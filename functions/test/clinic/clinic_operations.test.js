"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { loadPlatform, memoryDb, seed } = require("./platform_test_support.cjs");
const operations = () => ({
  contactName: "Test contact", contactTitle: "Office", contactEmail: "contact@example.test",
  contactPhone: "+886 2 0000 #3", clinicType: "psychiatry_clinic",
  cooperationNotes: "<b>literal plain text</b>",
});
const request = (data, auth = { uid: "platform" }) => ({ auth, data });
const plain = data => JSON.parse(JSON.stringify(data));
for (const source of ["functions", "functions_demo"]) {
  function setup(docs = seed(), mode = {}) {
    const memory = memoryDb(docs, mode);
    return { ...memory, ...loadPlatform(source, memory.db, { rawHandlers: true }) };
  }
  const update = (app, patch = {}) => app.functions.updateClinicOperations(request({
    clinicId: "a", operations: operations(), expectedRevision: 0, ...patch,
  }));
  const audits = app => Object.entries(app.docs()).filter(([key]) => key.startsWith("auditLogs/")).map(([, data]) => data);
  test(`${source}: missing operations, create/read/update/clear preserve clinics`, async () => {
    const docs = seed(); docs["clinics/a"].name = "Clinic";
    const app = setup(docs);
    const initial = await app.functions.getClinicDetails(request({ clinicId: "a" }));
    assert.equal(initial.operations, null); assert.equal(initial.revision, 0);
    assert.equal(initial.updatedAt, null);
    assert.equal(audits(app).length, 0);
    const created = await update(app);
    assert.equal(created.revision, 1);
    assert.equal(typeof created.updatedAt.seconds, "number");
    assert.deepEqual(plain((await app.functions.getClinicDetails(request({ clinicId: "a" }))).updatedAt), plain(created.updatedAt));
    assert.deepEqual(plain(created.operations), operations());
    assert.deepEqual(plain((await app.functions.getClinicDetails(request({ clinicId: "a" }))).operations), operations());
    await update(app, { expectedRevision: 1, operations: { ...operations(), contactName: "  Revised  " } });
    assert.equal(app.docs()["clinicOperations/a"].contactName, "Revised");
    const empty = Object.fromEntries(Object.keys(operations()).map(key => [key, ""]));
    assert.equal((await update(app, { expectedRevision: 2, operations: empty })).revision, 3);
    assert.deepEqual(plain((await app.functions.getClinicDetails(request({ clinicId: "a" }))).operations), empty);
    assert.deepEqual(app.docs()["clinics/a"], docs["clinics/a"]);
    assert.equal(app.docs()["clinicOperations/a"].createdBy, "platform");
    assert.equal(app.docs()["clinicOperations/a"].schemaVersion, 1);
    assert.equal(audits(app).length, 3);
    for (const audit of audits(app)) {
      assert.equal(audit.action, "clinic.operations.update");
      assert.equal(audit.targetType, "clinicOperations");
      assert.deepEqual(Object.keys(audit.after), ["revision"]);
      for (const value of Object.values(operations())) assert.ok(!JSON.stringify(audit).includes(value));
    }
  });
  for (const name of ["getClinicDetails", "updateClinicOperations"]) {
    test(`${source}/${name}: rejects unauthorized and transaction-time revocation`, async () => {
      for (const kind of ["missing", "inactive", "wrong-role", "unauthenticated", "revoke"]) {
        const docs = seed();
        if (kind === "missing") delete docs["platformAdmins/platform"];
        if (kind === "inactive") docs["platformAdmins/platform"].status = "inactive";
        if (kind === "wrong-role") docs["platformAdmins/platform"].role = "admin";
        const app = setup(docs, { revoke: kind === "revoke" });
        const data = name === "getClinicDetails" ? { clinicId: "a" } : { clinicId: "a", operations: operations(), expectedRevision: 0 };
        await assert.rejects(app.functions[name](request(data, kind === "unauthenticated" ? null : { uid: "platform" })),
          { code: kind === "unauthenticated" ? "unauthenticated" : "permission-denied" });
        assert.equal(app.docs()["clinicOperations/a"], undefined);
        assert.equal(audits(app).length, 0);
      }
    });
    test(`${source}/${name}: nonexistent clinic is not empty operations`, async () => {
      const app = setup();
      const data = name === "getClinicDetails" ? { clinicId: "missing" } :
        { clinicId: "missing", operations: operations(), expectedRevision: 0 };
      await assert.rejects(app.functions[name](request(data)), { code: "not-found" });
      assert.equal(audits(app).length, 0);
    });
  }
  test(`${source}: denies unknown/system fields, missing fields and wrong types`, async () => {
    const candidates = [null, [], "text", { ...operations(), status: "active" },
      { ...operations(), revision: 20 }, { ...operations(), createdBy: "someone" }];
    for (const key of Object.keys(operations())) {
      const missing = operations(); delete missing[key]; candidates.push(missing);
      for (const value of [null, 1, true, {}, []]) candidates.push({ ...operations(), [key]: value });
    }
    for (const input of candidates) {
      const app = setup();
      await assert.rejects(update(app, { operations: input }), { code: "invalid-argument" });
      assert.equal(app.attempts(), 0);
    }
    for (const patch of [{ status: "active" }, { clinicId: 3 }, { clinicId: "a/b" }, { clinicId: ".." },
      { clinicId: "" }, { clinicId: " a " }, { clinicId: "__id__" }, { clinicId: "院".repeat(501) },
      ...[-1, 1.5, "0", null, Number.MAX_SAFE_INTEGER].map(expectedRevision => ({ expectedRevision }))]) {
      await assert.rejects(update(setup(), patch), { code: "invalid-argument" });
    }
    await assert.rejects(setup().functions.getClinicDetails(request({ clinicId: "a", extra: true })), { code: "invalid-argument" });
  });
  test(`${source}: enforces raw UTF-16 lengths, email and exact type enum`, async () => {
    for (const [key, max] of Object.entries({ contactName: 100, contactTitle: 100, contactEmail: 254, contactPhone: 50, cooperationNotes: 3000 })) {
      const value = key === "contactEmail" ? "a".repeat(max - 9) + "@test.com" : "x".repeat(max);
      await update(setup(), { operations: { ...operations(), [key]: value } });
      await assert.rejects(update(setup(), { operations: { ...operations(), [key]: value + "  " } }), { code: "invalid-argument" });
    }
    for (const clinicType of ["", "psychiatry_clinic", "other_clinic", "hospital", "counseling_center", "psychotherapy_center", "other"]) {
      await update(setup(), { operations: { ...operations(), clinicType } });
    }
    await assert.rejects(update(setup(), { operations: { ...operations(), clinicType: "clinic" } }), { code: "invalid-argument" });
    await assert.rejects(update(setup(), { operations: { ...operations(), contactEmail: "invalid@" } }), { code: "invalid-argument" });
    await assert.rejects(update(setup(), { operations: { ...operations(), contactName: "😀".repeat(51) } }), { code: "invalid-argument" });
  });
  test(`${source}: inactive clinic allowed, only whitelisted details returned`, async () => {
    const docs = seed();
    docs["clinics/a"] = { ...docs["clinics/a"], status: "inactive", clinicName: "Legacy", code: "CL01", secret: "DO_NOT_RETURN" };
    const app = setup(docs);
    await update(app);
    const result = await app.functions.getClinicDetails(request({ clinicId: "a" }));
    assert.deepEqual(Object.keys(result.clinic).sort(), ["clinicName", "code", "status", "createdAt"].sort());
    assert.equal(result.clinic.status, "inactive");
    assert.deepEqual(app.docs()["clinics/a"], docs["clinics/a"]);
  });
  test(`${source}: conflict rejects overwrite; retry commits one revision/audit`, async () => {
    const app = setup(seed(), { retry: true });
    await update(app);
    assert.equal(app.attempts(), 2);
    assert.equal(app.random.requests, 1);
    assert.equal(audits(app).length, 1);
    const before = plain(app.docs());
    await assert.rejects(update(app), error => error.code === "failed-precondition" &&
      error.details.reason === "revision-conflict" && error.details.currentRevision === 1);
    assert.deepEqual(plain(app.docs()), before);
  });
  test(`${source}: audit failure rolls back operations and omits sensitive logs`, async () => {
    const app = setup(seed(), { auditFailure: true });
    await assert.rejects(update(app), { code: "internal" });
    assert.equal(app.docs()["clinicOperations/a"], undefined);
    assert.equal(audits(app).length, 0);
    for (const value of Object.values(operations())) assert.ok(!JSON.stringify(app.logs).includes(value));
  });
  test(`${source}: malformed stored schema/revision fails instead of resetting`, async () => {
    for (const patch of [{ revision: 0, schemaVersion: 1 }, { revision: 1, schemaVersion: 2 }, { revision: "1", schemaVersion: 1 }]) {
      const docs = seed(); docs["clinicOperations/a"] = { ...operations(), ...patch };
      const app = setup(docs);
      await assert.rejects(update(app), { code: "failed-precondition" });
      await assert.rejects(app.functions.getClinicDetails(request({ clinicId: "a" })), { code: "failed-precondition" });
      assert.deepEqual(app.docs()["clinicOperations/a"], docs["clinicOperations/a"]);
    }
  });
}
test("Production/Demo implementation parity and callable exports", () => {
  for (const file of ["clinics.js", "platform_audit.js"]) {
    const base = path.resolve(__dirname, "../../..");
    assert.equal(fs.readFileSync(path.join(base, "functions/src/clinic", file), "utf8"),
      fs.readFileSync(path.join(base, "functions_demo/src/clinic", file), "utf8"));
  }
  for (const source of ["functions", "functions_demo"]) {
    const entry = fs.readFileSync(path.resolve(__dirname, "../../..", source, "index.js"), "utf8");
    for (const name of ["getClinicDetails", "updateClinicOperations"]) assert.ok(entry.includes(`exports.${name} =`));
  }
});
