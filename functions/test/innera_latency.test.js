"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildInneraLatencyLog,
  buildRecentReviewContextSizeLog,
  createInneraLatencyState,
  elapsedSince,
} = require("../innera_latency");

test("recent review context breakdown measures sizes without exposing values", () => {
  const context = {
    sleepTimeStats: {
      validSleepTimeDays: 2,
      bedtimeEvidence: [{ date: "private-date", sleepTime: "private-time" }],
    },
    emotionStats: {
      emotions: [{ name: "private-emotion", occurrenceDays: 2 }],
    },
    dailyRecordStats: { recordedDays: 2 },
    recentDiaries: [{ summary: "private-diary" }],
    activeMedications: [{ name: "private-medication" }],
    customAggregate: { value: "private-other" },
  };
  const contextSources = [{ label: "private-source", count: 2 }];
  const before = JSON.stringify(context);
  const queries = [
    "最近睡眠有什麼變化？",
    "最近最常出現什麼情緒？",
    "最近有沒有明顯的變化？",
  ];
  const logs = queries.map(() => buildRecentReviewContextSizeLog({
    context,
    contextSources,
    safeHistoryCount: 8,
    historyCharacters: 557,
    completion: { usage: { prompt_tokens: 8057 } },
    usedV2Summary: true,
    usedLegacyFallback: false,
    selectedDomains: ["sleep"],
    usedDomainFallback: false,
    fullSummary: context,
  }));

  assert.equal(JSON.stringify(context), before);
  assert.equal(logs.length, 3);
  for (const log of logs) {
    assert.equal(log.totalContextCharacters, JSON.stringify(context).length);
    assert.equal(
      log.contextSourcesCharacters,
      JSON.stringify(contextSources).length,
    );
    assert.equal(
      log.sleepTimeStatsCharacters,
      JSON.stringify(context.sleepTimeStats).length,
    );
    assert.equal(
      log.emotionStatsCharacters,
      JSON.stringify(context.emotionStats).length,
    );
    assert.equal(log.recentDailyRecordsCharacters, JSON.stringify(null).length);
    assert.equal(log.contextSourceCount, 1);
    assert.equal(log.emotionStatsItemCount, 1);
    assert.equal(log.sleepEvidenceCount, 1);
    assert.equal(log.safeHistoryCount, 8);
    assert.equal(log.historyCharacters, 557);
    assert.equal(log.inputTokens, 8057);
    assert.equal(log.finalContextCharacters, JSON.stringify(context).length);
    assert.equal(log.recentReviewSummaryCharacters, JSON.stringify(null).length);
    assert.equal(log.usedV2Summary, true);
    assert.equal(log.usedLegacyFallback, false);
    assert.deepEqual(log.selectedDomains, ["sleep"]);
    assert.equal(log.domainCount, 1);
    assert.equal(
      log.selectedSummaryCharacters,
      JSON.stringify(null).length,
    );
    assert.equal(log.fullSummaryCharacters, JSON.stringify(context).length);
    assert.equal(log.usedDomainFallback, false);
    const serializedLog = JSON.stringify(log);
    for (const privateValue of [
      "private-date",
      "private-time",
      "private-emotion",
      "private-diary",
      "private-medication",
      "private-other",
      "private-source",
    ]) {
      assert.equal(serializedLog.includes(privateValue), false);
    }
  }
});

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
