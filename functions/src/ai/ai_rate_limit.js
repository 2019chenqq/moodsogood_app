"use strict";

const AI_RATE_LIMIT_COLLECTION = "ai_rate_limits";
const AI_GLOBAL_RATE_LIMIT_COLLECTION = "ai_global_rate_limits";
const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
const DEFAULT_LIMITS = Object.freeze({
  perMinute: 12,
  perHour: 120,
  perDay: 300,
});
const DEFAULT_GLOBAL_LIMITS = Object.freeze({
  perMinute: 120,
  perDay: 5000,
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
  const perDay = positiveInteger(limits.perDay, DEFAULT_LIMITS.perDay);
  const minute = windowState(previous?.minute, safeNowMs, MINUTE_MS);
  const hour = windowState(previous?.hour, safeNowMs, HOUR_MS);
  const day = windowState(previous?.day, safeNowMs, DAY_MS);

  if (day.count > perDay) {
    return {
      allowed: false,
      limitType: "day",
      retryAfterSeconds: retryAfterSeconds(safeNowMs, DAY_MS),
    };
  }
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
    day,
  };
}

function evaluateGlobalAiRateLimit(
  previous,
  nowMs = Date.now(),
  limits = {},
) {
  return evaluateAiRateLimit(previous, nowMs, {
    perMinute: positiveInteger(
      limits.perMinute,
      DEFAULT_GLOBAL_LIMITS.perMinute,
    ),
    // The global limiter intentionally has no practical hourly ceiling. Its
    // hard budget boundaries are the burst limit and the daily project cap.
    perHour: Number.MAX_SAFE_INTEGER,
    perDay: positiveInteger(limits.perDay, DEFAULT_GLOBAL_LIMITS.perDay),
  });
}

async function enforceAiRateLimit({
  db,
  admin,
  uid,
  feature,
  limits = DEFAULT_LIMITS,
  globalLimits = DEFAULT_GLOBAL_LIMITS,
  nowMs = Date.now(),
}) {
  const userRef = db.collection(AI_RATE_LIMIT_COLLECTION).doc(uid);
  const globalRef = db.collection(AI_GLOBAL_RATE_LIMIT_COLLECTION).doc("current");

  return db.runTransaction(async (transaction) => {
    const [userSnapshot, globalSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(globalRef),
    ]);
    const userResult = evaluateAiRateLimit(userSnapshot.data(), nowMs, limits);
    if (!userResult.allowed) {
      throw new AiRateLimitError(
        userResult.retryAfterSeconds,
        userResult.limitType,
      );
    }
    const globalResult = evaluateGlobalAiRateLimit(
      globalSnapshot.data(),
      nowMs,
      globalLimits,
    );
    if (!globalResult.allowed) {
      throw new AiRateLimitError(
        globalResult.retryAfterSeconds,
        `global_${globalResult.limitType}`,
      );
    }

    transaction.set(
      userRef,
      {
        minute: userResult.minute,
        hour: userResult.hour,
        day: userResult.day,
        lastFeature: String(feature || "unknown").slice(0, 80),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(
      globalRef,
      {
        minute: globalResult.minute,
        day: globalResult.day,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { user: userResult, global: globalResult };
  });
}

module.exports = {
  AI_RATE_LIMIT_COLLECTION,
  AI_GLOBAL_RATE_LIMIT_COLLECTION,
  AiRateLimitError,
  DEFAULT_LIMITS,
  DEFAULT_GLOBAL_LIMITS,
  evaluateAiRateLimit,
  evaluateGlobalAiRateLimit,
  enforceAiRateLimit,
};
