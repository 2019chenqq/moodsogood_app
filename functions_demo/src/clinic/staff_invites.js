const crypto = require("node:crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const {
  isStaffActive,
  isClinicActive
} = require("./authorization");

const {
  db,
  admin
} = require("../config/firebase");

const {
  recordAuditLogSafely
} = require("./audit");

const ALLOWED_ROLES = [
  "admin",
  "doctor",
  "nurse",
  "staff"
];


// =========================================================
// Helpers
// =========================================================
function normalizeEmail(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}


function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}


function createInviteToken() {
  return crypto
    .randomBytes(32)
    .toString("base64url");
}


function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}


// 同一院所 + Email 使用固定 inviteId。
// 可以避免同時建立多份 pending invitation。
function createInviteId(clinicId, email) {
  return crypto
    .createHash("sha256")
    .update(`${clinicId}:${email}`)
    .digest("hex");
}


// =========================================================
// createStaffInvite
// =========================================================

exports.createStaffInvite = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 必須登入
    // -----------------------------------------------------

    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }


    const callerUid = request.auth.uid;


    // -----------------------------------------------------
    // 2. 取得目前登入者 staff 資料
    // -----------------------------------------------------

    const callerDoc = await db
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

    const clinicId =
      String(caller.clinicId || "").trim();


    if (!clinicId) {
      throw new HttpsError(
        "failed-precondition",
        "院所資料不完整。"
      );
    }

    // -----------------------------------------------------
    // 3. 只有 active admin 可以建立邀請
    // -----------------------------------------------------

    if (
      !isStaffActive(caller) ||
      !await isClinicActive(clinicId) ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以邀請成員。"
      );
    }


    // -----------------------------------------------------
    // 4. 清理輸入
    // -----------------------------------------------------

    const {
      displayName,
      email,
      role,
      department
    } = request.data || {};


    const cleanName =
      String(displayName || "").trim();


    const cleanEmail =
      normalizeEmail(email);


    const cleanRole =
      String(role || "").trim();


    const cleanDepartment =
      String(department || "").trim();


    // -----------------------------------------------------
    // 5. 基本驗證
    // -----------------------------------------------------

    if (!cleanName) {
      throw new HttpsError(
        "invalid-argument",
        "請輸入姓名。"
      );
    }


    if (
      !cleanEmail ||
      !isValidEmail(cleanEmail)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "請輸入有效的 Email。"
      );
    }


    if (!ALLOWED_ROLES.includes(cleanRole)) {
      throw new HttpsError(
        "invalid-argument",
        "角色設定不正確。"
      );
    }


    // -----------------------------------------------------
    // 6. 檢查這個 Email 是否已經是同院所 staff
    //
    // 包含 active / disabled。
    // disabled staff 不能藉由 invitation 重新啟用。
    // -----------------------------------------------------

    const staffByEmailSnapshot = await db
      .collection("clinicStaff")
      .where("email", "==", cleanEmail)
      .get();


    const existingSameClinicStaff =
      staffByEmailSnapshot.docs.find((doc) => {
        const staff = doc.data();

        return staff.clinicId === clinicId;
      });


    if (existingSameClinicStaff) {

      const staff =
        existingSameClinicStaff.data();


      if (isStaffActive(staff)) {
        throw new HttpsError(
          "already-exists",
          "這個 Email 已經是院所成員。"
        );
      }


      throw new HttpsError(
        "failed-precondition",
        "這個帳號目前已停用，請使用原本的成員啟用功能，不要重新邀請。"
      );
    }


    // -----------------------------------------------------
    // 7. 產生 invitation
    // -----------------------------------------------------

    const inviteId =
      createInviteId(
        clinicId,
        cleanEmail
      );


    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    const rawToken =
      createInviteToken();


    const tokenHash =
      hashToken(rawToken);


    const nowMs =
      Date.now();


    const expiresAt =
      admin.firestore.Timestamp.fromMillis(
        nowMs + 7 * 24 * 60 * 60 * 1000
      );


    // -----------------------------------------------------
    // 8. Transaction：
    //    避免有效 invitation 被重複建立
    // -----------------------------------------------------

    await db.runTransaction(
      async (transaction) => {

        const existingInviteDoc =
          await transaction.get(inviteRef);


        if (existingInviteDoc.exists) {

          const existing =
            existingInviteDoc.data();


          const existingExpiresAt =
            existing.expiresAt;


          const stillValid =
            existing.status === "pending" &&
            existingExpiresAt instanceof
              admin.firestore.Timestamp &&
            existingExpiresAt.toMillis() > Date.now();


          if (stillValid) {
            throw new HttpsError(
              "already-exists",
              "這位成員已有尚未失效的邀請。"
            );
          }
        }


        transaction.set(
          inviteRef,
          {
            clinicId,

            email: cleanEmail,
            emailNormalized: cleanEmail,

            displayName: cleanName,

            role: cleanRole,

            department: cleanDepartment,

            status: "pending",

            tokenHash,

            createdByUid: callerUid,

            createdAt:
              admin.firestore.FieldValue
                .serverTimestamp(),

            expiresAt,

            acceptedAt: null,
            acceptedByUid: null,

            revokedAt: null,
            revokedByUid: null,

            version: 1
          }
        );
      }
    );


    // -----------------------------------------------------
    // 9. Audit Log
    // -----------------------------------------------------

    await recordAuditLogSafely({
      action: "staff.invite.create",
      actorUid: callerUid,
      actorClinicId: clinicId,
      targetType: "staffInvite",
      targetId: inviteId,
      result: "success"
    });


    // -----------------------------------------------------
    // 10. 第一階段暫時回傳 token
    //
    // 之後接 Email 時，
    // raw token 會直接放進寄出的 activation URL，
    // 不會顯示在正式 UI。
    // -----------------------------------------------------

    return {
      success: true,

      inviteId,

      email: cleanEmail,

      role: cleanRole,

      expiresAt:
        expiresAt.toMillis(),

      token: rawToken
    };
  }
);
// =========================================================
// listPendingStaffInvites
// =========================================================

