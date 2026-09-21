const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");

exports.createClinicStaff = onCall(
  {
    region: "us-central1",
  },
  async (request) => {

    // 1. 必須登入
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入院所帳號。"
      );
    }

    const callerUid = request.auth.uid;

    // 2. 取得目前登入者資料
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

    // 3. 只有 admin 能新增
    if (
      caller.active !== true ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以新增成員。"
      );
    }

    const {
      displayName,
      email,
      password,
      role,
      department
    } = request.data || {};

    const cleanName =
      String(displayName || "").trim();

    const cleanEmail =
      String(email || "")
        .trim()
        .toLowerCase();

    const cleanPassword =
      String(password || "");

    const cleanDepartment =
      String(department || "").trim();

    const allowedRoles = [
      "admin",
      "doctor",
      "nurse",
      "staff"
    ];

    // 4. 基本驗證
    if (!cleanName) {
      throw new HttpsError(
        "invalid-argument",
        "請輸入姓名。"
      );
    }

    if (!cleanEmail) {
      throw new HttpsError(
        "invalid-argument",
        "請輸入 Email。"
      );
    }

    if (cleanPassword.length < 6) {
      throw new HttpsError(
        "invalid-argument",
        "密碼至少需要 6 碼。"
      );
    }

    if (!allowedRoles.includes(role)) {
      throw new HttpsError(
        "invalid-argument",
        "角色設定不正確。"
      );
    }


    let newUser = null;

    try {

      // 5. 建立 Firebase Authentication 帳號
      newUser =
        await admin
          .auth()
          .createUser({
            email: cleanEmail,
            password: cleanPassword,
            displayName: cleanName,
            disabled: false
          });


      // 6. 建立 clinicStaff
      await db
        .collection("clinicStaff")
        .doc(newUser.uid)
        .set({

          clinicId:
            caller.clinicId,

          clinicName:
            caller.clinicName || "",

          displayName:
            cleanName,

          email:
            cleanEmail,

          role,

          department:
            cleanDepartment,

          active:
            true,

          createdBy:
            callerUid,

          createdAt:
            admin.firestore.FieldValue.serverTimestamp(),

          updatedAt:
            admin.firestore.FieldValue.serverTimestamp()

        });


      return {
        success: true,
        uid: newUser.uid,
        email: cleanEmail
      };


    } catch (error) {

      console.error(
        "[createClinicStaff] failed",
        error
      );


      // 如果 Auth 建成功但 Firestore 建失敗，
      // 把剛建立的 Auth 帳號清掉
      if (newUser?.uid) {
        try {
          await admin
            .auth()
            .deleteUser(newUser.uid);
        } catch (cleanupError) {
          console.error(
            "[createClinicStaff] cleanup failed",
            cleanupError
          );
        }
      }


      if (
        error.code ===
        "auth/email-already-exists"
      ) {
        throw new HttpsError(
          "already-exists",
          "這個 Email 已經有帳號。"
        );
      }


      throw new HttpsError(
        "internal",
        "建立院所成員失敗。"
      );
    }
  }
);

exports.disableClinicStaff = onCall(
  {
    region: "us-central1",
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


    const {
      staffUid
    } = request.data || {};


    if (!staffUid) {
      throw new HttpsError(
        "invalid-argument",
        "缺少院所成員 UID。"
      );
    }


    if (
      callerUid === staffUid
    ) {
      throw new HttpsError(
        "failed-precondition",
        "不能停用自己的帳號。"
      );
    }


    const callerDoc =
      await db
        .collection("clinicStaff")
        .doc(callerUid)
        .get();


    if (!callerDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "找不到院所管理員資料。"
      );
    }


    const caller =
      callerDoc.data();


    if (
      caller.active !== true ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以停用成員。"
      );
    }


    const targetRef =
      db
        .collection("clinicStaff")
        .doc(staffUid);


    const targetDoc =
      await targetRef.get();


    if (!targetDoc.exists) {
      throw new HttpsError(
        "not-found",
        "找不到院所成員。"
      );
    }


    const target =
      targetDoc.data();


    if (
      target.clinicId !==
      caller.clinicId
    ) {
      throw new HttpsError(
        "permission-denied",
        "不能停用其他院所的成員。"
      );
    }


    try {

      await admin
        .auth()
        .updateUser(
          staffUid,
          {
            disabled: true
          }
        );


      await targetRef.update({

        active: false,

        disabledBy:
          callerUid,

        disabledAt:
          admin.firestore
            .FieldValue
            .serverTimestamp(),

        updatedAt:
          admin.firestore
            .FieldValue
            .serverTimestamp()

      });


      return {
        success: true,
        uid: staffUid
      };


    } catch (error) {

      console.error(
        "[disableClinicStaff] failed",
        error
      );


      throw new HttpsError(
        "internal",
        "停用院所成員失敗。"
      );
    }
  }
);

exports.enableClinicStaff = onCall(
  {
    region: "us-central1",
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


    const {
      staffUid
    } = request.data || {};


    if (!staffUid) {
      throw new HttpsError(
        "invalid-argument",
        "缺少院所成員 UID。"
      );
    }


    const callerDoc =
      await db
        .collection("clinicStaff")
        .doc(callerUid)
        .get();


    if (!callerDoc.exists) {
      throw new HttpsError(
        "permission-denied",
        "找不到院所管理員資料。"
      );
    }


    const caller =
      callerDoc.data();


    if (
      caller.active !== true ||
      caller.role !== "admin"
    ) {
      throw new HttpsError(
        "permission-denied",
        "只有院所管理員可以啟用成員。"
      );
    }


    const targetRef =
      db
        .collection("clinicStaff")
        .doc(staffUid);


    const targetDoc =
      await targetRef.get();


    if (!targetDoc.exists) {
      throw new HttpsError(
        "not-found",
        "找不到院所成員。"
      );
    }


    const target =
      targetDoc.data();


    if (
      target.clinicId !==
      caller.clinicId
    ) {
      throw new HttpsError(
        "permission-denied",
        "不能啟用其他院所的成員。"
      );
    }


    try {

      await admin
        .auth()
        .updateUser(
          staffUid,
          {
            disabled: false
          }
        );


      await targetRef.update({

        active: true,

        enabledBy:
          callerUid,

        enabledAt:
          admin.firestore
            .FieldValue
            .serverTimestamp(),

        updatedAt:
          admin.firestore
            .FieldValue
            .serverTimestamp()

      });


      return {
        success: true,
        uid: staffUid
      };


    } catch (error) {

      console.error(
        "[enableClinicStaff] failed",
        error
      );


      throw new HttpsError(
        "internal",
        "啟用院所成員失敗。"
      );
    }
  }
);
