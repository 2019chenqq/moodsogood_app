"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { loadPlatform, memoryDb, seed } = require("./platform_test_support.cjs");
const { evaluateTrial } = require("../../src/clinic/clinic_trial");
const plain = value => JSON.parse(JSON.stringify(value));
const trial = (startDate, resolution = null) => ({ schemaVersion: 1, startDate,
  durationDays: 84, timeZone: "Asia/Taipei", resolution,
  resolvedAt: null, resolvedBy: null, resolutionReason: null });

test("calendar: 84 days, year rollover, leap year, all six states and Taipei midnight", () => {
  assert.equal(evaluateTrial(undefined, 0).status, "not_configured");
  for (const [start, end, last] of [["2026-10-27", "2027-01-19", "2027-01-18"],
    ["2024-01-01", "2024-03-25", "2024-03-24"], ["2025-01-01", "2025-03-26", "2025-03-25"]]) {
    const at = date => Date.parse(`${date}T00:00:00+08:00`);
    const t = trial(start), first = evaluateTrial(t, at(start));
    assert.equal(first.status, "active"); assert.equal(first.remainingDays, 84);
    assert.equal(first.endDateExclusive, end); assert.equal(first.lastTrialDate, last);
    assert.equal(first.expiresAtMillis, at(end));
    assert.equal(evaluateTrial(t, at(start) - 1).status, "scheduled");
    assert.equal(evaluateTrial(t, at(end) - 1).remainingDays, 1);
    assert.equal(evaluateTrial(t, at(end)).status, "expired");
    assert.equal(evaluateTrial(t, at(end)).remainingDays, 0);
    for (const resolution of ["converted", "terminated"]) {
      const ended = evaluateTrial(trial(start, resolution), at(end));
      assert.equal(ended.status, resolution); assert.equal(ended.remainingDays, null);
    }
  }
});

