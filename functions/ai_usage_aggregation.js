"use strict";

const TAIPEI_UTC_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function nonNegativeNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function previousTaipeiDayRange(now = new Date()) {
  const shifted = new Date(now.getTime() + TAIPEI_UTC_OFFSET_MS);
  const todayStartUtcMs =
    Date.UTC(
      shifted.getUTCFullYear(),
      shifted.getUTCMonth(),
      shifted.getUTCDate(),
    ) - TAIPEI_UTC_OFFSET_MS;
  const startMs = todayStartUtcMs - DAY_MS;
  const dateKey = new Date(startMs + TAIPEI_UTC_OFFSET_MS)
    .toISOString()
    .slice(0, 10);

  return {
    dateKey,
    start: new Date(startMs),
    end: new Date(todayStartUtcMs),
  };
}

function summarizeAiUsageEvents(events, dateKey) {
  const summary = {
    schemaVersion: 1,
    date: dateKey,
    billingMode: "observe_only",
    currency: "USD",
    eventCount: 0,
    succeededCount: 0,
    failedCount: 0,
    pendingCount: 0,
    quotedPoints: 0,
    estimatedCostMicroUsd: 0,
    inputTokens: 0,
    cachedInputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    costPerPointMicroUsd: null,
    byFeature: {},
  };

  for (const rawEvent of events || []) {
    const event =
      rawEvent && typeof rawEvent === "object" ? rawEvent : {};
    const feature = String(event.feature || "unknown").trim() || "unknown";
    const status = String(event.status || "pending").trim();
    const succeeded = status === "succeeded";
    const failed = status === "failed";
    const quotedPoints = succeeded
      ? nonNegativeNumber(event.quotedPoints)
      : 0;
    const estimatedCostMicroUsd = nonNegativeNumber(
      event.estimatedCostMicroUsd,
    );
    const inputTokens = nonNegativeNumber(event.inputTokens);
    const cachedInputTokens = nonNegativeNumber(event.cachedInputTokens);
    const outputTokens = nonNegativeNumber(event.outputTokens);
    const totalTokens = nonNegativeNumber(event.totalTokens);

    summary.eventCount += 1;
    summary.succeededCount += succeeded ? 1 : 0;
    summary.failedCount += failed ? 1 : 0;
    summary.pendingCount += succeeded || failed ? 0 : 1;
    summary.quotedPoints += quotedPoints;
    summary.estimatedCostMicroUsd += estimatedCostMicroUsd;
    summary.inputTokens += inputTokens;
    summary.cachedInputTokens += cachedInputTokens;
    summary.outputTokens += outputTokens;
    summary.totalTokens += totalTokens;

    const featureSummary = summary.byFeature[feature] || {
      eventCount: 0,
      succeededCount: 0,
      failedCount: 0,
      pendingCount: 0,
      quotedPoints: 0,
      estimatedCostMicroUsd: 0,
      inputTokens: 0,
      cachedInputTokens: 0,
      outputTokens: 0,
      totalTokens: 0,
      costPerPointMicroUsd: null,
    };
    featureSummary.eventCount += 1;
    featureSummary.succeededCount += succeeded ? 1 : 0;
    featureSummary.failedCount += failed ? 1 : 0;
    featureSummary.pendingCount += succeeded || failed ? 0 : 1;
    featureSummary.quotedPoints += quotedPoints;
    featureSummary.estimatedCostMicroUsd += estimatedCostMicroUsd;
    featureSummary.inputTokens += inputTokens;
    featureSummary.cachedInputTokens += cachedInputTokens;
    featureSummary.outputTokens += outputTokens;
    featureSummary.totalTokens += totalTokens;
    summary.byFeature[feature] = featureSummary;
  }

  if (summary.quotedPoints > 0) {
    summary.costPerPointMicroUsd = Math.round(
      summary.estimatedCostMicroUsd / summary.quotedPoints,
    );
  }
  for (const featureSummary of Object.values(summary.byFeature)) {
    if (featureSummary.quotedPoints > 0) {
      featureSummary.costPerPointMicroUsd = Math.round(
        featureSummary.estimatedCostMicroUsd /
          featureSummary.quotedPoints,
      );
    }
  }

  return summary;
}

module.exports = {
  previousTaipeiDayRange,
  summarizeAiUsageEvents,
};
