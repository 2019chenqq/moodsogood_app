"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createService } = require("../service");
const { createSummaryService } = require("../summary-service");
const { TYPES } = require("../summary-schema");
const { MemoryDb, dualClinicFixture, request, VERSION, keyPair, encrypt, unwrap, sleep } = require("./helpers");
const payloads = {
  sleepRecords: sleep, healthEvents: require("./health-event-fixture"),
  checkIns: require("./check-in-fixture"), medications: require("./medication-fixture"),
  dailyRecords: require("./daily-record-fixture").confirmation,
};
const root = clinic => `demoEncryptedShares/fake-patient/clinics/${clinic}`;
const current = clinic => `${root(clinic)}/aiSummaries/current`;
const scope = (clinic, type) => type === "sleepRecords" ? root(clinic) : `${root(clinic)}/scopes/${type}`;
const patient = clinicId => request("fake-patient", { clinicId, consentVersion: 1 });
const doctor = clinicId => request(clinicId === "clinic-a" ? "doctor" : "doctor-b", { clinicId, uid: "fake-patient" });

async function setup() {
  const db = new MemoryDb();
  dualClinicFixture(db);
  const version = clinic => VERSION.replace("clinic-a", clinic);
  const keys = {
    canRead: (clinic, v) => ["clinic-a", "clinic-b"].includes(clinic) && v === version(clinic),
    canWrite: (clinic, v) => ["clinic-a", "clinic-b"].includes(clinic) && v === version(clinic),
    publicKey: async clinic => ({ keyVersion: version(clinic), publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }),
    unwrap: async (clinic, v, bytes) => unwrap(v, bytes),
  };
  const sources = Object.fromEntries(TYPES.map(type => [type, createService({ db, keys, projectId: "innera-demo", type })]));
  const summary = createSummaryService({ db, keys, projectId: "innera-demo" });
  async function publish(clinic, type) {
    const { epoch } = await sources[type].context(patient(clinic));
    return sources[type].publish(request("fake-patient", { clinicId: clinic, expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: `opaque-${type}`, envelope: encrypt({ clinicId: clinic, version: version(clinic), id: `opaque-${type}`, epoch: epoch + 1, type, payload: payloads[type] }) }] }));
  }
  for (const clinic of ["clinic-a", "clinic-b"]) {
    for (const type of TYPES) await publish(clinic, type);
    await summary.consent(patient(clinic));
    await summary.generate(doctor(clinic));
  }
  const snapshot = clinic => structuredClone([...db.data].filter(([p]) => p === root(clinic) || p.startsWith(`${root(clinic)}/`)).sort(([a], [b]) => a.localeCompare(b)));
  async function readable(clinic) {
    for (const type of TYPES) assert.deepEqual((await sources[type].read(doctor(clinic))).records, [payloads[type]]);
    assert.equal((await summary.readCurrent(doctor(clinic))).records.length, 1);
  }
  return { db, keys, sources, summary, publish, snapshot, readable };
}

test("both clinics read all five encrypted sources and summaries; cross-clinic doctors are denied", async () => {
  const s = await setup();
  for (const clinic of ["clinic-a", "clinic-b"]) {
    await s.readable(clinic);
    const wrong = request(clinic === "clinic-a" ? "doctor-b" : "doctor", { clinicId: clinic, uid: "fake-patient" });
    for (const service of [...Object.values(s.sources), s.summary]) await assert.rejects(() => service.read(wrong), { code: "permission-denied" });
  }
});

