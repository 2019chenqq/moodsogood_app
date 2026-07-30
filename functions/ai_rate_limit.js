"use strict";

const AI_RATE_LIMIT_COLLECTION = "ai_rate_limits";
const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DEFAULT_LIMITS = Object.freeze({
  perMinute: 12,
  perHour: 120,
});

class AiRateLimitError extends Error {
  constructor(retryAfterSeconds, limitType) {
    super("AI request rate limit exceeded");
    this.name = "AiRateLimitError";
    this.code = "ai-rate-limit";
    this.retryAfterSeconds = retryAfterSeconds;
    this.limitType = limitType;
  }
}

function positiveInteger(value, fallback) {
  const parsed = Math.floor(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function windowState(previous, nowMs, windowMs) {
  const key = Math.floor(nowMs / windowMs);
  const previousKey = Number(previous?.key);
  const previousCount = Math.max(0, Math.floor(Number(previous?.count) || 0));
  return {
    key,
    count: previousKey === key ? previousCount + 1 : 1,
  };
}

function retryAfterSeconds(nowMs, windowMs) {
  const windowEnd = (Math.floor(nowMs / windowMs) + 1) * windowMs;
  return Math.max(1, Math.ceil((windowEnd - nowMs) / 1000));
}

function evaluateAiRateLimit(previous, nowMs = Date.now(), limits = {}) {
  const safeNowMs = Number.isFinite(Number(nowMs))
    ? Number(nowMs)
    : Date.now();
  const perMinute = positiveInteger(
    limits.perMinute,
    DEFAULT_LIMITS.perMinute,
  );
  const perHour = positiveInteger(limits.perHour, DEFAULT_LIMITS.perHour);
  const minute = windowState(previous?.minute, safeNowMs, MINUTE_MS);
  const hour = windowState(previous?.hour, safeNowMs, HOUR_MS);

  if (hour.count > perHour) {
    return {
      allowed: false,
      limitType: "hour",
      retryAfterSeconds: retryAfterSeconds(safeNowMs, HOUR_MS),
    };
  }
  if (minute.count > perMinute) {
    return {
      allowed: false,
      limitType: "minute",
      retryAfterSeconds: retryAfterSeconds(safeNowMs, MINUTE_MS),
    };
  }
  return {
    allowed: true,
    minute,
    hour,
  };
}

async function enforceAiRateLimit({
  db,
  admin,
  uid,
  feature,
  limits = DEFAULT_LIMITS,
  nowMs = Date.now(),
}) {
  const ref = db.collection(AI_RATE_LIMIT_COLLECTION).doc(uid);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const result = evaluateAiRateLimit(snapshot.data(), nowMs, limits);
    if (!result.allowed) {
      throw new AiRateLimitError(
        result.retryAfterSeconds,
        result.limitType,
      );
    }

    transaction.set(
      ref,
      {
        minute: result.minute,
        hour: result.hour,
        lastFeature: String(feature || "unknown").slice(0, 80),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return result;
  });
}

module.exports = {
  AI_RATE_LIMIT_COLLECTION,
  AiRateLimitError,
  DEFAULT_LIMITS,
  evaluateAiRateLimit,
  enforceAiRateLimit,
};
