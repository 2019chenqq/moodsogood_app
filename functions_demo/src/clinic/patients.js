const { isStaffActive, isClinicActive } = require("./authorization");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");
const { recordAuditLogSafely } = require("./audit");

function formatPatientId(number) {
  return `P${String(number).padStart(6, "0")}`;
}

exports.createClinicPatient = onCall(
  {
    region: "us-central1"
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }

    const callerUid =
      request.auth.uid;

    const callerDoc =
      await db
        .collection("clinicStaff")
        .doc(callerUid)
        .get();

    if (!callerDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "找不到院所人員資料。"
      );
    }

    const caller =
      callerDoc.data();

    if (
      !isStaffActive(caller) ||
      !caller.clinicId ||
      !await isClinicActive(caller.clinicId)
    ) {
      throw new HttpsError(
        "permission-denied",
        "目前帳號或院所不可建立個案。"
      );
    }

    const legalName =
      String(
        request.data?.legalName || ""
      ).trim();

    if (!legalName) {
      throw new HttpsError(
        "invalid-argument",
        "請輸入患者姓名。"
      );
    }

    if (legalName.length > 100) {
      throw new HttpsError(
        "invalid-argument",
        "患者姓名過長。"
      );
    }

    const rawQueueNumber =
      request.data?.queueNumber;

    let queueNumber = null;

    if (
      rawQueueNumber !== null &&
      rawQueueNumber !== undefined &&
      String(rawQueueNumber).trim() !== ""
    ) {
      queueNumber =
        Number(rawQueueNumber);

      if (
        !Number.isFinite(queueNumber) ||
        queueNumber < 0
      ) {
        throw new HttpsError(
          "invalid-argument",
          "掛號號碼格式不正確。"
        );
      }
    }

    const visitType =
      request.data?.visitType == null
        ? null
        : String(
            request.data.visitType
          ).trim() || null;

    if (
      visitType &&
      visitType.length > 50
    ) {
      throw new HttpsError(
        "invalid-argument",
        "看診類型過長。"
      );
    }

    const todayAppointment =
      request.data?.todayAppointment === true;

    const appointmentSession =
      request.data?.appointmentSession == null
        ? null
        : String(
            request.data.appointmentSession
          ).trim() || null;

    const appointmentTime =
      request.data?.appointmentTime == null
        ? null
        : String(
            request.data.appointmentTime
          ).trim() || null;

    const appointmentDate =
      request.data?.appointmentDate == null
        ? null
        : String(
            request.data.appointmentDate
          ).trim() || null;

    const counterRef =
      db
        .collection("inneraCounters")
        .doc("patients");

    const result =
      await db.runTransaction(
        async (transaction) => {
        const counterSnap =
          await transaction.get(
            counterRef
          );

        const rawCurrent =
          counterSnap.exists
            ? Number(
                counterSnap
                  .data()
                  .lastNumber || 0
              )
            : 0;

        const current =
          Number.isFinite(rawCurrent) &&
          rawCurrent >= 0
            ? Math.floor(rawCurrent)
            : 0;

        const next =
          current + 1;

        const patientId =
          formatPatientId(next);

        const patientRef =
          db
            .collection(
              "inneraPatients"
            )
            .doc(patientId);

        const existingPatient =
          await transaction.get(
            patientRef
          );

        if (existingPatient.exists) {
          throw new HttpsError(
            "failed-precondition",
            "患者流水號與既有資料不一致，請聯絡系統管理員。"
          );
        }

        const timestamp =
          admin.firestore
            .FieldValue
            .serverTimestamp();

        transaction.set(
          counterRef,
          {
            lastNumber:
              next,

            updatedAt:
              timestamp
          },
          {
            merge: true
          }
        );

        transaction.set(
          patientRef,
          {
            patientId,

            legalName,

            clinicId:
              caller.clinicId,

            firebaseUid:
              null,

            linked:
              false,

            linkedAt:
              null,

            queueNumber,

            // P1：正式掛號資料模型
            todayAppointment,

            appointmentDate:
              todayAppointment
                ? appointmentDate
                : null,

            appointmentSession,

            appointmentTime,

            // Legacy：暫時保留舊欄位，避免既有前端流程受影響。
            visitType,

            createdByUid:
              callerUid,

            createdAt:
              timestamp,

            updatedAt:
              timestamp
          }
        );

        return {
          patientId,
          legalName,
          clinicId:
            caller.clinicId
        };
        }
      );

    await recordAuditLogSafely({
      action: "patient.create",
      actorUid: callerUid,
      actorClinicId: caller.clinicId,
      targetType: "inneraPatient",
      targetId: result.patientId,
      result: "success"
    });

    return result;
  }
);