exports.listPendingStaffInvites = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 必須登入
    // -----------------------------------------------------

    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }


    const callerUid =
      request.auth.uid;


    // -----------------------------------------------------
    // 2. 取得目前登入者 staff 資料
    // -----------------------------------------------------

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

    // -----------------------------------------------------
    // 3. 僅 active admin 可查看邀請
    // -----------------------------------------------------

    if (
      !isStaffActive(caller) ||
      !await isClinicActive(clinicId) ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以查看成員邀請。"
      );
    }


    // -----------------------------------------------------
    // 4. 只讀取自己院所的 pending invitations
    // -----------------------------------------------------

    const snapshot =
      await db
        .collection("staffInvites")
        .where("clinicId", "==", clinicId)
        .where("status", "==", "pending")
        .limit(100)
        .get();


    const nowMs =
      Date.now();


    const invites =
      snapshot.docs.map((doc) => {

        const invite =
          doc.data();


        // -----------------------------------------------
        // Email 遮罩
        // -----------------------------------------------

        const email =
          String(
            invite.email || ""
          );


        const atIndex =
          email.indexOf("@");


        let maskedEmail =
          "****";


        if (atIndex > 0) {

          const local =
            email.slice(
              0,
              atIndex
            );


          const domain =
            email.slice(
              atIndex
            );


          if (local.length <= 1) {
            maskedEmail =
              `${local[0] || "*"}***${domain}`;
          } else {
            maskedEmail =
              `${local[0]}***${local[local.length - 1]}${domain}`;
          }
        }


        // -----------------------------------------------
        // Timestamp
        // -----------------------------------------------

        const createdAt =
          invite.createdAt instanceof
          admin.firestore.Timestamp
            ? invite.createdAt.toMillis()
            : null;


        const expiresAt =
          invite.expiresAt instanceof
          admin.firestore.Timestamp
            ? invite.expiresAt.toMillis()
            : null;


        return {
          inviteId:
            doc.id,

          displayName:
            String(
              invite.displayName || ""
            ),

          maskedEmail,

          role:
            String(
              invite.role || ""
            ),

          department:
            String(
              invite.department || ""
            ),

          createdAt,

          expiresAt,

          isExpired:
            !expiresAt ||
            expiresAt <= nowMs
        };
      });


    // Firestore 這裡先不 orderBy，
    // 避免 MVP 為此新增 composite index。
    // 改成 server 端記憶體排序。
    invites.sort(
      (a, b) =>
        (b.createdAt || 0) -
        (a.createdAt || 0)
    );


    return {
      success: true,
      invites
    };
  }
);
// =========================================================
// resendStaffInvite
// =========================================================

