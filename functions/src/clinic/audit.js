const {
  onCall,
  HttpsError
} = require("firebase-functions/v2/https");

const { db, admin } =
  require("../config/firebase");

const {
  isStaffActive,
  isClinicActive
} = require("./authorization");

async function recordAuditLog({
  action,
  actorUid,
  actorClinicId,
  targetType,
  targetId,
  result = "success"
}) {
  if (
    !action ||
    !actorUid ||
    !actorClinicId ||
    !targetType ||
    !targetId
  ) {
    throw new Error("Audit log 欄位不完整。");
  }

  await db
    .collection("auditLogs")
    .add({
      action,
      actorUid,
      actorClinicId,
      targetType,
      targetId,
      result,
      source: "cloud_function",
      createdAt:
        admin.firestore
          .FieldValue
          .serverTimestamp()
    });
}

async function recordAuditLogSafely(payload) {
  try {
    await recordAuditLog(payload);
    return true;
  } catch (error) {
    // Audit 失敗不可把已成功完成的 staff 操作誤報成失敗，
    // 先記到 Cloud Functions log，後續再擴充監控告警。
    console.error(
      "[Innera Audit] 寫入 auditLogs 失敗",
      {
        action: payload?.action || null,
        actorUid: payload?.actorUid || null,
        targetId: payload?.targetId || null,
        error
      }
    );
    return false;
  }
}
// =========================================================
// listClinicAuditLogs
// =========================================================

const listClinicAuditLogs = onCall(
  { region: "us-central1" },
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


    const clinicId =
      String(
        caller.clinicId || ""
      ).trim();


    if (!clinicId) {
      throw new HttpsError(
        "failed-precondition",
        "院所資料不完整。"
      );
    }

    if (
      !isStaffActive(caller) ||
      !await isClinicActive(clinicId) ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以查看操作紀錄。"
      );
    }


    const snapshot =
  await db
    .collection("auditLogs")
    .where(
      "actorClinicId",
      "==",
      clinicId
    )
    .orderBy(
      "createdAt",
      "desc"
    )
    .limit(50)
    .get();


// ---------------------------------------------------------
// 取得這批 Audit Log 中所有不重複的操作者 UID
// ---------------------------------------------------------

const actorUids =
  [
    ...new Set(
      snapshot.docs
        .map((doc) => {
          const data =
            doc.data();

          return String(
            data.actorUid || ""
          ).trim();
        })
        .filter(Boolean)
    )
  ];


// ---------------------------------------------------------
// 查詢 clinicStaff，建立 uid -> displayName 對照表
// ---------------------------------------------------------

const actorNameMap =
  new Map();


if (actorUids.length > 0) {

  const actorRefs =
    actorUids.map((uid) =>
      db
        .collection("clinicStaff")
        .doc(uid)
    );


  const actorDocs =
    await db.getAll(
      ...actorRefs
    );


  actorDocs.forEach((actorDoc) => {

    if (!actorDoc.exists) {
      return;
    }


    const actor =
      actorDoc.data();


    // 額外確認這個 staff 仍屬於目前院所
    if (
      String(actor.clinicId || "") !==
      clinicId
    ) {
      return;
    }


    const displayName =
      String(
        actor.displayName || ""
      ).trim();


    if (displayName) {
      actorNameMap.set(
        actorDoc.id,
        displayName
      );
    }
  });
}


// ---------------------------------------------------------
// 組合前端需要的 Audit Log
// ---------------------------------------------------------

const logs =
  snapshot.docs.map((doc) => {

    const data =
      doc.data();


    const actorUid =
      String(
        data.actorUid || ""
      );


    return {
      id: doc.id,

      action:
        String(
          data.action || ""
        ),

      actorUid,

      actorDisplayName:
        actorNameMap.get(actorUid) ||
        "未知成員",

      targetType:
        String(
          data.targetType || ""
        ),

      targetId:
        String(
          data.targetId || ""
        ),

      result:
        String(
          data.result || ""
        ),

      createdAt:
        data.createdAt?.toMillis?.() ||
        null
    };
  });


    return {
      success: true,
      logs
    };
  }
);
module.exports = {
  recordAuditLog,
  recordAuditLogSafely,
  listClinicAuditLogs
};