for (const source of ["functions", "functions_demo"]) {
  function setup(docs = seed(), mode = {}, instant = "2026-10-27T04:00:00Z") {
    let now = Date.parse(instant), calls = 0;
    class Clock extends Date { static now() { calls++; return now; } }
    const memory = memoryDb(docs, mode);
    return { ...memory, ...loadPlatform(source, memory.db, { rawHandlers: true, Date: Clock }),
      clock: value => { now = Date.parse(value); }, calls: () => calls };
  }
  const request = (data, auth = { uid: "platform" }) => ({ data, auth });
  const update = (app, patch = {}, auth) => app.functions.updateClinicTrial(request({
    clinicId: "a", expectedRevision: 0, action: "setStart", startDate: "2026-10-28", ...patch,
  }, auth));
  const close = (app, action, revision = 1, reason = "  Pilot decision  ") =>
    app.functions.updateClinicTrial(request({ clinicId: "a", expectedRevision: revision, action, reason }));
  const read = app => app.functions.getClinicDetails(request({ clinicId: "a" }));
  const audits = app => Object.entries(app.docs()).filter(([key]) => key.startsWith("auditLogs/")).map(([, v]) => v);
  const unchanged = async (app, operation, code = "failed-precondition") => {
    const before = plain(app.docs()); await assert.rejects(operation(), { code });
    assert.deepEqual(plain(app.docs()), before);
  };

  test(`${source}: read missing trial is side effect free; creates F1 compatible document`, async () => {
    const app = setup(), before = plain(app.docs());
    const initial = await read(app);
    assert.equal(initial.trial, null); assert.equal(initial.trialComputed.status, "not_configured");
    assert.equal(initial.operations, null); assert.deepEqual(plain(app.docs()), before);
    const saved = await update(app);
    assert.equal(saved.revision, 1); assert.equal(saved.trialComputed.status, "scheduled");
    assert.equal(saved.evaluatedAt.seconds, Date.parse("2026-10-27T04:00:00Z") / 1000);
    assert.equal(app.calls(), 2);
    assert.deepEqual(plain(saved.trial), plain((await read(app)).trial));
    assert.deepEqual(plain(saved.updatedAt), plain(saved.trial.updatedAt));
    assert.equal(Object.values((await read(app)).operations).filter(v => v === "").length, 6);
    assert.equal(app.docs()["clinicOperations/a"].schemaVersion, 1);
    assert.equal(audits(app)[0].targetType, "clinicOperations");
    assert.equal(audits(app)[0].action, "clinic.trial.set_start");
  });
  test(`${source}: preserves F1 fields, trial, clinic and medical documents in both directions`, async () => {
    const docs = seed(); docs["patients/test"] = { access: "unchanged" };
    const app = setup(docs);
    const operations = { contactName: "A", contactTitle: "B", contactEmail: "a@example.test",
      contactPhone: "123", clinicType: "hospital", cooperationNotes: "C" };
    await app.functions.updateClinicOperations(request({ clinicId: "a", expectedRevision: 0, operations }));
    await update(app, { expectedRevision: 1 });
    assert.deepEqual(plain((await read(app)).operations), operations);
    const savedTrial = plain(app.docs()["clinicOperations/a"].trial);
    await app.functions.updateClinicOperations(request({ clinicId: "a", expectedRevision: 2, operations }));
    assert.deepEqual(plain(app.docs()["clinicOperations/a"].trial), savedTrial);
    app.clock("2027-02-01T00:00:00Z");
    assert.equal((await read(app)).trialComputed.status, "expired");
    await close(app, "convert", 3);
    assert.deepEqual(plain((await read(app)).operations), operations);
    for (const [key, value] of Object.entries(docs)) assert.deepEqual(plain(app.docs()[key]), value);
  });
  test(`${source}: reschedule and manual closure from scheduled, active and expired`, async () => {
    for (const instant of ["2026-10-27T04:00:00Z", "2026-10-29T04:00:00Z", "2027-02-01T04:00:00Z"]) {
      for (const action of ["convert", "terminate"]) {
        const app = setup(); await update(app);
        await update(app, { startDate: "2026-10-29", expectedRevision: 1 });
        assert.equal(audits(app)[1].action, "clinic.trial.reschedule");
        app.clock(instant); const result = await close(app, action, 2);
        assert.equal(result.trialComputed.status, action === "convert" ? "converted" : "terminated");
        assert.equal(result.trial.resolutionReason, "Pilot decision");
        assert.deepEqual(plain(result.trial.resolvedAt), plain(result.updatedAt));
        assert.equal(audits(app)[2].after.resolutionReason, "Pilot decision");
        for (const next of ["convert", "terminate"]) await unchanged(app, () => close(app, next, 3));
        await unchanged(app, () => update(app, { expectedRevision: 3 }));
        assert.equal(app.docs()["clinics/a"].status, "active");
      }
    }
  });
  test(`${source}: rejects invalid dates, extra fields, bad reasons and revisions without writes`, async () => {
    for (const startDate of ["2026-02-29", "2024-02-30", "2026-13-01", "2026-1-01", "2026-10-27T00:00:00Z", " 2026-10-27", null, 123]) {
      const app = setup(); await unchanged(app, () => update(app, { startDate }), "invalid-argument");
    }
    for (const patch of [{ durationDays: 100 }, { status: "active" }, { clinicId: "a/b" },
      { action: "extend" }, ...[-1, 0.5, "0", null].map(expectedRevision => ({ expectedRevision }))]) {
      const app = setup(); await unchanged(app, () => update(app, patch), "invalid-argument");
    }
    for (const reason of ["", "  ", "x".repeat(501), null, 42]) {
      const app = setup(); await update(app); await unchanged(app, () => close(app, "convert", 1, reason), "invalid-argument");
    }
    const app = setup(); await update(app); await close(app, "convert", 1, "x".repeat(500));
  });
  test(`${source}: rejects past dates, unchanged dates, started reschedules, missing trial and conflicts`, async () => {
    const app = setup();
    await unchanged(app, () => update(app, { startDate: "2026-10-26" }));
    await unchanged(app, () => close(app, "convert", 0));
    await update(app);
    await unchanged(app, () => update(app, { expectedRevision: 1 }));
    await unchanged(app, () => update(app));
    app.clock("2026-10-27T16:00:00Z");
    await unchanged(app, () => update(app, { expectedRevision: 1, startDate: "2026-11-01" }));
    const missing = setup();
    await unchanged(missing, () => update(missing, { clinicId: "missing" }), "not-found");
  });
  test(`${source}: rejects unauthenticated, non-admin, inactive and transaction-time revoked admin`, async () => {
    for (const kind of ["unauthenticated", "missing", "inactive", "wrong-role", "revoke"]) {
      const docs = seed();
      if (kind === "missing") delete docs["platformAdmins/platform"];
      if (kind === "inactive") docs["platformAdmins/platform"].status = "inactive";
      if (kind === "wrong-role") docs["platformAdmins/platform"].role = "admin";
      const app = setup(docs, { revoke: kind === "revoke" });
      await assert.rejects(update(app, {}, kind === "unauthenticated" ? null : { uid: "platform" }),
        { code: kind === "unauthenticated" ? "unauthenticated" : "permission-denied" });
      assert.equal(app.docs()["clinicOperations/a"], undefined); assert.equal(audits(app).length, 0);
    }
  });
  test(`${source}: simulated retry commits one audit; simulated audit failure rolls back`, async () => {
    const app = setup(seed(), { retry: true }); await update(app);
    assert.equal(app.attempts(), 2); assert.equal(app.calls(), 2);
    assert.equal(audits(app).length, 1); assert.equal(app.docs()["clinicOperations/a"].revision, 1);
    const failed = setup(seed(), { auditFailure: true });
    await unchanged(failed, () => update(failed), "internal");
    assert.ok(!JSON.stringify(failed.logs).includes("PRIVATE_TOKEN"));
  });
  test(`${source}: malformed stored trial fails closed`, async () => {
    for (const bad of [null, {}, { ...trial("2026-10-28"), durationDays: 90 },
      { ...trial("2026-10-28"), resolution: "active" }]) {
      const docs = seed(); docs["clinicOperations/a"] = { schemaVersion: 1, revision: 1, trial: bad };
      const app = setup(docs);
      await unchanged(app, () => read(app));
      await unchanged(app, () => update(app, { expectedRevision: 1 }));
    }
  });
}
test("trial source parity and exported callable", () => {
  const root = path.resolve(__dirname, "../../..");
  for (const file of ["clinics.js", "platform_audit.js", "clinic_trial.js"]) {
    assert.equal(fs.readFileSync(path.join(root, "functions/src/clinic", file), "utf8"),
      fs.readFileSync(path.join(root, "functions_demo/src/clinic", file), "utf8"));
  }
  for (const source of ["functions", "functions_demo"]) {
    assert.ok(fs.readFileSync(path.join(root, source, "index.js"), "utf8").includes("exports.updateClinicTrial ="));
  }
});