exports.resendStaffInvite = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 必須登入
    // -----------------------------------------------------

    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }


    const callerUid =
      request.auth.uid;


    // -----------------------------------------------------
    // 2. 取得目前登入者 staff
    // -----------------------------------------------------

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

    // -----------------------------------------------------
    // 3. 只有 active admin 可以重新寄送
    // -----------------------------------------------------

    if (
      !isStaffActive(caller) ||
      !await isClinicActive(clinicId) ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以重新寄送成員邀請。"
      );
    }


    // -----------------------------------------------------
    // 4. 驗證 inviteId
    // -----------------------------------------------------

    const inviteId =
      String(
        request.data?.inviteId || ""
      ).trim();


    if (
      !inviteId ||
      inviteId.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "邀請資料無效。"
      );
    }


    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    // -----------------------------------------------------
    // 5. 產生新的 token
    //
    // raw token 不存 Firestore；
    // Firestore 只存新的 SHA-256 hash。
    // 舊 token 會在 transaction 成功後立即失效。
    // -----------------------------------------------------

    const rawToken =
      createInviteToken();


    const tokenHash =
      hashToken(rawToken);


    const expiresAt =
      admin.firestore.Timestamp.fromMillis(
        Date.now() +
        7 * 24 * 60 * 60 * 1000
      );


    // -----------------------------------------------------
    // 6. Transaction
    // -----------------------------------------------------

    const result =
      await db.runTransaction(
        async (transaction) => {

          const inviteDoc =
            await transaction.get(
              inviteRef
            );


          if (!inviteDoc.exists) {
            throw new HttpsError(
              "not-found",
              "找不到這份邀請。"
            );
          }


          const invite =
            inviteDoc.data();


          // 只能操作自己院所的 invitation
          if (
            String(invite.clinicId || "") !==
            clinicId
          ) {
            throw new HttpsError(
              "permission-denied",
              "無權操作這份邀請。"
            );
          }


          // accepted / revoked 都不能重寄
          if (invite.status !== "pending") {
            throw new HttpsError(
              "failed-precondition",
              "只有待接受的邀請可以重新寄送。"
            );
          }


          const email =
            normalizeEmail(
              invite.email
            );


          if (
            !email ||
            !isValidEmail(email)
          ) {
            throw new HttpsError(
              "failed-precondition",
              "邀請 Email 資料不完整。"
            );
          }


          const resendCount =
            Number(
              invite.resendCount || 0
            ) + 1;


          transaction.update(
            inviteRef,
            {
              tokenHash,

              expiresAt,

              lastResentAt:
                admin.firestore.FieldValue
                  .serverTimestamp(),

              lastResentByUid:
                callerUid,

              resendCount
            }
          );


          return {
            email,
            resendCount
          };
        }
      );


    // -----------------------------------------------------
    // 7. Audit Log
    // -----------------------------------------------------

    await recordAuditLogSafely({
      action: "staff.invite.resend",
      actorUid: callerUid,
      actorClinicId: clinicId,
      targetType: "staffInvite",
      targetId: inviteId,
      result: "success"
    });


    // -----------------------------------------------------
    // 8. raw token 只在這次 response 回傳
    //
    // 前端收到後立即放進 activation URL 寄信。
    // 不寫入 Firestore。
    // -----------------------------------------------------

    return {
      success: true,

      inviteId,

      email:
        result.email,

      token:
        rawToken,

      expiresAt:
        expiresAt.toMillis(),

      resendCount:
        result.resendCount
    };
  }
);

