const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { revenueCatSecretApiKey } = require("../config/params");
const { readQuota } = require("./innera_free_quota");
const { db } = require("../config/firebase");
const { requireAiProAccess } = require("./access");

exports.getInneraAiFreeQuota = onCall(
  { secrets: [revenueCatSecretApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "請先登入");
    return readQuota({ db, uid: request.auth.uid, verifyPro: requireAiProAccess });
  },
);
