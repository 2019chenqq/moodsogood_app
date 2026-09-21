const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { hasRecentSignIn, deleteUserAccountData } = require("./account_deletion");
const { db, admin } = require("../config/firebase");

exports.deleteOwnAccount = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "請先登入後再刪除帳號");
  }
  if (!hasRecentSignIn(request.auth)) {
    throw new HttpsError(
      "failed-precondition",
      "為了保護帳號，請重新登入後再執行刪除",
      { reason: "recent_sign_in_required" },
    );
  }

  try {
    await deleteUserAccountData({
      db,
      auth: admin.auth(),
      bucket: admin.storage().bucket(),
      uid: request.auth.uid,
    });
    return { deleted: true };
  } catch (error) {
    console.error("Account deletion failed", {
      code: error?.code || "unknown",
    });
    throw new HttpsError(
      "internal",
      "帳號資料刪除尚未完成，請稍後重試",
    );
  }
});
