"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildInneraLatencyLog,
  createInneraLatencyState,
  elapsedSince,
} = require("../innera_latency");

test("latency log contains only timing and request metadata", () => {
  const state = createInneraLatencyState(1000);
  Object.assign(state, {
    rateLimitMs: 12,
    preparationMs: 8,
    openAiMs: 420,
    parseNormalizeMs: 4,
    usageWriteMs: 16,
    safeHistoryCount: 8,
    historyCharacters: 2400,
  });
  const log = buildInneraLatencyLog({
    state,
    mode: "emotionalSupport",
    completion: {
      usage: {
        prompt_tokens: 500,
        completion_tokens: 80,
        prompt_tokens_details: { cached_tokens: 120 },
      },
    },
    promptVersion: "test-version",
    status: "succeeded",
    now: 1500,
  });

  assert.deepEqual(log, {
    mode: "emotionalSupport",
    status: "succeeded",
    totalMs: 500,
    rateLimitMs: 12,
    preparationMs: 8,
    openAiMs: 420,
    parseNormalizeMs: 4,
    usageWriteMs: 16,
    safeHistoryCount: 8,
    historyCharacters: 2400,
    inputTokens: 500,
    outputTokens: 80,
    cachedInputTokens: 120,
    promptVersion: "test-version",
  });
  for (const forbidden of [
    "message", "history", "recordDraft", "eventDrafts", "emotion",
    "symptom", "diary", "image", "uid",
  ]) {
    assert.equal(Object.hasOwn(log, forbidden), false);
  }
});

test("missing completion usage is represented by zero token counts", () => {
  const state = createInneraLatencyState(2000);
  const log = buildInneraLatencyLog({
    state,
    mode: "physicalHealth",
    completion: undefined,
    promptVersion: "test-version",
    status: "failed",
    now: 2010,
  });
  assert.equal(log.inputTokens, 0);
  assert.equal(log.outputTokens, 0);
  assert.equal(log.cachedInputTokens, 0);
  assert.equal(log.totalMs, 10);
});

test("elapsed timing never becomes negative", () => {
  assert.equal(elapsedSince(100, 90), 0);
  assert.equal(elapsedSince(100, 125), 25);
});

test("all four modes produce the same privacy-safe telemetry shape", () => {
  const expectedKeys = Object.keys(buildInneraLatencyLog({
    state: createInneraLatencyState(0),
    mode: "emotionalSupport",
    promptVersion: "version",
    status: "succeeded",
    now: 1,
  }));
  for (const mode of [
    "emotionalSupport", "dailyRecord", "physicalHealth", "recentReview",
  ]) {
    const log = buildInneraLatencyLog({
      state: createInneraLatencyState(0),
      mode,
      promptVersion: "version",
      status: "succeeded",
      now: 1,
    });
    assert.deepEqual(Object.keys(log), expectedKeys);
    assert.equal(log.mode, mode);
  }
});

test("ten emotional support samples remain independent", () => {
  const samples = Array.from({ length: 10 }, (_, index) => {
    const state = createInneraLatencyState(index * 1000);
    state.openAiMs = 300 + index;
    return buildInneraLatencyLog({
      state,
      mode: "emotionalSupport",
      promptVersion: "version",
      status: "succeeded",
      now: index * 1000 + 400,
    });
  });
  assert.equal(samples.length, 10);
  assert.deepEqual(samples.map((item) => item.openAiMs), [
    300, 301, 302, 303, 304, 305, 306, 307, 308, 309,
  ]);
});