// =========================================================
// revokeStaffInvite
// =========================================================

exports.revokeStaffInvite = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 必須登入
    // -----------------------------------------------------

    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }


    const callerUid =
      request.auth.uid;


    // -----------------------------------------------------
    // 2. 取得目前登入者 staff
    // -----------------------------------------------------

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

    // -----------------------------------------------------
    // 3. 只有 active admin 可以撤銷邀請
    // -----------------------------------------------------

    if (
      !isStaffActive(caller) ||
      !await isClinicActive(clinicId) ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以撤銷成員邀請。"
      );
    }


    // -----------------------------------------------------
    // 4. 驗證 inviteId
    // -----------------------------------------------------

    const inviteId =
      String(
        request.data?.inviteId || ""
      ).trim();


    if (
      !inviteId ||
      inviteId.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "邀請資料無效。"
      );
    }


    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    // -----------------------------------------------------
    // 5. Transaction
    // -----------------------------------------------------

    await db.runTransaction(
      async (transaction) => {

        const inviteDoc =
          await transaction.get(
            inviteRef
          );


        if (!inviteDoc.exists) {
          throw new HttpsError(
            "not-found",
            "找不到這份邀請。"
          );
        }


        const invite =
          inviteDoc.data();


        // invitation 必須屬於目前院所
        if (
          String(invite.clinicId || "") !==
          clinicId
        ) {
          throw new HttpsError(
            "permission-denied",
            "無權操作這份邀請。"
          );
        }


        // 只有 pending invitation 可以撤銷
        if (invite.status !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "這份邀請已無法撤銷。"
          );
        }


        transaction.update(
          inviteRef,
          {
            status: "revoked",

            revokedAt:
              admin.firestore.FieldValue
                .serverTimestamp(),

            revokedByUid:
              callerUid
          }
        );
      }
    );


    // -----------------------------------------------------
    // 6. Audit Log
    // -----------------------------------------------------

    await recordAuditLogSafely({
      action: "staff.invite.revoke",
      actorUid: callerUid,
      actorClinicId: clinicId,
      targetType: "staffInvite",
      targetId: inviteId,
      result: "success"
    });


    return {
      success: true,
      inviteId
    };
  }
);
// =========================================================
// getStaffInvite
// =========================================================

