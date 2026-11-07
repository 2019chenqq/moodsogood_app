"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createService } = require("../service");
const { createSummaryService } = require("../summary-service");
const { MemoryDb, dualClinicFixture, request, VERSION, keyPair, encrypt, unwrap, sleep } = require("./helpers");

function setup() {
  const db = new MemoryDb();
  dualClinicFixture(db);
  const versions = { "clinic-a": VERSION, "clinic-b": VERSION.replace("clinic-a", "clinic-b") };
  const keys = {
    canRead: (clinic, version) => Boolean(versions[clinic]) && versions[clinic] === version,
    canWrite: (clinic, version) => Boolean(versions[clinic]) && versions[clinic] === version,
    publicKey: async clinic => ({ keyVersion: versions[clinic], publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }),
    unwrap: async (clinic, version, bytes) => unwrap(version, bytes),
  };
  const service = createService({ db, keys, projectId: "innera-demo" });
  const summary = createSummaryService({ db, keys, projectId: "innera-demo" });
  const patient = clinicId => request("fake-patient", { clinicId, consentVersion: 1 });
  const doctor = clinicId => request(clinicId === "clinic-a" ? "doctor" : "doctor-b", { clinicId, uid: "fake-patient" });
  const publish = clinicId => service.publish(request("fake-patient", {
    clinicId, expectedEpoch: 0, consentVersion: 1,
    records: [{ id: "opaque-record", envelope: encrypt({ clinicId, version: versions[clinicId] }) }],
  }));
  return { db, service, summary, patient, doctor, publish };
}

test("A/B independently authorize, publish and read data and summaries", async () => {
  const s = setup();
  for (const clinic of ["clinic-a", "clinic-b"]) {
    assert.equal((await s.service.context(s.patient(clinic))).epoch, 0);
    await s.publish(clinic);
    assert.deepEqual((await s.service.read(s.doctor(clinic))).records, [sleep]);
    await s.summary.consent(s.patient(clinic));
    await s.summary.generate(s.doctor(clinic));
    assert.equal((await s.summary.read(s.doctor(clinic))).records.length, 1);
  }
  await s.service.revoke(s.patient("clinic-a"));
  await s.summary.revoke(s.patient("clinic-a"));
  await assert.rejects(() => s.service.read(s.doctor("clinic-a")), { code: "permission-denied" });
  await assert.rejects(() => s.summary.read(s.doctor("clinic-a")), { code: "permission-denied" });
  assert.deepEqual((await s.service.read(s.doctor("clinic-b"))).records, [sleep]);
  assert.equal((await s.summary.read(s.doctor("clinic-b"))).records.length, 1);
});

test("cross-clinic doctors and unknown clinics are rejected", async () => {
  const s = setup();
  for (const [actor, clinicId] of [["doctor", "clinic-b"], ["doctor-b", "clinic-a"]]) {
    const req = request(actor, { clinicId, uid: "fake-patient" });
    await assert.rejects(() => s.service.read(req), { code: "permission-denied" });
    await assert.rejects(() => s.summary.read(req), { code: "permission-denied" });
  }
  for (const clinic of ["unknown-clinic", "clinic-a"]) {
    delete s.db.data.get("demoEncryptedFixtures/fake-patient").clinics[clinic];
    await assert.rejects(() => s.service.context(s.patient(clinic)), { code: "permission-denied" });
    await assert.rejects(() => s.summary.consent(s.patient(clinic)), { code: "permission-denied" });
    await assert.rejects(() => s.service.revoke(s.patient(clinic)), { code: "permission-denied" });
    await assert.rejects(() => s.summary.revoke(s.patient(clinic)), { code: "permission-denied" });
  }
});

for (const invalid of ["other-clinic-chart", "missing-chart", "wrong-uid", "unlinked", "not-synthetic", "inactive-clinic"]) {
  test(`invalid relation rejects ${invalid}`, async () => {
    const s = setup();
    const fixture = s.db.data.get("demoEncryptedFixtures/fake-patient");
    const chart = s.db.data.get("inneraPatients/fake-chart-b");
    if (invalid === "other-clinic-chart") fixture.clinics["clinic-b"].patientId = "fake-chart";
    if (invalid === "missing-chart") fixture.clinics["clinic-b"].patientId = "missing";
    if (invalid === "wrong-uid") chart.firebaseUid = "other-patient";
    if (invalid === "unlinked") chart.linked = false;
    if (invalid === "not-synthetic") fixture.synthetic = false;
    if (invalid === "inactive-clinic") s.db.data.get("clinics/clinic-b").status = "inactive";
    await assert.rejects(() => s.service.context(s.patient("clinic-b")), { code: "permission-denied" });
    await assert.rejects(() => s.publish("clinic-b"), { code: "permission-denied" });
    await assert.rejects(() => s.service.read(s.doctor("clinic-b")), { code: "permission-denied" });
    await assert.rejects(() => s.summary.consent(s.patient("clinic-b")), { code: "permission-denied" });
    await assert.rejects(() => s.summary.generate(s.doctor("clinic-b")), { code: "permission-denied" });
    await assert.rejects(() => s.summary.read(s.doctor("clinic-b")), { code: "permission-denied" });
    if (["unlinked", "inactive-clinic"].includes(invalid)) {
      await s.service.revoke(s.patient("clinic-b"));
      await s.summary.revoke(s.patient("clinic-b"));
    } else {
      await assert.rejects(() => s.service.revoke(s.patient("clinic-b")), { code: "permission-denied" });
      await assert.rejects(() => s.summary.revoke(s.patient("clinic-b")), { code: "permission-denied" });
    }
  });
}

test("list finds mapped clinic B, deduplicates A and excludes unrelated or invalid charts", async () => {
  const s = setup();
  s.db.data.set("demoEncryptedFixtures/only-a", { synthetic: true, clinicId: "clinic-a", patientId: "chart-only-a" });
  s.db.data.set("inneraPatients/chart-only-a", { linked: true, clinicId: "clinic-a", firebaseUid: "only-a" });
  s.db.data.set("demoEncryptedFixtures/bad-b", { synthetic: true, clinics: { "clinic-b": { patientId: "chart-only-a" } } });
  assert.deepEqual((await s.service.list(s.doctor("clinic-a"))).patients.map(p => p.uid).sort(), ["fake-patient", "only-a"]);
  assert.deepEqual((await s.service.list(s.doctor("clinic-b"))).patients, [{ uid: "fake-patient", clinicId: "clinic-b", label: "睡眠測試患者" }]);
});
