"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createService } = require("../service");
const { VERSION, keyPair, sleep, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");

test("real Firestore transactions and demo Rules: encrypted share, doctor read, revoke and concurrent stale upload", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST && "Requires local Firestore emulator on 127.0.0.1:8185",
}, async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8185", "Only the dedicated loopback emulator is allowed");
  const { initializeTestEnvironment, assertFails } = require("../../functions/node_modules/@firebase/rules-unit-testing");
  const { doc, getDoc, setDoc, setLogLevel } = require("../../functions/node_modules/firebase/firestore");
  const { initializeApp, deleteApp, cert } = require("firebase-admin/app");
  const { getFirestore } = require("firebase-admin/firestore");
  setLogLevel("silent");
  const env = await initializeTestEnvironment({ projectId: "innera-demo", firestore: {
    host: "127.0.0.1", port: 8185,
    rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.demo.rules"), "utf8"),
  } });
  // Runtime-only fake credential prevents any ADC/metadata lookup. The host is
  // asserted above; this certificate is not associated with a cloud account.
  const app = initializeApp({ projectId: "innera-demo", credential: cert({
    projectId: "innera-demo", clientEmail: "local-test@innera-demo.iam.gserviceaccount.com",
    privateKey: keyPair.privateKey.export({ type: "pkcs8", format: "pem" }),
  }) }, "encrypted-pilot-test");
  const db = getFirestore(app);
  try {
    await env.clearFirestore();
    const memory = new MemoryDb(); fixture(memory);
    for (const [p, value] of memory.data) await db.doc(p).set(value);
    const service = createService({ db, projectId: "innera-demo", keys: {
      canRead: (clinic, version) => clinic === "clinic-a" && version === VERSION,
      canWrite: (clinic, version) => clinic === "clinic-a" && version === VERSION,
      unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
    } });
    const upload = epoch => service.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: "opaque-record", envelope: encrypt({ epoch: epoch + 1 }) }] }));
    await upload(0);
    const healthService = createService({ db, projectId: "innera-demo", type: "healthEvents", keys: {
      canRead: () => true, canWrite: () => true,
      unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
    } });
    const healthUpload = epoch => healthService.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: "opaque-health", envelope: encrypt({ id: "opaque-health", epoch: epoch + 1,
        type: "healthEvents", payload: require("./health-event-fixture") }) }] }));
    await healthUpload(0);
    const checkService = createService({ db, projectId: "innera-demo", type: "checkIns", keys: {
      canRead: () => true, canWrite: () => true, unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
    } });
    const checkUpload = epoch => checkService.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: "opaque-check", envelope: encrypt({ id: "opaque-check", epoch: epoch + 1,
        type: "checkIns", payload: require("./check-in-fixture") }) }] }));
    await checkUpload(0);
    const medicationService = createService({ db, projectId: "innera-demo", type: "medications", keys: {
      canRead: () => true, canWrite: () => true, unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
    } });
    const medicationUpload = epoch => medicationService.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: "opaque-medication", envelope: encrypt({ id: "opaque-medication", epoch: epoch + 1,
        type: "medications", payload: require("./medication-fixture") }) }] }));
    await medicationUpload(0);
    // Runtime DB guard proves no service operation touches historical collections.
    for (const method of ["doc", "collection"]) {
      const original = db[method].bind(db);
      db[method] = p => { assert.ok(!p.startsWith("users/"), "Demo cannot access original user data"); return original(p); };
    }
    const dailyService = createService({ db, projectId: "innera-demo", type: "dailyRecords", keys: {
      canRead: () => true, canWrite: () => true, unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
    } });
    const dailyUpload = epoch => dailyService.publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: Object.entries(require("./daily-record-fixture")).map(([id, payload]) => ({ id,
        envelope: encrypt({ id, epoch: epoch + 1, type: "dailyRecords", payload }) })) }));
    await dailyUpload(0);
    assert.equal((await dailyService.read(request("doctor", { uid: "fake-patient" }))).records.length, 2);
    assert.equal((await medicationService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await checkService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.deepEqual((await service.read(request("doctor", { uid: "fake-patient" }))).records, [sleep]);
    assert.equal((await service.list(request("doctor"))).patients.length, 1);
    const { createSummaryService } = require("../summary-service");
    const summaryKeys = {
      canRead: () => true, canWrite: () => true,
      unwrap: async (clinic, version, wrapped) => unwrap(version, wrapped),
      publicKey: async () => ({ keyVersion: VERSION, publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }),
    };
    const summaryService = createSummaryService({ db, projectId: "innera-demo", keys: summaryKeys });
    await summaryService.consent(request("fake-patient", { consentVersion: 1 }));
    await summaryService.generate(request("doctor", { uid: "fake-patient" }));
    assert.equal((await summaryService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    const summaryDoc = db.doc("demoEncryptedShares/fake-patient/clinics/clinic-a/aiSummaries/current");
    assert.equal(Object.keys((await summaryDoc.get()).data()).length, 9);
    await healthService.revoke(request("fake-patient"));
    assert.equal((await summaryDoc.get()).exists, false);
    const partial = await summaryService.read(request("doctor", { uid: "fake-patient" }));
    assert.equal(partial.updated, true);
    assert.ok(!Object.hasOwn(partial.records[0].sources, "healthEvents"));
    await healthUpload(2);
    await assert.rejects(() => summaryService.readCurrent(request("doctor", { uid: "fake-patient" })), { code: "failed-precondition" });
    const renewed = await summaryService.read(request("doctor", { uid: "fake-patient" }));
    assert.equal(renewed.records[0].sources.healthEvents.epoch, 3);
    await summaryService.revoke(request("fake-patient"));
    assert.equal((await summaryDoc.get()).exists, false);
    assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    await summaryService.consent(request("fake-patient", { consentVersion: 1 }));
    let revokedDuringDecrypt = false;
    const originalUnwrap = summaryKeys.unwrap;
    summaryKeys.unwrap = async (...args) => {
      if (!revokedDuringDecrypt) { revokedDuringDecrypt = true; await dailyService.revoke(request("fake-patient")); }
      return originalUnwrap(...args);
    };
    await assert.rejects(() => summaryService.generate(request("doctor", { uid: "fake-patient" })), { code: "aborted" });
    summaryKeys.unwrap = originalUnwrap;
    assert.equal((await summaryDoc.get()).exists, false);
    await dailyUpload(2);
    for (const uid of ["fake-patient", "doctor", "admin", "other"]) {
      const client = env.authenticatedContext(uid).firestore();
      for (const p of [
        "demoEncryptedShares/fake-patient/clinics/clinic-a",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/sleepRecords/opaque-record",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/aiSummaries/current",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/checkIns/opaque-check",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/checkIns",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/medications/opaque-medication",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/medications",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/dailyRecords/page",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/dailyRecords",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/aiSummary",
        "demoEncryptedFixtures/fake-patient", "demoEncryptedAudit/attempt",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/healthEvents/opaque-health",
        "demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/healthEvents",
      ]) {
        await assertFails(getDoc(doc(client, p)));
        await assertFails(setDoc(doc(client, p), { active: true, durationMinutes: 480 }));
      }
    }
    const dailyRace = await Promise.allSettled([dailyUpload(3), dailyService.revoke(request("fake-patient"))]);
    assert.equal(dailyRace[1].status, "fulfilled");
    await assert.rejects(() => dailyService.read(request("doctor", { uid: "fake-patient" })), { code: "permission-denied" });
    await assert.rejects(() => dailyUpload(0), { code: "aborted" });
    assert.equal((await db.collection("demoEncryptedShares/fake-patient/clinics/clinic-a/dailyRecords").get()).size, 0);
    assert.equal((await service.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await checkService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await medicationService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    const medicationRace = await Promise.allSettled([medicationUpload(1), medicationService.revoke(request("fake-patient"))]);
    assert.equal(medicationRace[1].status, "fulfilled");
    await assert.rejects(() => medicationService.read(request("doctor", { uid: "fake-patient" })), { code: "permission-denied" });
    await assert.rejects(() => medicationUpload(0), { code: "aborted" });
    assert.equal((await db.collection("demoEncryptedShares/fake-patient/clinics/clinic-a/medications").get()).size, 0);
    assert.equal((await service.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await checkService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    const checkRace = await Promise.allSettled([checkUpload(1), checkService.revoke(request("fake-patient"))]);
    assert.equal(checkRace[1].status, "fulfilled");
    await assert.rejects(() => checkService.read(request("doctor", { uid: "fake-patient" })), { code: "permission-denied" });
    await assert.rejects(() => checkUpload(0), { code: "aborted" });
    assert.equal((await db.collection("demoEncryptedShares/fake-patient/clinics/clinic-a/checkIns").get()).size, 0);
    assert.equal((await service.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    assert.equal((await healthService.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    const healthRace = await Promise.allSettled([healthUpload(3), healthService.revoke(request("fake-patient"))]);
    assert.equal(healthRace[1].status, "fulfilled");
    await assert.rejects(() => healthService.read(request("doctor", { uid: "fake-patient" })), { code: "permission-denied" });
    assert.equal((await db.collection("demoEncryptedShares/fake-patient/clinics/clinic-a/healthEvents").get()).size, 0);
    assert.equal((await service.read(request("doctor", { uid: "fake-patient" }))).records.length, 1);
    const results = await Promise.allSettled([
      upload(1), service.revoke(request("fake-patient")),
    ]);
    assert.equal(results[1].status, "fulfilled");
    await assert.rejects(() => service.read(request("doctor", { uid: "fake-patient" })), { code: "permission-denied" });
    const root = db.doc("demoEncryptedShares/fake-patient/clinics/clinic-a");
    assert.equal((await root.get()).data().active, false);
    assert.equal((await root.collection("sleepRecords").get()).size, 0);
    const logs = await db.collection("demoEncryptedAudit").get();
    assert.ok(logs.size >= 3);
    for (const row of logs.docs) {
      const data = row.data();
      assert.equal(Object.hasOwn(data, "patientId"), false);
      assert.equal(JSON.stringify(data).includes("fake-patient"), false);
    }
  } finally {
    await env.clearFirestore(); await db.terminate(); await deleteApp(app); await env.cleanup();
  }
});
