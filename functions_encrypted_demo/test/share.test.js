"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createService } = require("../service");
const { decrypt, validateEnvelope } = require("../protocol");
const { VERSION, sleep, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");
const root = "demoEncryptedShares/fake-patient/clinics/clinic-a";
function setup() {
  const db = new MemoryDb(); fixture(db);
  let keyCalls = 0;
  const keys = {
    canRead: (clinic, version) => clinic === "clinic-a" && [VERSION, VERSION.replace(/1$/, "2")].includes(version),
    canWrite: (clinic, version) => clinic === "clinic-a" && version === VERSION,
    publicKey: async () => ({ keyVersion: VERSION }),
    unwrap: async (clinic, version, bytes) => { keyCalls++; return unwrap(version, bytes); },
  };
  const service = createService({ db, keys, projectId: "innera-demo" });
  const publish = (epoch = 0) => service.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1, records: [{ id: "opaque-record", envelope: encrypt({ epoch: epoch + 1 }) }] }));
  const read = () => service.read(request("doctor", { uid: "fake-patient" }));
  const revoke = () => service.revoke(request("fake-patient"));
  return { db, keys, service, publish, read, revoke, keyCalls: () => keyCalls };
}
test("complete synthetic share/read/revoke flow keeps storage and audit free of medical plaintext", async () => {
  const s = setup(); await s.publish();
  assert.deepEqual((await s.read()).records, [sleep]);
  const stored = s.db.data.get(`${root}/sleepRecords/opaque-record`);
  validateEnvelope(stored);
  assert.equal(JSON.stringify([...s.db.data.values()]).includes("合成測試紀錄"), false);
  s.db.data.set(`${root}/aiSummaries/current`, { ciphertext: "synthetic-old-summary" });
  await s.revoke();
  assert.equal(s.db.data.has(`${root}/aiSummaries/current`), false);
  assert.equal(s.db.data.has(`${root}/sleepRecords/opaque-record`), false);
  const calls = s.keyCalls();
  await assert.rejects(s.read, { code: "permission-denied" });
  assert.equal(s.keyCalls(), calls);
  await assert.rejects(() => s.publish(0), { code: "aborted" });
  await s.publish(2); assert.equal((await s.read()).epoch, 3);
});
test("unauthenticated, missing App Check, anonymous, admin/nurse, inactive and cross-clinic are rejected before key access", async () => {
  for (const change of [
    s => s.db.data.set("clinicStaff/doctor", { role: "admin", status: "active", clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "nurse", status: "active", clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", active: false, status: "active", clinicId: "clinic-a" }),
    s => s.db.data.set("clinicStaff/doctor", { role: "doctor", status: "active", clinicId: "clinic-b" }),
    s => s.db.data.set("clinics/clinic-a", { status: "inactive" }),
    s => s.db.data.set("inneraPatients/fake-chart", { linked: true, clinicId: "clinic-b", firebaseUid: "fake-patient" }),
    s => s.db.data.set("demoEncryptedFixtures/fake-patient", { synthetic: false, clinicId: "clinic-a", patientId: "fake-chart" }),
  ]) {
    const s = setup(); await s.publish(); change(s); await assert.rejects(s.read); assert.equal(s.keyCalls(), 0);
  }
  const s = setup(); await s.publish();
  for (const r of [
    { ...request("doctor", { uid: "fake-patient" }), auth: null },
    { ...request("doctor", { uid: "fake-patient" }), app: null },
    { ...request("doctor", { uid: "fake-patient" }), auth: { uid: "doctor", token: { firebase: { sign_in_provider: "anonymous" } } } },
  ]) await assert.rejects(() => s.service.read(r));
  assert.equal(s.keyCalls(), 0);
});
test("revocation during unwrap prevents releasing plaintext", async () => {
  const s = setup(); await s.publish();
  s.keys.unwrap = async (clinic, version, bytes) => { await s.revoke(); return unwrap(version, bytes); };
  await assert.rejects(s.read, { code: "permission-denied" });
});
test("role removal during unwrap and failed audit prevent releasing plaintext", async () => {
  const s = setup(); await s.publish();
  s.keys.unwrap = async (clinic, version, bytes) => {
    s.db.data.set("clinicStaff/doctor", { role: "nurse", status: "active", clinicId: "clinic-a" });
    return unwrap(version, bytes);
  };
  await assert.rejects(s.read);
  const a = setup(); await a.publish(); a.db.failAudit = true;
  await assert.rejects(a.read);
  await assert.rejects(a.revoke);
  assert.equal(a.db.data.get(root).active, true); // No false success on atomic failure.
});
test("wrong environment, plaintext fields, unknown version and stale epoch fail closed", async () => {
  const s = setup();
  const wrong = createService({ db: s.db, keys: s.keys, projectId: "moodsogood-9e45b" });
  await assert.rejects(() => wrong.context(request("fake-patient")), { code: "failed-precondition" });
  const env = encrypt(); env.durationMinutes = 480;
  await assert.rejects(() => s.service.publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1, records: [{ id: "opaque-record", envelope: env }] })), { code: "invalid-argument" });
  await s.publish();
  s.db.data.get(`${root}/sleepRecords/opaque-record`).keyVersion = VERSION.replace(/1$/, "99");
  await assert.rejects(s.read, { code: "failed-precondition" }); assert.equal(s.keyCalls(), 0);
});
test("GCM rejects transplanted uid/clinic/document/epoch, modified tag/ciphertext and unsupported schema", async () => {
  for (const [uid, clinic, id] of [["other", "clinic-a", "opaque-record"], ["fake-patient", "other", "opaque-record"], ["fake-patient", "clinic-a", "other"]]) {
    await assert.rejects(() => decrypt(uid, clinic, id, encrypt(), unwrap), { code: "data-loss" });
  }
  for (const mutate of [
    e => { e.epoch++; }, e => { e.schemaVersion = 2; },
    e => { e.authenticationTag = Buffer.alloc(16).toString("base64"); },
    e => { e.ciphertext = Buffer.alloc(48).toString("base64"); },
  ]) { const e = encrypt(); mutate(e); await assert.rejects(() => decrypt("fake-patient", "clinic-a", "opaque-record", e, unwrap)); }
  const first = encrypt(); const second = encrypt();
  assert.notEqual(first.wrappedDataKey, second.wrappedDataKey); assert.notEqual(first.nonce, second.nonce);
});
test("rotation reads allowed old versions but only writes the current version", async () => {
  const s = setup(); await s.publish();
  s.keys.canWrite = (clinic, version) => version === VERSION.replace(/1$/, "2");
  assert.deepEqual((await s.read()).records, [sleep]);
  await assert.rejects(() => s.publish(1), { code: "failed-precondition" });
  s.keys.canRead = () => false;
  await assert.rejects(s.read, { code: "failed-precondition" });
});
