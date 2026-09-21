const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");

exports.redeemClinicInvite = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("unauthenticated", "請先登入心域帳號。");
  }
  const code = typeof request.data?.code === "string"
    ? request.data.code.trim().toUpperCase() : "";
  if (!code || code.includes("/")) {
    throw new HttpsError("invalid-argument", "請輸入有效的邀請碼。");
  }
  const uid = request.auth.uid;
  const inviteRef = db.collection("inneraInvites").doc(code);
  return db.runTransaction(async (transaction) => {
    const inviteSnap = await transaction.get(inviteRef);
    if (!inviteSnap.exists) {
      throw new HttpsError("not-found", "邀請碼不存在。");
    }
    const invite = inviteSnap.data();
    if (invite.status !== "unused") {
      throw new HttpsError("failed-precondition", "此邀請碼已使用或已失效。");
    }
    if (!(invite.expiresAt instanceof admin.firestore.Timestamp) ||
        invite.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "此邀請碼已過期或期限無效。");
    }
    const patientId = typeof invite.patientId === "string" ? invite.patientId.trim() : "";
    const clinicId = typeof invite.clinicId === "string" ? invite.clinicId.trim() : "";
    const legalName = typeof invite.legalName === "string" ? invite.legalName.trim() : "";
    if (!patientId || !clinicId || patientId.includes("/") || clinicId.includes("/")) {
      throw new HttpsError("failed-precondition", "邀請資料不完整。");
    }
    const patientRef = db.collection("inneraPatients").doc(patientId);
    const patientSnap = await transaction.get(patientRef);
    if (!patientSnap.exists) {
      throw new HttpsError("not-found", "找不到對應的心域患者資料。");
    }
    const patient = patientSnap.data();
    if (patient.firebaseUid && patient.firebaseUid !== uid) {
      throw new HttpsError("permission-denied", "此患者已綁定其他心域帳號。");
    }
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(patientRef, {
      firebaseUid: uid, linked: true, linkedAt: timestamp, updatedAt: timestamp,
    });
    transaction.update(inviteRef, {
      status: "used", usedByUid: uid, usedAt: timestamp,
    });
    transaction.set(db.collection("users").doc(uid).collection("clinicLinks").doc(clinicId), {
      patientId, clinicId, legalName, status: "active",
      linkedAt: timestamp, updatedAt: timestamp,
    }, { merge: true });
    transaction.set(db.collection("clinicalShares").doc(uid).collection("clinics").doc(clinicId), {
      uid, clinicId, active: true, grantedAt: timestamp,
      revokedAt: null, updatedAt: timestamp,
    }, { merge: true });
    return { patientId, clinicId, legalName };
  });
});
