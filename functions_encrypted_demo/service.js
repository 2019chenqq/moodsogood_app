"use strict";
const { randomUUID, createHash } = require("node:crypto");
const { PROJECT, requireThat, identifier, validateEnvelope, decrypt } = require("./protocol");

// All authorization reads use transactions. The final transaction is the read's
// authorization linearization point; an already released response cannot be recalled.
function createService({ db, projectId, keys, now = () => Date.now(), type = "sleepRecords" }) {
  requireThat(["sleepRecords", "healthEvents", "checkIns", "medications", "dailyRecords"].includes(type), "failed-precondition");
  const health = type === "healthEvents";
  const sharingFlag = { sleepRecords: "sleepSharingEnabled", healthEvents: "healthEventSharingEnabled", checkIns: "checkInSharingEnabled", medications: "medicationSharingEnabled", dailyRecords: "dailyRecordSharingEnabled" }[type];
  const actionPrefix = { sleepRecords: "sleep", healthEvents: "healthEvent", checkIns: "checkIn", medications: "medication", dailyRecords: "dailyRecord" }[type];
  function caller(request) {
    requireThat(projectId === PROJECT, "failed-precondition");
    requireThat(request.app?.appId, "failed-precondition");
    requireThat(request.auth?.uid && request.auth.token?.firebase?.sign_in_provider !== "anonymous", "unauthenticated");
    return identifier(request.auth.uid);
  }
  function refs(uid, clinicId) {
    return {
      clinic: db.doc(`clinics/${clinicId}`), fixture: db.doc(`demoEncryptedFixtures/${uid}`),
      share: db.doc(`demoEncryptedShares/${uid}/clinics/${clinicId}${type === "sleepRecords" ? "" : `/scopes/${type}`}`),
      records: db.collection(`demoEncryptedShares/${uid}/clinics/${clinicId}/${type}`),
    };
  }
  async function relation(tx, uid, clinicId) {
    const r = refs(uid, clinicId);
    const fixture = (await tx.get(r.fixture)).data();
    const clinic = (await tx.get(r.clinic)).data();
    requireThat(fixture?.synthetic === true && fixture.clinicId === clinicId && clinic?.status === "active");
    const patient = (await tx.get(db.doc(`inneraPatients/${identifier(fixture.patientId)}`))).data();
    requireThat(patient?.linked === true && patient.firebaseUid === uid && patient.clinicId === clinicId);
    return r;
  }
  function audit(tx, action, actor, subject, result = "success") {
    // Intentionally no patient identifier, token, payload, or raw error.
    const ref = value => createHash("sha256").update(`innera-demo:audit:${value}`).digest("hex");
    tx.set(db.doc(`demoEncryptedAudit/${randomUUID()}`), {
      action, result, actorRef: ref(actor), subjectRef: ref(subject), at: now(), schemaVersion: 1,
    });
  }
  async function context(request) {
    const uid = caller(request); const clinicId = identifier(request.data?.clinicId);
    const share = await db.runTransaction(async tx => {
      const r = await relation(tx, uid, clinicId);
      return (await tx.get(r.share)).data();
    });
    const key = await keys.publicKey(clinicId);
    return { ...key, epoch: share?.epoch || 0, active: share?.active === true, consentVersion: 1 };
  }
  async function publish(request) {
    const uid = caller(request); const clinicId = identifier(request.data?.clinicId);
    const { expectedEpoch, consentVersion, records } = request.data || {};
    requireThat(consentVersion === 1 && Number.isSafeInteger(expectedEpoch) && expectedEpoch >= 0 &&
      Array.isArray(records) && records.length > 0 && records.length <= 30, "invalid-argument");
    const ids = new Set();
    for (const record of records) {
      requireThat(record && Object.keys(record).length === 2, "invalid-argument");
      identifier(record.id); requireThat(!ids.has(record.id), "invalid-argument"); ids.add(record.id);
      validateEnvelope(record.envelope);
      requireThat(record.envelope.epoch === expectedEpoch + 1 && keys.canWrite(clinicId, record.envelope.keyVersion), "failed-precondition");
    }
    await db.runTransaction(async tx => {
      const r = await relation(tx, uid, clinicId);
      const share = (await tx.get(r.share)).data();
      requireThat((share?.epoch || 0) === expectedEpoch, "aborted");
      const old = await tx.get(r.records.limit(31));
      requireThat(old.size <= 30, "resource-exhausted");
      old.docs.forEach(doc => tx.delete(doc.ref));
      records.forEach(record => tx.set(r.records.doc(record.id), record.envelope));
      tx.set(r.share, { active: true, [sharingFlag]: true, epoch: expectedEpoch + 1,
        consentVersion, grantedAt: now(), revokedAt: null, summaryValid: false });
      tx.delete(r.share.collection("aiSummaries").doc("current"));
      tx.delete(db.doc(`demoEncryptedShares/${uid}/clinics/${clinicId}/aiSummaries/current`));
      audit(tx, "summary.invalidated", uid, uid, "invalidated");
      audit(tx, `${actionPrefix}.share`, uid, uid);
    });
    return { epoch: expectedEpoch + 1 };
  }
  async function revoke(request) {
    const uid = caller(request); const clinicId = identifier(request.data?.clinicId);
    // Revocation remains possible even if the clinic/patient link was disabled.
    return db.runTransaction(async tx => {
      const r = refs(uid, clinicId);
      const fixture = (await tx.get(r.fixture)).data();
      requireThat(fixture?.synthetic === true && fixture.clinicId === clinicId);
      const share = (await tx.get(r.share)).data();
      const old = await tx.get(r.records.limit(31));
      requireThat(old.size <= 30, "resource-exhausted");
      const epoch = (share?.epoch || 0) + 1;
      tx.set(r.share, { active: false, [sharingFlag]: false, epoch, revokedAt: now(), summaryValid: false });
      old.docs.forEach(doc => tx.delete(doc.ref));
      tx.delete(r.share.collection("aiSummaries").doc("current"));
      tx.delete(db.doc(`demoEncryptedShares/${uid}/clinics/${clinicId}/aiSummaries/current`));
      audit(tx, "summary.invalidated", uid, uid, "invalidated");
      audit(tx, `${actionPrefix}.revoke`, uid, uid);
      return { epoch };
    });
  }
  async function doctor(tx, actor, uid, clinicId, epoch) {
    const staff = (await tx.get(db.doc(`clinicStaff/${actor}`))).data();
    requireThat(staff && staff.active !== false && (staff.status === undefined || staff.status === "active") &&
      (staff.active === true || staff.status === "active") && staff.role === "doctor" && staff.clinicId === clinicId);
    const r = await relation(tx, uid, clinicId);
    const share = (await tx.get(r.share)).data();
    requireThat(share?.active === true && share[sharingFlag] === true && share.revokedAt == null &&
      (epoch === undefined || share.epoch === epoch));
    return { r, epoch: share.epoch };
  }
  async function read(request) {
    const actor = caller(request);
    const uid = identifier(request.data?.uid); const clinicId = identifier(request.data?.clinicId);
    const snapshot = await db.runTransaction(async tx => {
      const auth = await doctor(tx, actor, uid, clinicId);
      const docs = await tx.get(auth.r.records.limit(31));
      requireThat(docs.size <= 30, "resource-exhausted");
      return { epoch: auth.epoch, docs: docs.docs.map(d => ({ id: d.id, envelope: d.data() })) };
    });
    const records = [];
    for (const { id, envelope } of snapshot.docs) {
      requireThat(envelope.epoch === snapshot.epoch && keys.canRead(clinicId, envelope.keyVersion), "failed-precondition");
      // Re-check before every key operation, not just at the start of a batch.
      await db.runTransaction(tx => doctor(tx, actor, uid, clinicId, snapshot.epoch));
      records.push(await decrypt(uid, clinicId, id, envelope, (version, wrapped) => keys.unwrap(clinicId, version, wrapped), type));
    }
    await db.runTransaction(async tx => {
      await doctor(tx, actor, uid, clinicId, snapshot.epoch);
      audit(tx, `${actionPrefix}.read`, actor, uid); // Audit failure prevents releasing plaintext.
    });
    const timeField = health ? "timestamp" : type === "medications" ? "startDate" : "date";
    return { records: records.sort((a, b) => a[timeField].localeCompare(b[timeField])), epoch: snapshot.epoch, expiresInSeconds: 30 };
  }
  async function list(request) {
    const actor = caller(request);
    return db.runTransaction(async tx => {
      const staff = (await tx.get(db.doc(`clinicStaff/${actor}`))).data();
      requireThat(staff && staff.role === "doctor" && staff.active !== false &&
        (staff.status === undefined || staff.status === "active") && (staff.active === true || staff.status === "active"));
      const clinicId = identifier(staff.clinicId);
      const clinic = (await tx.get(db.doc(`clinics/${clinicId}`))).data();
      requireThat(clinic?.status === "active");
      const fixtures = await tx.get(db.collection("demoEncryptedFixtures").where("clinicId", "==", clinicId).limit(30));
      return { patients: fixtures.docs.filter(d => d.data().synthetic === true).map(d => ({
        uid: d.id, clinicId, label: "睡眠測試患者",
      })) };
    });
  }
  return { context, publish, revoke, read, list };
}
module.exports = { createService };
