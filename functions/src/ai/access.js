const { requireProEntitlement, ProEntitlementError } = require("./pro_entitlement");
const { db, admin } = require("../config/firebase");
const { revenueCatSecretApiKey, aiTestProUids, aiTestProEmails } = require("../config/params");
const { HttpsError } = require("firebase-functions/v2/https");
const { enforceAiRateLimit, AiRateLimitError } = require("./ai_rate_limit");

async function requireAiProAccess(uid) {
  try {
    await requireProEntitlement({
      db,
      admin,
      uid,
      apiKey: revenueCatSecretApiKey.value(),
      testProUids: aiTestProUids.value(),
      testProEmails: aiTestProEmails.value(),
    });
  } catch (error) {
    if (error instanceof ProEntitlementError) {
      if (error.code === "required") {
        throw new HttpsError(
          "permission-denied",
          "此 AI 功能需要有效的 Pro 訂閱。",
          { reason: "pro_entitlement_required" },
        );
      }
      if (error.code === "configuration") {
        throw new HttpsError(
          "failed-precondition",
          "訂閱驗證服務尚未完成設定。",
          { reason: "pro_entitlement_not_configured" },
        );
      }
    }
    console.error("Pro entitlement verification failed", {
      uid,
      message: error?.message || String(error),
    });
    throw new HttpsError(
      "unavailable",
      "目前無法驗證 Pro 訂閱，請稍後再試。",
      { reason: "pro_entitlement_unavailable" },
    );
  }
}

async function requireAiCapacity(uid, feature) {
  try {
    await enforceAiRateLimit({
      db,
      admin,
      uid,
      feature,
    });
  } catch (error) {
    if (error instanceof AiRateLimitError) {
      throw new HttpsError(
        "resource-exhausted",
        "AI 使用過於頻繁，請稍後再試。",
        {
          reason: "ai_rate_limit",
          limitType: error.limitType,
          retryAfterSeconds: error.retryAfterSeconds,
        },
      );
    }
    console.error("AI rate limit check failed", {
      uid,
      feature,
      message: error?.message || String(error),
    });
    throw new HttpsError(
      "unavailable",
      "AI 服務暫時無法確認使用額度，請稍後再試。",
    );
  }
}

module.exports = {
  requireAiCapacity,
  requireAiProAccess,
};
