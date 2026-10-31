"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createService } = require("../service");
const { decrypt, validateEnvelope, validateMedication } = require("../protocol");
const { VERSION, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");
const event = require("./medication-fixture");
const root = "demoEncryptedShares/fake-patient/clinics/clinic-a";
function setup() {
  const db = new MemoryDb(); fixture(db); let calls = 0;
  const keys = { publicKey: async () => ({ keyVersion: VERSION }),
    canWrite: (clinic, version) => clinic === "clinic-a" && version === VERSION,
    canRead: (clinic, version) => clinic === "clinic-a" && version === VERSION,
    unwrap: async (clinic, version, data) => { calls++; return unwrap(version, data); } };
  const service = createService({ db, keys, projectId: "innera-demo", type: "medications" });
  const envelope = epoch => encrypt({ type: "medications", payload: event, epoch });
  const publish = (epoch = 0) => service.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
    records: [{ id: "opaque-record", envelope: envelope(epoch + 1) }] }));
  const read = () => service.read(request("doctor", { uid: "fake-patient" }));
  return { db, keys, service, envelope, publish, read, calls: () => calls };
}
test("Medication share/read/revoke is scoped, encrypted, audited and leaves sleep consent unchanged", async () => {
  const s = setup();
  const sleepService = createService({ db: s.db, keys: s.keys, projectId: "innera-demo" });
  await sleepService.publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1,
    records: [{ id: "sleep-record", envelope: encrypt({ id: "sleep-record" }) }] }));
  const healthService = createService({ db: s.db, keys: s.keys, projectId: "innera-demo", type: "healthEvents" });
  await healthService.publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1,
    records: [{ id: "health-record", envelope: encrypt({ id: "health-record", type: "healthEvents", payload: require("./health-event-fixture") }) }] }));
  const checkService = createService({ db: s.db, keys: s.keys, projectId: "innera-demo", type: "checkIns" });
  await checkService.publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1,
    records: [{ id: "check-record", envelope: encrypt({ id: "check-record", type: "checkIns", payload: require("./check-in-fixture") }) }] }));
  const originalCheck = JSON.stringify(s.db.data.get(`${root}/scopes/checkIns`));
  const originalHealth = JSON.stringify(s.db.data.get(`${root}/scopes/healthEvents`));
  const originalSleep = JSON.stringify(s.db.data.get(root));
  await s.publish(); const result = await s.read();
  assert.ok(JSON.stringify(result.records) === JSON.stringify([event]), "Decrypted model matches synthetic schema");
  validateEnvelope(s.db.data.get(`${root}/medications/opaque-record`));
  const persisted = JSON.stringify([...s.db.data.values()]);
  for (const marker of [event.name, event.nameEn, event.note, event.ingredientLines[0], event.startDate, '"dose"', '"times"', '"intervalDays"'])
    assert.ok(!persisted.includes(marker), "No Medication plaintext in persisted state or audit");
  for (const [path, value] of s.db.data) if (path.startsWith("demoEncryptedAudit/")) {
    assert.ok(Object.keys(value).sort().join() === ["action", "result", "actorRef", "subjectRef", "at", "schemaVersion"].sort().join());
  }
  s.db.data.set(`${root}/scopes/medications/aiSummaries/current`, { ciphertext: "synthetic-summary" });
  await s.service.revoke(request("fake-patient"));
  assert.ok(!s.db.data.has(`${root}/medications/opaque-record`));
  assert.ok(!s.db.data.has(`${root}/scopes/medications/aiSummaries/current`));
  assert.equal(s.db.data.get(`${root}/scopes/medications`).summaryValid, false);
  assert.equal(JSON.stringify(s.db.data.get(root)), originalSleep);
  assert.equal((await sleepService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
  assert.equal(JSON.stringify(s.db.data.get(`${root}/scopes/healthEvents`)), originalHealth);
  assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
  assert.equal(JSON.stringify(s.db.data.get(`${root}/scopes/checkIns`)), originalCheck);
  assert.equal((await checkService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
  await assert.rejects(s.read, { code: "permission-denied" });
  await assert.rejects(() => s.publish(0), { code: "aborted" });
});
test("Medication AAD binds type, environment, patient, clinic, document, epoch and tag", async () => {
  const s = setup(), envelope = s.envelope(1);
  for (const [uid, clinic, id, env, type] of [
    ["other", "clinic-a", "opaque-record", envelope, "medications"],
    ["fake-patient", "other", "opaque-record", envelope, "medications"],
    ["fake-patient", "clinic-a", "other", envelope, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, epoch: 2 }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", envelope, "sleepRecords"],
    ["fake-patient", "clinic-a", "opaque-record", envelope, "healthEvents"],
    ["fake-patient", "clinic-a", "opaque-record", envelope, "checkIns"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, ciphertext: Buffer.alloc(20).toString("base64") }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, schemaVersion: 2 }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, algorithm: "other" }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, wrappingAlgorithm: "other" }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, authenticationTag: Buffer.alloc(16).toString("base64") }, "medications"],
    ["fake-patient", "clinic-a", "opaque-record", { ...envelope, keyVersion: VERSION.replace("innera-demo", "production") }, "medications"],
  ]) await assert.rejects(() => decrypt(uid, clinic, id, env, unwrap, type));
});
test("Medication non-doctor, inactive, cross-clinic, missing consent and App Check fail before KMS", async () => {
  for (const mutate of [
    s => s.db.data.set("clinics/clinic-a", { status: "inactive" }),
    s => { const f = s.db.data.get("demoEncryptedFixtures/fake-patient"); s.db.data.set(`inneraPatients/${f.patientId}`, { linked: false }); },
    s => s.db.data.set("clinicStaff/doctor", { role: "nurse", active: true, clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", active: false, clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", active: true, clinicId: "other" }),
    s => s.db.data.set(`${root}/scopes/medications`, { active: false, epoch: 1 }),
  ]) { const s = setup(); await s.publish(); mutate(s); await assert.rejects(s.read, { code: "permission-denied" }); assert.equal(s.calls(), 0); }
  const s = setup(); await assert.rejects(s.read, { code: "permission-denied" });
  const req = request("doctor", { uid: "fake-patient" }); delete req.app;
  await assert.rejects(() => s.service.read(req), { code: "failed-precondition" }); assert.equal(s.calls(), 0);
});
test("Medication revocation during KMS and audit failure discard plaintext", async () => {
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
test("Medication schema rejects invalid dose and plaintext envelope fields", () => {
  assert.throws(() => validateMedication({ ...event, dose: -1 }));
  assert.throws(() => validateEnvelope({ ...setup().envelope(1), note: "synthetic" }));
});
test("Medication operations never log payloads or keys", async t => {
  const spies = ["log", "warn", "error", "info", "debug"].map(name => t.mock.method(console, name, () => {}));
  const s = setup(); await s.publish(); await s.read(); await s.service.revoke(request("fake-patient"));
  assert.ok(spies.every(spy => spy.mock.callCount() === 0), "No application log output");
});

test("Medication supports actual oral, PRN, injection, drops, schedule and inactive variants without invented fields", async () => {
  const variants = [event, { ...event, times: ["需要時"] }, { ...event, type: "injection", intervalDays: 28, times: [] },
    { ...event, type: "drops", concentrationMg: 10, concentrationMl: 1, intakeMl: 1 },
    { ...event, scheduleType: "intervalDays", scheduleIntervalDays: 2, scheduleAnchorDate: event.startDate },
    { ...event, scheduleType: "weekdays", weekdays: [1, 3] },
    { ...event, isActive: false, lastChangeAt: event.updatedAt, resumedAt: null }];
  for (const payload of variants) {
    const envelope = encrypt({ type: "medications", payload });
    const result = await decrypt("fake-patient", "clinic-a", "opaque-record", envelope, unwrap, "medications");
    assert.ok(JSON.stringify(result) === JSON.stringify(payload), "Actual medication schema round-trips");
  }
  for (const extra of [{ prn: true }, { discontinuedDate: event.startDate }, { genericName: "invented" }, { medicationId: "opaque" }])
    assert.throws(() => validateMedication({ ...event, ...extra }));
});
