"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createService } = require("../service");
const { decrypt, validateEnvelope, validateHealthEvent } = require("../protocol");
const { VERSION, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");
const event = require("./health-event-fixture");
const root = "demoEncryptedShares/fake-patient/clinics/clinic-a";
function setup() {
  const db = new MemoryDb(); fixture(db); let calls = 0;
  const keys = { publicKey: async () => ({ keyVersion: VERSION }),
    canWrite: (clinic, version) => clinic === "clinic-a" && version === VERSION,
    canRead: (clinic, version) => clinic === "clinic-a" && version === VERSION,
    unwrap: async (clinic, version, data) => { calls++; return unwrap(version, data); } };
  const service = createService({ db, keys, projectId: "innera-demo", type: "healthEvents" });
  const envelope = epoch => encrypt({ type: "healthEvents", payload: event, epoch });
  const publish = (epoch = 0) => service.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
    records: [{ id: "opaque-record", envelope: envelope(epoch + 1) }] }));
  const read = () => service.read(request("doctor", { uid: "fake-patient" }));
  return { db, keys, service, envelope, publish, read, calls: () => calls };
}
test("HealthEvent share/read/revoke is scoped, encrypted, audited and leaves sleep consent unchanged", async () => {
  const s = setup();
  const sleepService = createService({ db: s.db, keys: s.keys, projectId: "innera-demo" });
  await sleepService.publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1,
    records: [{ id: "sleep-record", envelope: encrypt({ id: "sleep-record" }) }] }));
  const originalSleep = JSON.stringify(s.db.data.get(root));
  await s.publish(); const result = await s.read();
  assert.ok(JSON.stringify(result.records) === JSON.stringify([event]), "Decrypted model matches synthetic schema");
  validateEnvelope(s.db.data.get(`${root}/healthEvents/opaque-record`));
  const persisted = JSON.stringify([...s.db.data.values()]);
  for (const marker of [event.note, event.context, event.symptoms[0].name, '"severity"', '"timestamp"'])
    assert.ok(!persisted.includes(marker), "No HealthEvent plaintext in persisted state or audit");
  for (const [path, value] of s.db.data) if (path.startsWith("demoEncryptedAudit/")) {
    assert.ok(Object.keys(value).sort().join() === ["action", "result", "actorRef", "subjectRef", "at", "schemaVersion"].sort().join());
  }
  s.db.data.set(`${root}/scopes/healthEvents/aiSummaries/current`, { ciphertext: "synthetic-summary" });
  await s.service.revoke(request("fake-patient"));
  assert.ok(!s.db.data.has(`${root}/healthEvents/opaque-record`));
  assert.ok(!s.db.data.has(`${root}/scopes/healthEvents/aiSummaries/current`));
  assert.equal(s.db.data.get(`${root}/scopes/healthEvents`).summaryValid, false);
  assert.equal(JSON.stringify(s.db.data.get(root)), originalSleep);
  assert.equal((await sleepService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
  await assert.rejects(s.read, { code: "permission-denied" });
  await assert.rejects(() => s.publish(0), { code: "aborted" });
});
test("HealthEvent AAD binds type, environment, patient, clinic, document, epoch and tag", async () => {
  const s = setup(), envelope = s.envelope(1);
  for (const [uid, clinic, id, env, type] of [
    ["other", "clinic-a", "opaque-record", envelope, "healthEvents"],
    ["fake-patient", "other", "opaque-record", envelope, "healthEvents"],
    ["fake-patient", "clinic-a", "other", envelope, "healthEvents"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, epoch: 2 }, "healthEvents"],
    ["fake-patient", "clinic-a", "opaque-record", envelope, "sleepRecords"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, authenticationTag: Buffer.alloc(16).toString("base64") }, "healthEvents"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, keyVersion: VERSION.replace("innera-demo", "production") }, "healthEvents"],
  ]) await assert.rejects(() => decrypt(uid, clinic, id, env, unwrap, type));
});
test("HealthEvent non-doctor, inactive, cross-clinic, missing consent and App Check fail before KMS", async () => {
  for (const mutate of [
    s => s.db.data.set("clinicStaff/doctor", { role: "nurse", active: true, clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", active: false, clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", active: true, clinicId: "other" }),
    s => s.db.data.set(`${root}/scopes/healthEvents`, { active: false, epoch: 1 }),
  ]) { const s = setup(); await s.publish(); mutate(s); await assert.rejects(s.read, { code: "permission-denied" }); assert.equal(s.calls(), 0); }
  const s = setup(); await assert.rejects(s.read, { code: "permission-denied" });
  const req = request("doctor", { uid: "fake-patient" }); delete req.app;
  await assert.rejects(() => s.service.read(req), { code: "failed-precondition" }); assert.equal(s.calls(), 0);
});
test("HealthEvent revocation during KMS and audit failure discard plaintext", async () => {
  for (const during of ["revoke", "audit"]) {
    const s = setup(); await s.publish();
    const normal = s.keys.unwrap;
    s.keys.unwrap = async (...args) => {
      if (during === "revoke") await s.service.revoke(request("fake-patient"));
      else s.db.failAudit = true;
      return normal(...args);
    };
    await assert.rejects(s.read);
  }
});
test("HealthEvent schema rejects invalid severity and plaintext envelope fields", () => {
  assert.throws(() => validateHealthEvent({ ...event, symptoms: [{ name: "synthetic", severity: 9 }] }));
  assert.throws(() => validateEnvelope({ ...setup().envelope(1), note: "synthetic" }));
});
test("HealthEvent operations never log payloads or keys", async t => {
  const spies = ["log", "warn", "error", "info", "debug"].map(name => t.mock.method(console, name, () => {}));
  const s = setup(); await s.publish(); await s.read(); await s.service.revoke(request("fake-patient"));
  assert.ok(spies.every(spy => spy.mock.callCount() === 0), "No application log output");
});
