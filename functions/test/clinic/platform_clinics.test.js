"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { loadPlatform, memoryDb, seed, requests, request } = require("./platform_test_support.cjs");
const names = Object.keys(requests);
function setup(docs = seed(), mode = {}) {
  const store = memoryDb(docs, mode);
  return { ...store, ...loadPlatform("functions", store.db, { rawHandlers: true }) };
}
const audits = app => Object.entries(app.docs()).filter(([key]) => key.startsWith("auditLogs/")).map(([, value]) => value);

for (const name of names) {
  test(`${name}: rejects missing, inactive, wrong-role and unauthenticated identities`, async () => {
    for (const kind of ["missing", "inactive", "wrong-role", "unauthenticated"]) {
      const docs = seed();
      if (kind === "missing") delete docs["platformAdmins/platform"];
      if (kind === "inactive") docs["platformAdmins/platform"].status = "inactive";
      if (kind === "wrong-role") docs["platformAdmins/platform"].role = "admin";
      const app = setup(docs);
      const input = request(name); if (kind === "unauthenticated") delete input.auth;
      await assert.rejects(app.functions[name](input), { code: kind === "unauthenticated" ? "unauthenticated" : "permission-denied" });
      assert.equal(app.attempts(), 0);
      assert.equal(audits(app).length, 0);
      assert.equal(app.logs[0][1].result, "denied");
    }
  });
  test(`${name}: rechecks authorization inside transaction`, async () => {
    const app = setup(seed(), { revoke: true });
    await assert.rejects(app.functions[name](request(name)), { code: "permission-denied" });
    assert.equal(audits(app).length, 0);
    assert.equal(app.docs()["inneraCounters/clinic"].value, 8);
    assert.equal(app.docs()["clinics/a"].status, "active");
    assert.equal(app.docs()["staffInvites/invite-a"].tokenHash, "old-hash");
  });
  test(`${name}: callback retries allocate randomness once and commit one audit`, async () => {
    const app = setup(seed(), { retry: true });
    const result = await app.functions[name](request(name));
    assert.equal(result.success, true);
    assert.equal(app.attempts(), 2);
    assert.equal(audits(app).length, 1);
    assert.equal(app.random.requests, 1);
    assert.equal(app.random.tokens, name === "setClinicStatus" ? 0 : 1);
    assert.equal(app.logs.length, 0);
    if (name === "createClinic") assert.equal(app.docs()["inneraCounters/clinic"].value, 9);
    if (name === "resendInitialAdminInvite") assert.equal(app.docs()["staffInvites/invite-a"].resendCount, 3);
    assert.ok(!JSON.stringify(audits(app)).includes(result.token || "UNUSED_SENTINEL"));
  });
  test(`${name}: failure logs omit raw error/token and never record success`, async () => {
    const app = setup(seed(), { auditFailure: true });
    await assert.rejects(app.functions[name](request(name, { token: "PRIVATE_TOKEN_DO_NOT_LOG", password: "PRIVATE_PASSWORD" })), { code: "internal" });
    assert.equal(audits(app).length, 0);
    assert.equal(app.logs.length, 1);
    assert.equal(app.logs[0][1].result, "failure");
    assert.ok(!JSON.stringify(app.logs).includes("PRIVATE_"));
  });
}

test("same status returns compatible no-op without timestamp or audit changes", async () => {
  const app = setup();
  const result = await app.functions.setClinicStatus(request("setClinicStatus", { status: "active" }));
  assert.equal(result.success, true); assert.equal(result.clinicId, "a"); assert.equal(result.status, "active"); assert.equal(result.changed, false);
  assert.equal(audits(app).length, 0); assert.equal(app.docs()["clinics/a"].updatedAt, undefined);
});

test("resend retains invitation ownership, role, pending state, recipient and active clinic checks", async () => {
  for (const [target, patch] of [
    ["clinics/a", { status: "inactive" }], ["clinics/a", { primaryAdminUid: "existing" }],
    ["staffInvites/invite-a", { clinicId: "other" }], ["staffInvites/invite-a", { role: "doctor" }],
    ["staffInvites/invite-a", { status: "accepted" }], ["staffInvites/invite-a", { inviteType: "staff" }],
    ["staffInvites/invite-a", { email: "invalid" }], ["staffInvites/invite-a", { resendCount: -1 }],
  ]) {
    const docs = seed(); Object.assign(docs[target], patch); const app = setup(docs);
    await assert.rejects(app.functions.resendInitialAdminInvite(request("resendInitialAdminInvite")), { code: "failed-precondition" });
    assert.equal(audits(app).length, 0);
  }
  const app = setup();
  const result = await app.functions.resendInitialAdminInvite(request("resendInitialAdminInvite", { email: "attacker@example.test", role: "doctor" }));
  assert.equal(result.adminEmail, "owner@example.test");
  assert.equal(app.docs()["staffInvites/invite-a"].role, "admin");
  assert.equal(app.docs()["staffInvites/invite-a"].email, "owner@example.test");
  assert.equal(audits(app)[0].eventType, "invitation_rotated");
});

test("invalid status and path identifiers fail without writes", async () => {
  for (const [name, data] of [["setClinicStatus", { status: "deleted" }], ["setClinicStatus", { clinicId: "a/b" }], ["resendInitialAdminInvite", { clinicId: "a/b" }]]) {
    const app = setup(); await assert.rejects(app.functions[name](request(name, data)), { code: "invalid-argument" });
    assert.equal(audits(app).length, 0);
  }
});

test("audit state is a whitelist, not a copy of business data", () => {
  const app = setup(); let entry;
  app.helper.appendPlatformAudit({ create: (_, data) => { entry = data; } }, { actorUid: "platform", requestId: "request", auditRef: {} }, {
    action: "clinic.disable", targetId: "a", targetClinicId: "a",
    before: { status: "active", token: "SECRET", password: "SECRET", email: "SECRET" },
    after: { status: "inactive", token: "SECRET" },
  });
  assert.equal(JSON.stringify(entry).includes("SECRET"), false);
  assert.deepEqual(Object.keys(entry.before), ["status"]);
});

test("Production/Demo implementation and callable region/export contracts match", () => {
  const root = path.resolve(__dirname, "../../..");
  for (const file of ["clinics.js", "platform_audit.js"]) {
    assert.equal(fs.readFileSync(path.join(root, "functions/src/clinic", file), "utf8"), fs.readFileSync(path.join(root, "functions_demo/src/clinic", file), "utf8"));
  }
  for (const source of ["functions", "functions_demo"]) {
    const app = loadPlatform(source, memoryDb(seed()).db);
    assert.deepEqual(Object.keys(app.functions).sort(), [...names, "getClinicDetails", "updateClinicOperations", "updateClinicTrial"].sort());
    for (const fn of Object.values(app.functions)) {
      assert.deepEqual(fn.__endpoint.region, ["asia-east1"]);
      assert.ok(fn.__endpoint.callableTrigger);
    }
  }
});
