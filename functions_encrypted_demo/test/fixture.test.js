"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { MemoryDb, fixture, dualClinicFixture, request } = require("./helpers");

test("legacy fixture and request defaults remain unchanged", () => {
  const db = new MemoryDb();
  fixture(db);
  assert.deepEqual([...db.data], [
    ["clinics/clinic-a", { status: "active" }],
    ["clinicStaff/doctor", { status: "active", role: "doctor", clinicId: "clinic-a" }],
    ["demoEncryptedFixtures/fake-patient", { synthetic: true, clinicId: "clinic-a", patientId: "fake-chart" }],
    ["inneraPatients/fake-chart", { linked: true, firebaseUid: "fake-patient", clinicId: "clinic-a" }],
  ]);
  assert.equal(request("doctor").data.clinicId, "clinic-a");
  assert.equal(request("doctor-b", { clinicId: "clinic-b" }).data.clinicId, "clinic-b");
});

test("dual fixture links one synthetic patient to distinct charts and doctors", () => {
  const db = new MemoryDb();
  dualClinicFixture(db);
  const patient = db.data.get("demoEncryptedFixtures/fake-patient");
  assert.equal(patient.synthetic, true);
  assert.equal(patient.clinicId, "clinic-a");
  assert.equal(patient.patientId, "fake-chart");
  assert.deepEqual(Object.keys(patient.clinics), ["clinic-a", "clinic-b"]);
  const charts = Object.values(patient.clinics).map(link => link.patientId);
  assert.equal(new Set(charts).size, 2);
  for (const [clinicId, link] of Object.entries(patient.clinics)) {
    assert.deepEqual(db.data.get(`clinics/${clinicId}`), { status: "active" });
    assert.deepEqual(db.data.get(`inneraPatients/${link.patientId}`), {
      linked: true, firebaseUid: "fake-patient", clinicId,
    });
  }
  assert.deepEqual(db.data.get("clinicStaff/doctor"), { status: "active", role: "doctor", clinicId: "clinic-a" });
  assert.deepEqual(db.data.get("clinicStaff/doctor-b"), { status: "active", role: "doctor", clinicId: "clinic-b" });
  assert.equal(db.data.size, 7);
});

test("clinic fixtures have independent records and database instances", () => {
  const first = new MemoryDb();
  const second = new MemoryDb();
  dualClinicFixture(first);
  dualClinicFixture(second);
  first.data.get("inneraPatients/fake-chart").linked = false;
  first.data.get("clinicStaff/doctor").status = "inactive";
  first.data.get("demoEncryptedFixtures/fake-patient").clinics["clinic-a"].patientId = "changed";
  assert.equal(first.data.get("inneraPatients/fake-chart-b").linked, true);
  assert.equal(first.data.get("clinicStaff/doctor-b").status, "active");
  assert.equal(second.data.get("inneraPatients/fake-chart").linked, true);
  assert.equal(second.data.get("demoEncryptedFixtures/fake-patient").clinics["clinic-a"].patientId, "fake-chart");
});
