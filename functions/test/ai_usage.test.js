"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  classifyError,
  estimateCostMicroUsd,
  extractTokenUsage,
  normalizeRequestId,
} = require("../ai_usage");

test("extractTokenUsage includes cached and total tokens", () => {
  assert.deepEqual(
    extractTokenUsage({
      usage: {
        prompt_tokens: 1000,
        prompt_tokens_details: { cached_tokens: 400 },
        completion_tokens: 250,
        total_tokens: 1250,
      },
    }),
    {
      inputTokens: 1000,
      cachedInputTokens: 400,
      outputTokens: 250,
      totalTokens: 1250,
    },
  );
});

test("estimateCostMicroUsd uses uncached, cached, and output pricing", () => {
  assert.equal(
    estimateCostMicroUsd("gpt-4.1-mini", {
      inputTokens: 1000,
      cachedInputTokens: 400,
      outputTokens: 250,
    }),
    680,
  );
});

test("unknown model has no guessed cost", () => {
  assert.equal(
    estimateCostMicroUsd("unknown-model", {
      inputTokens: 10,
      cachedInputTokens: 0,
      outputTokens: 10,
    }),
    null,
  );
});

test("request IDs are accepted only in the safe format", () => {
  assert.equal(
    normalizeRequestId("1722230000000_abcdefghijklmnop"),
    "1722230000000_abcdefghijklmnop",
  );
  assert.match(normalizeRequestId("../unsafe"), /^[0-9a-f-]{36}$/);
});

test("provider errors are grouped without storing error messages", () => {
  assert.equal(classifyError({ status: 429 }), "provider_rate_limit");
  assert.equal(classifyError({ status: 503 }), "provider_unavailable");
  assert.equal(classifyError(new SyntaxError("bad JSON")), "invalid_provider_response");
});
