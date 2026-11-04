const { randomInt } = require("node:crypto");
const { isStaffActive, allowsPatientInvite } = require("./authorization");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");
const { recordAuditLogSafely } = require("./audit");

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
  const result = await db.runTransaction(async (transaction) => {
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
    if (patient.clinicId !== clinicId || !await allowsPatientInvite(clinicId, transaction)) {
      throw new HttpsError("permission-denied", "Clinic or patient invite is not authorized.");
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

  await recordAuditLogSafely({
    action: "invite.redeem",
    actorUid: uid,
    actorClinicId: result.clinicId,
    targetType: "clinicInvite",
    targetId: code,
    result: "success"
  });

  return result;
});

exports.createClinicInvite = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const patientId = typeof request.data?.patientId === "string" ? request.data.patientId.trim() : "";
  const hours = Number(request.data?.expiresHours ?? 24);
  if (!patientId || patientId.includes("/") || !Number.isFinite(hours) || hours <= 0 || hours > 24 * 365) {
    throw new HttpsError("invalid-argument", "Invalid patient or expiry.");
  }
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const code = Array.from({ length: 8 }, () => alphabet[randomInt(alphabet.length)]).join("");
  const result = await db.runTransaction(async (transaction) => {
    const staff = (await transaction.get(
      db.collection("clinicStaff").doc(request.auth.uid)
    )).data();
    if (
      !isStaffActive(staff) ||
      !await allowsPatientInvite(staff.clinicId, transaction)
    ) {
      throw new HttpsError(
        "permission-denied",
        "Clinic invites are not authorized."
      );
    }
    const patientSnap = await transaction.get(db.collection("inneraPatients").doc(patientId));
    const patient = patientSnap.data();
    if (!patient || patient.clinicId !== staff.clinicId) {
      throw new HttpsError("permission-denied", "Patient belongs to another clinic or does not exist.");
    }
    if (patient.linked === true || patient.firebaseUid) {
      throw new HttpsError("failed-precondition", "Patient is already linked.");
    }
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + hours * 3600000);
    transaction.create(db.collection("inneraInvites").doc(code), {
      code, patientId, clinicId: staff.clinicId, legalName: patient.legalName || "",
      status: "unused", usedByUid: null, usedAt: null, expiresAt,
      createdByUid: request.auth.uid, createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      code,
      patientId,
      clinicId: staff.clinicId,
      legalName: patient.legalName || "",
      expiresAt: expiresAt.toMillis()
    };
  });

  await recordAuditLogSafely({
    action: "invite.create",
    actorUid: request.auth.uid,
    actorClinicId: result.clinicId,
    targetType: "clinicInvite",
    targetId: code,
    result: "success"
  });

  return {
    code: result.code,
    patientId: result.patientId,
    legalName: result.legalName,
    expiresAt: result.expiresAt
  };
});