exports.getStaffInvite = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 取得輸入
    // -----------------------------------------------------

    const inviteId =
      String(request.data?.inviteId || "").trim();

    const token =
      String(request.data?.token || "").trim();


    if (
      !inviteId ||
      !token ||
      inviteId.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "邀請連結無效。"
      );
    }


    // -----------------------------------------------------
    // 2. 取得 invitation
    //
    // 這支 Function 可以在未登入狀態使用，
    // 因為受邀者此時可能還沒有 Firebase Auth 帳號。
    // -----------------------------------------------------

    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    const inviteDoc =
      await inviteRef.get();


    if (!inviteDoc.exists) {
      throw new HttpsError(
        "not-found",
        "邀請不存在或已失效。"
      );
    }


    const invite =
      inviteDoc.data();


    // -----------------------------------------------------
    // 3. 驗證 token
    //
    // Firestore 只存 SHA-256 hash，
    // raw token 不會存在資料庫。
    // -----------------------------------------------------

    const incomingHash =
      hashToken(token);


    const storedHash =
      typeof invite.tokenHash === "string"
        ? invite.tokenHash
        : "";


    if (
      !storedHash ||
      incomingHash.length !== storedHash.length
    ) {
      throw new HttpsError(
        "permission-denied",
        "邀請連結無效。"
      );
    }


    const tokenMatches =
      crypto.timingSafeEqual(
        Buffer.from(incomingHash, "utf8"),
        Buffer.from(storedHash, "utf8")
      );


    if (!tokenMatches) {
      throw new HttpsError(
        "permission-denied",
        "邀請連結無效。"
      );
    }


    // -----------------------------------------------------
    // 4. invitation 必須仍是 pending
    // -----------------------------------------------------

    if (invite.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "此邀請已使用或已失效。"
      );
    }


    // -----------------------------------------------------
    // 5. 檢查 expiry
    // -----------------------------------------------------

    if (
      !(invite.expiresAt instanceof admin.firestore.Timestamp) ||
      invite.expiresAt.toMillis() <= Date.now()
    ) {
      throw new HttpsError(
        "failed-precondition",
        "此邀請已過期。"
      );
    }


    // -----------------------------------------------------
    // 6. Clinic 必須仍為 active
    // -----------------------------------------------------

    const clinicId =
      String(invite.clinicId || "").trim();


    if (
      !clinicId ||
      !await isClinicActive(clinicId)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "此院所目前無法接受成員邀請。"
      );
    }


    // -----------------------------------------------------
    // 7. 取得 clinic 顯示名稱
    // -----------------------------------------------------

    const clinicDoc =
      await db
        .collection("clinics")
        .doc(clinicId)
        .get();


    const clinic =
      clinicDoc.exists
        ? clinicDoc.data()
        : {};


    const clinicDisplayName =
      String(
        clinic?.displayName ||
        clinic?.clinicName ||
        clinic?.name ||
        ""
      ).trim();


    // -----------------------------------------------------
    // 8. 遮罩 Email
    // -----------------------------------------------------

    const email =
      String(invite.email || "");


    const atIndex =
      email.indexOf("@");


    let maskedEmail = "****";


    if (atIndex > 0) {

      const local =
        email.slice(0, atIndex);

      const domain =
        email.slice(atIndex);


      if (local.length <= 1) {
        maskedEmail =
          `${local[0] || "*"}***${domain}`;
      } else {
        maskedEmail =
          `${local[0]}***${local[local.length - 1]}${domain}`;
      }
    }


    // -----------------------------------------------------
    // 9. 只回傳 activation page 真正需要的資料
    // -----------------------------------------------------

    return {
      valid: true,

      clinicDisplayName,

      role:
        String(invite.role || ""),

      displayName:
        String(invite.displayName || ""),

      maskedEmail,

      expiresAt:
        invite.expiresAt.toMillis()
    };
  }
);

// =========================================================
// getStaffInviteActivationEmail
// =========================================================

exports.getStaffInviteActivationEmail = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    const inviteId =
      String(request.data?.inviteId || "").trim();

    const token =
      String(request.data?.token || "").trim();


    if (
      !inviteId ||
      !token ||
      inviteId.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "邀請資料無效。"
      );
    }


    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    const inviteDoc =
      await inviteRef.get();


    if (!inviteDoc.exists) {
      throw new HttpsError(
        "not-found",
        "邀請不存在或已失效。"
      );
    }


    const invite =
      inviteDoc.data();


    // token 驗證
    const incomingHash =
      hashToken(token);


    const storedHash =
      typeof invite.tokenHash === "string"
        ? invite.tokenHash
        : "";


    if (
      !storedHash ||
      incomingHash.length !== storedHash.length
    ) {
      throw new HttpsError(
        "permission-denied",
        "邀請連結無效。"
      );
    }


    const tokenMatches =
      crypto.timingSafeEqual(
        Buffer.from(incomingHash, "utf8"),
        Buffer.from(storedHash, "utf8")
      );


    if (!tokenMatches) {
      throw new HttpsError(
        "permission-denied",
        "邀請連結無效。"
      );
    }


    // invitation 必須仍有效
    if (invite.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        "此邀請已使用或已失效。"
      );
    }


    if (
      !(invite.expiresAt instanceof admin.firestore.Timestamp) ||
      invite.expiresAt.toMillis() <= Date.now()
    ) {
      throw new HttpsError(
        "failed-precondition",
        "此邀請已過期。"
      );
    }


    const clinicId =
      String(invite.clinicId || "").trim();


    if (
      !clinicId ||
      !await isClinicActive(clinicId)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "此院所目前無法接受成員邀請。"
      );
    }


    const email =
      normalizeEmail(invite.email);


    if (!email) {
      throw new HttpsError(
        "failed-precondition",
        "邀請 Email 資料不完整。"
      );
    }


    // 只提供給 Email Link callback 使用。
    // 前端不應將此值顯示在畫面上。
    return {
      email
    };
  }
);
// =========================================================
// acceptStaffInvite
// =========================================================