exports.updateClinicPatientAppointment = onCall(
  {
    region: "us-central1"
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }

    const callerUid = request.auth.uid;

    const callerDoc =
      await db
        .collection("clinicStaff")
        .doc(callerUid)
        .get();

    if (!callerDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "找不到院所人員資料。"
      );
    }

    const caller = callerDoc.data();

    if (
      !isStaffActive(caller) ||
      !caller.clinicId ||
      !await isClinicActive(caller.clinicId)
    ) {
      throw new HttpsError(
        "permission-denied",
        "目前帳號或院所不可修改個案掛號。"
      );
    }

    const patientId =
      String(
        request.data?.patientId || ""
      ).trim();

    if (!patientId) {
      throw new HttpsError(
        "invalid-argument",
        "缺少患者編號。"
      );
    }

    const todayAppointment =
      request.data?.todayAppointment === true;

    const appointmentSession =
      request.data?.appointmentSession == null
        ? null
        : String(
            request.data.appointmentSession
          ).trim() || null;

    const appointmentTime =
      request.data?.appointmentTime == null
        ? null
        : String(
            request.data.appointmentTime
          ).trim() || null;

    const appointmentDate =
      request.data?.appointmentDate == null
        ? null
        : String(
            request.data.appointmentDate
          ).trim() || null;

    const rawQueueNumber =
      request.data?.queueNumber;

    let queueNumber = null;

    if (
      rawQueueNumber !== null &&
      rawQueueNumber !== undefined &&
      String(rawQueueNumber).trim() !== ""
    ) {
      queueNumber = Number(rawQueueNumber);

      if (
        !Number.isInteger(queueNumber) ||
        queueNumber <= 0
      ) {
        throw new HttpsError(
          "invalid-argument",
          "掛號號碼格式不正確。"
        );
      }
    }

    if (
      todayAppointment &&
      appointmentSession &&
      !["morning", "afternoon", "evening"]
        .includes(appointmentSession)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "門診時段格式不正確。"
      );
    }

    if (
      todayAppointment &&
      appointmentTime &&
      !/^([01]\d|2[0-3]):[0-5]\d$/
        .test(appointmentTime)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "掛號時間格式不正確。"
      );
    }

    const patientRef =
      db
        .collection("inneraPatients")
        .doc(patientId);

    const patientSnap =
      await patientRef.get();

    if (!patientSnap.exists) {
      throw new HttpsError(
        "not-found",
        "找不到患者資料。"
      );
    }

    const patient = patientSnap.data();

    if (patient.clinicId !== caller.clinicId) {
      throw new HttpsError(
        "permission-denied",
        "你沒有操作此患者的權限。"
      );
    }

    const timestamp =
      admin.firestore
        .FieldValue
        .serverTimestamp();

    await patientRef.update({
      todayAppointment,

      appointmentDate:
        todayAppointment
          ? appointmentDate
          : null,

      appointmentSession:
        todayAppointment
          ? appointmentSession
          : null,

      appointmentTime:
        todayAppointment
          ? appointmentTime
          : null,

      queueNumber:
        todayAppointment
          ? queueNumber
          : null,

      updatedAt: timestamp
    });

    await recordAuditLogSafely({
      action: "patient.appointment.update",
      actorUid: callerUid,
      actorClinicId: caller.clinicId,
      targetType: "inneraPatient",
      targetId: patientId,
      result: "success"
    });

    return {
      patientId,
      todayAppointment,

      appointmentDate:
        todayAppointment
          ? appointmentDate
          : null,

      appointmentSession:
        todayAppointment
          ? appointmentSession
          : null,

      appointmentTime:
        todayAppointment
          ? appointmentTime
          : null,

      queueNumber:
        todayAppointment
          ? queueNumber
          : null
    };
  }
);