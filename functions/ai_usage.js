"use strict";

const crypto = require("crypto");

const AI_USAGE_COLLECTION = "ai_usage_events";
const AI_PRICING_VERSION = "openai_2025_04_14";

// Prices are USD per 1M tokens. Keep pricing versioned so historical costs do
// not change when the provider updates its price list.
const AI_MODEL_PRICING = Object.freeze({
  "gpt-4.1-mini": Object.freeze({
    input: 0.4,
    cachedInput: 0.1,
    output: 1.6,
  }),
});

const AI_QUOTED_POINTS = Object.freeze({
  journal_reflection: 2,
  diary_draft: 1,
  song_recommendation: 1,
  innera_chat: 1,
  recent_review: 3,
});

function normalizeRequestId(value) {
  const requestId = String(value || "").trim();
  if (/^[A-Za-z0-9_-]{16,128}$/.test(requestId)) return requestId;
  return crypto.randomUUID();
}

function normalizeModelName(model) {
  const name = String(model || "").trim();
  if (AI_MODEL_PRICING[name]) return name;
  return Object.keys(AI_MODEL_PRICING).find((key) => name.startsWith(`${key}-`)) || "";
}

function extractTokenUsage(completion) {
  const usage = completion?.usage || {};
  const inputTokens = Math.max(0, Number(usage.prompt_tokens) || 0);
  const cachedInputTokens = Math.min(
    inputTokens,
    Math.max(0, Number(usage.prompt_tokens_details?.cached_tokens) || 0),
  );
  const outputTokens = Math.max(0, Number(usage.completion_tokens) || 0);
  const providerTotal = Math.max(0, Number(usage.total_tokens) || 0);
  return {
    inputTokens,
    cachedInputTokens,
    outputTokens,
    totalTokens: providerTotal || inputTokens + outputTokens,
  };
}

function estimateCostMicroUsd(model, tokenUsage) {
  const pricing = AI_MODEL_PRICING[normalizeModelName(model)];
  if (!pricing) return null;
  const uncachedInputTokens = Math.max(
    0,
    tokenUsage.inputTokens - tokenUsage.cachedInputTokens,
  );
  return Math.ceil(
    uncachedInputTokens * pricing.input +
      tokenUsage.cachedInputTokens * pricing.cachedInput +
      tokenUsage.outputTokens * pricing.output,
  );
}

function classifyError(error) {
  const status = Number(error?.status) || 0;
  if (status === 401 || status === 403) return "provider_auth";
  if (status === 429) return "provider_rate_limit";
  if (status >= 500) return "provider_unavailable";
  if (error?.name === "AbortError") return "timeout";
  if (error?.name === "SyntaxError") return "invalid_provider_response";
  if (error?.code === "failed-precondition") return "configuration";
  return "internal";
}

function createAiUsageTracker({
  db,
  admin,
  uid,
  requestId,
  feature,
  model,
  promptVersion,
  quotedPoints,
  metadata,
}) {
  const safeRequestId = normalizeRequestId(requestId);
  const safeFeature = String(feature || "unknown").trim().slice(0, 80);
  const startedAtMs = Date.now();
  // Keep every provider call as a separate event. requestId is a correlation
  // key; future point deduction should use a separate idempotent ledger.
  const ref = db.collection(AI_USAGE_COLLECTION).doc();
  const safeMetadata =
    metadata && typeof metadata === "object" ? metadata : undefined;

  async function safeSet(data) {
    try {
      await ref.set(data, { merge: true });
    } catch (error) {
      // Usage telemetry must never make the user-facing AI request fail.
      console.error("AI usage write failed", {
        feature: safeFeature,
        requestId: safeRequestId,
        message: error?.message,
      });
    }
  }

  const common = {
    uid,
    requestId: safeRequestId,
    feature: safeFeature,
    model,
    promptVersion: String(promptVersion || "unknown").slice(0, 120),
    pricingVersion: AI_PRICING_VERSION,
    quotedPoints: Math.max(0, Number(quotedPoints) || 0),
    chargedPoints: 0,
    billingMode: "observe_only",
    ...(safeMetadata ? { metadata: safeMetadata } : {}),
  };

  return {
    requestId: safeRequestId,
    async start() {
      await safeSet({
        ...common,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    },
    async succeed(completion) {
      const tokenUsage = extractTokenUsage(completion);
      const estimatedCostMicroUsd = estimateCostMicroUsd(model, tokenUsage);
      await safeSet({
        ...common,
        ...tokenUsage,
        ...(estimatedCostMicroUsd == null ? {} : { estimatedCostMicroUsd }),
        status: "succeeded",
        billable: true,
        durationMs: Date.now() - startedAtMs,
        providerRequestId:
          String(completion?._request_id || completion?.request_id || "")
            .trim()
            .slice(0, 160) || null,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    },
    async fail(error, completion) {
      const tokenUsage = extractTokenUsage(completion);
      const estimatedCostMicroUsd = estimateCostMicroUsd(model, tokenUsage);
      await safeSet({
        ...common,
        ...tokenUsage,
        ...(estimatedCostMicroUsd == null ? {} : { estimatedCostMicroUsd }),
        status: "failed",
        billable: false,
        errorCategory: classifyError(error),
        durationMs: Date.now() - startedAtMs,
        providerRequestId:
          String(
            error?.request_id ||
              completion?._request_id ||
              completion?.request_id ||
              "",
          )
            .trim()
            .slice(0, 160) || null,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    },
  };
}

module.exports = {
  AI_MODEL_PRICING,
  AI_PRICING_VERSION,
  AI_QUOTED_POINTS,
  classifyError,
  createAiUsageTracker,
  estimateCostMicroUsd,
  extractTokenUsage,
  normalizeRequestId,
};
