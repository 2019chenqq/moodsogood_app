"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  previousTaipeiDayRange,
  summarizeAiUsageEvents,
} = require("../ai_usage_aggregation");

test("previousTaipeiDayRange returns the previous local calendar day", () => {
  const range = previousTaipeiDayRange(
    new Date("2026-08-12T17:00:00.000Z"),
  );

  assert.equal(range.dateKey, "2026-08-12");
  assert.equal(range.start.toISOString(), "2026-08-11T16:00:00.000Z");
  assert.equal(range.end.toISOString(), "2026-08-12T16:00:00.000Z");
});

test("summarizeAiUsageEvents groups cost and successful points", () => {
  const summary = summarizeAiUsageEvents(
    [
      {
        feature: "innera_chat",
        status: "succeeded",
        quotedPoints: 1,
        estimatedCostMicroUsd: 1200,
        inputTokens: 2000,
        cachedInputTokens: 500,
        outputTokens: 200,
        totalTokens: 2200,
      },
      {
        feature: "recent_review",
        status: "succeeded",
        quotedPoints: 3,
        estimatedCostMicroUsd: 3200,
        inputTokens: 6000,
        outputTokens: 500,
        totalTokens: 6500,
      },
      {
        feature: "innera_chat",
        status: "failed",
        quotedPoints: 1,
        estimatedCostMicroUsd: 400,
        inputTokens: 500,
        outputTokens: 100,
        totalTokens: 600,
      },
      {
        feature: "diary_draft",
        status: "pending",
        quotedPoints: 1,
      },
    ],
    "2026-08-12",
  );

  assert.equal(summary.eventCount, 4);
  assert.equal(summary.succeededCount, 2);
  assert.equal(summary.failedCount, 1);
  assert.equal(summary.pendingCount, 1);
  assert.equal(summary.quotedPoints, 4);
  assert.equal(summary.estimatedCostMicroUsd, 4800);
  assert.equal(summary.costPerPointMicroUsd, 1200);
  assert.equal(summary.inputTokens, 8500);
  assert.equal(summary.outputTokens, 800);
  assert.equal(summary.byFeature.innera_chat.eventCount, 2);
  assert.equal(summary.byFeature.innera_chat.quotedPoints, 1);
  assert.equal(
    summary.byFeature.innera_chat.costPerPointMicroUsd,
    1600,
  );
});

test("failed usage contributes cost but does not consume quoted points", () => {
  const summary = summarizeAiUsageEvents(
    [
      {
        feature: "journal_reflection",
        status: "failed",
        quotedPoints: 2,
        estimatedCostMicroUsd: 700,
      },
    ],
    "2026-08-12",
  );

  assert.equal(summary.quotedPoints, 0);
  assert.equal(summary.estimatedCostMicroUsd, 700);
  assert.equal(summary.costPerPointMicroUsd, null);
});

test("empty days still produce a complete deterministic summary", () => {
  const summary = summarizeAiUsageEvents([], "2026-08-12");

  assert.equal(summary.eventCount, 0);
  assert.equal(summary.quotedPoints, 0);
  assert.equal(summary.costPerPointMicroUsd, null);
  assert.deepEqual(summary.byFeature, {});
});