for (const [revoked, other] of [["clinic-a", "clinic-b"], ["clinic-b", "clinic-a"]]) {
  for (const type of TYPES) test(`${revoked} ${type} revoke and regrant preserve ${other} and reject stale envelopes`, async () => {
    const s = await setup(), untouched = s.snapshot(other);
    const recordPath = `${root(revoked)}/${type}/opaque-${type}`;
    const oldRecord = structuredClone(s.db.data.get(recordPath));
    const oldSummary = structuredClone(s.db.data.get(current(revoked)));
    const before = s.db.data.get(scope(revoked, type)).epoch;
    await s.sources[type].revoke(patient(revoked));
    assert.ok(s.db.data.get(scope(revoked, type)).epoch > before);
    assert.equal(s.db.data.has(recordPath), false);
    assert.equal(s.db.data.has(current(revoked)), false);
    await assert.rejects(() => s.sources[type].read(doctor(revoked)), { code: "permission-denied" });
    await assert.rejects(() => s.summary.readCurrent(doctor(revoked)), { code: "failed-precondition" });
    const partial = await s.summary.read(doctor(revoked));
    assert.equal(partial.updated, true);
    assert.equal(Object.hasOwn(partial.records[0].sources, type), false);
    assert.notDeepEqual(s.db.data.get(current(revoked)), oldSummary);
    const revokedEpoch = s.db.data.get(scope(revoked, type)).epoch;
    await s.publish(revoked, type);
    assert.ok(s.db.data.get(scope(revoked, type)).epoch > revokedEpoch);
    const fresh = structuredClone(s.db.data.get(recordPath));
    s.db.data.set(recordPath, oldRecord);
    await assert.rejects(() => s.sources[type].read(doctor(revoked)), { code: "failed-precondition" });
    s.db.data.set(recordPath, fresh);
    s.db.data.set(current(revoked), oldSummary);
    await assert.rejects(() => s.summary.readCurrent(doctor(revoked)), { code: "failed-precondition" });
    const regenerated = await s.summary.read(doctor(revoked));
    assert.equal(regenerated.updated, true);
    assert.equal(regenerated.records[0].sources[type].epoch, s.db.data.get(scope(revoked, type)).epoch);
    assert.notDeepEqual(s.db.data.get(current(revoked)), oldSummary);
    await s.readable(other);
    assert.deepEqual(s.snapshot(other), untouched);
  });

  test(`${revoked} summary consent revoke/regrant cannot revive old summary; ${other} unchanged`, async () => {
    const s = await setup(), untouched = s.snapshot(other);
    const old = structuredClone(s.db.data.get(current(revoked)));
    const before = s.db.data.get(scope(revoked, "aiSummary")).epoch;
    await s.summary.revoke(patient(revoked));
    const revokedEpoch = s.db.data.get(scope(revoked, "aiSummary")).epoch;
    assert.ok(revokedEpoch > before);
    assert.equal(s.db.data.has(current(revoked)), false);
    await assert.rejects(() => s.summary.read(doctor(revoked)), { code: "permission-denied" });
    await s.summary.consent(patient(revoked));
    assert.ok(s.db.data.get(scope(revoked, "aiSummary")).epoch > revokedEpoch);
    s.db.data.set(current(revoked), old);
    await assert.rejects(() => s.summary.readCurrent(doctor(revoked)), { code: "failed-precondition" });
    const result = await s.summary.read(doctor(revoked));
    assert.equal(result.updated, true);
    assert.notDeepEqual(s.db.data.get(current(revoked)), old);
    await s.readable(revoked);
    await s.readable(other);
    assert.deepEqual(s.snapshot(other), untouched);
  });

  for (const type of [...TYPES, "aiSummary"]) test(`${revoked} ${type} revoke during fake provider response aborts generation, preserving ${other}`, async () => {
    const s = await setup(), untouched = s.snapshot(other);
    let calls = 0;
    const summary = createSummaryService({ db: s.db, keys: s.keys, projectId: "innera-demo", externalPatientUid: "fake-patient",
      openAiProvider: async () => {
        calls++;
        await (type === "aiSummary" ? s.summary : s.sources[type]).revoke(patient(revoked));
        return {}; // Authorization must reject before validating this discarded response.
      },
    });
    await summary.consent(request("fake-patient", { clinicId: revoked, consentVersion: 1, provider: "openai" }));
    await assert.rejects(() => summary.generate(doctor(revoked)), error => ["aborted", "permission-denied"].includes(error.code));
    assert.equal(calls, 1);
    assert.equal(s.db.data.has(current(revoked)), false);
    await s.readable(other);
    assert.deepEqual(s.snapshot(other), untouched);
  });
}