exports.acceptStaffInvite = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // -----------------------------------------------------
    // 1. 必須登入
    // -----------------------------------------------------

    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入或完成 Email 驗證。"
      );
    }


    const uid = request.auth.uid;

    const authEmail =
      normalizeEmail(
        request.auth.token?.email
      );


    const emailVerified =
      request.auth.token?.email_verified === true;


    if (!authEmail || !emailVerified) {
      throw new HttpsError(
        "failed-precondition",
        "請先完成 Email 驗證。"
      );
    }


    // -----------------------------------------------------
    // 2. 取得 inviteId / token
    // -----------------------------------------------------

    const inviteId =
      String(request.data?.inviteId || "").trim();

    const token =
      String(request.data?.token || "").trim();


    if (
      !inviteId ||
      !token ||
      inviteId.includes("/")
    ) {
      throw new HttpsError(
        "invalid-argument",
        "邀請資料無效。"
      );
    }


    const inviteRef =
      db
        .collection("staffInvites")
        .doc(inviteId);


    const staffRef =
      db
        .collection("clinicStaff")
        .doc(uid);


    // -----------------------------------------------------
    // 3. Transaction
    // -----------------------------------------------------

    const result =
      await db.runTransaction(
        async (transaction) => {

          const inviteDoc =
            await transaction.get(inviteRef);


          if (!inviteDoc.exists) {
            throw new HttpsError(
              "not-found",
              "邀請不存在或已失效。"
            );
          }


          const invite =
            inviteDoc.data();


          // -----------------------------------------------
          // token 驗證
          // -----------------------------------------------

          const incomingHash =
            hashToken(token);


          const storedHash =
            typeof invite.tokenHash === "string"
              ? invite.tokenHash
              : "";


          if (
            !storedHash ||
            incomingHash.length !== storedHash.length
          ) {
            throw new HttpsError(
              "permission-denied",
              "邀請連結無效。"
            );
          }


          const tokenMatches =
            crypto.timingSafeEqual(
              Buffer.from(incomingHash, "utf8"),
              Buffer.from(storedHash, "utf8")
            );


          if (!tokenMatches) {
            throw new HttpsError(
              "permission-denied",
              "邀請連結無效。"
            );
          }


          // -----------------------------------------------
          // invitation 狀態
          // -----------------------------------------------

          if (invite.status !== "pending") {
            throw new HttpsError(
              "failed-precondition",
              "此邀請已使用或已失效。"
            );
          }


          if (
            !(invite.expiresAt instanceof admin.firestore.Timestamp) ||
            invite.expiresAt.toMillis() <= Date.now()
          ) {
            throw new HttpsError(
              "failed-precondition",
              "此邀請已過期。"
            );
          }


          // -----------------------------------------------
          // Email 必須完全符合
          // -----------------------------------------------

          const inviteEmail =
            normalizeEmail(invite.email);


          if (
            !inviteEmail ||
            inviteEmail !== authEmail
          ) {
            throw new HttpsError(
              "permission-denied",
              "目前登入帳號與受邀 Email 不一致。"
            );
          }


          // -----------------------------------------------
          // Clinic 必須有效
          // -----------------------------------------------

          const clinicId =
            String(invite.clinicId || "").trim();


          if (
            !clinicId ||
            !await isClinicActive(
              clinicId,
              transaction
            )
          ) {
            throw new HttpsError(
              "failed-precondition",
              "此院所目前無法接受成員邀請。"
            );
          }


          const clinicRef =
            db
              .collection("clinics")
              .doc(clinicId);


          const clinicDoc =
            await transaction.get(clinicRef);


          if (!clinicDoc.exists) {
            throw new HttpsError(
              "failed-precondition",
              "找不到院所資料。"
            );
          }


          const clinic =
            clinicDoc.data();

          const isInitialAdmin =
            invite.inviteType === "initial_admin";

          if (isInitialAdmin) {
            if (String(invite.role || "") !== "admin") {
              throw new HttpsError(
                "failed-precondition",
                "初始管理員邀請的角色設定不正確。"
              );
            }

            if (clinic.primaryAdminUid) {
              throw new HttpsError(
                "failed-precondition",
                "此院所已經有主要管理員。"
              );
            }
          }


          // -----------------------------------------------
          // 不允許 invitation 覆蓋既有 staff
          // -----------------------------------------------

          const existingStaffDoc =
            await transaction.get(staffRef);


          if (existingStaffDoc.exists) {

            const existing =
              existingStaffDoc.data();


            if (
              existing.clinicId === clinicId &&
              isStaffActive(existing)
            ) {
              throw new HttpsError(
                "already-exists",
                "你已經是此院所成員。"
              );
            }


            if (
              existing.clinicId === clinicId &&
              !isStaffActive(existing)
            ) {
              throw new HttpsError(
                "failed-precondition",
                "此帳號目前已被停用，請由院所管理員重新啟用。"
              );
            }


            // 目前 clinicStaff/{uid} 架構一個 UID 只能有一份 staff 文件。
            // MVP 先禁止 invitation 覆蓋另一院所 membership。
            throw new HttpsError(
              "failed-precondition",
              "此帳號目前已連結其他院所，暫時無法直接接受此邀請。"
            );
          }


          // -----------------------------------------------
          // 建立 clinicStaff
          // -----------------------------------------------

          const timestamp =
            admin.firestore.FieldValue
              .serverTimestamp();


          transaction.create(
            staffRef,
            {
              clinicId,

              clinicName:
                String(
                  clinic.displayName ||
                  clinic.clinicName ||
                  clinic.name ||
                  ""
                ).trim(),

              displayName:
                String(
                  invite.displayName || ""
                ).trim(),

              email:
                inviteEmail,

              emailNormalized:
                inviteEmail,

              role:
                String(invite.role || ""),

              department:
                String(
                  invite.department || ""
                ).trim(),

              active: true,

              status: "active",

              createdBy:
                invite.createdByUid || null,

              createdAt:
                timestamp,

              updatedAt:
                timestamp
            }
          );
          if (isInitialAdmin) {
            transaction.update(
              clinicRef,
              {
                primaryAdminUid:
                  uid,

                updatedAt:
                  timestamp
              }
            );
          }


          // -----------------------------------------------
          // Invitation 一次性消耗
          // -----------------------------------------------

          transaction.update(
            inviteRef,
            {
              status: "accepted",

              acceptedAt:
                timestamp,

              acceptedByUid:
                uid
            }
          );


          return {
            clinicId,
            role: String(invite.role || ""),
            email: inviteEmail
          };
        }
      );


    // -----------------------------------------------------
    // 4. Audit Logs
    // -----------------------------------------------------

    await recordAuditLogSafely({
      action: "staff.invite.accept",
      actorUid: uid,
      actorClinicId: result.clinicId,
      targetType: "staffInvite",
      targetId: inviteId,
      result: "success"
    });


    await recordAuditLogSafely({
      action: "staff.create",
      actorUid: uid,
      actorClinicId: result.clinicId,
      targetType: "clinicStaff",
      targetId: uid,
      result: "success"
    });


    return {
      success: true,
      clinicId: result.clinicId,
      role: result.role
    };
  }
);