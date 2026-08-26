"use strict";

function createInneraLatencyState(startedAt = Date.now()) {
  return {
    startedAt,
    rateLimitMs: 0,
    preparationMs: 0,
    openAiMs: 0,
    parseNormalizeMs: 0,
    usageWriteMs: 0,
    safeHistoryCount: 0,
    historyCharacters: 0,
  };
}

function elapsedSince(startedAt, now = Date.now()) {
  return Math.max(0, Number(now) - Number(startedAt));
}

function buildInneraLatencyLog({
  state,
  mode,
  completion,
  promptVersion,
  status,
  now = Date.now(),
}) {
  const usage = completion?.usage || {};
  const inputTokens = Math.max(0, Number(usage.prompt_tokens) || 0);
  return {
    mode,
    status,
    totalMs: elapsedSince(state.startedAt, now),
    rateLimitMs: state.rateLimitMs,
    preparationMs: state.preparationMs,
    openAiMs: state.openAiMs,
    parseNormalizeMs: state.parseNormalizeMs,
    usageWriteMs: state.usageWriteMs,
    safeHistoryCount: state.safeHistoryCount,
    historyCharacters: state.historyCharacters,
    inputTokens,
    outputTokens: Math.max(0, Number(usage.completion_tokens) || 0),
    cachedInputTokens: Math.min(
      inputTokens,
      Math.max(0, Number(usage.prompt_tokens_details?.cached_tokens) || 0),
    ),
    promptVersion,
  };
}

function buildRecentReviewContextSizeLog({
  context,
  contextSources,
  safeHistoryCount,
  historyCharacters,
  completion,
  usedV2Summary = false,
  usedLegacyFallback = false,
  selectedDomains = [],
  usedDomainFallback = false,
  fullSummary,
}) {
  const requestContext = context && typeof context === "object" ? context : {};
  const sources = Array.isArray(contextSources) ? contextSources : [];
  const jsonCharacters = (value) => JSON.stringify(value ?? null).length;
  const measuredKeys = [
    "sleepTimeStats",
    "emotionStats",
    "recentDailyRecords",
    "dailyRecordStats",
    "dailyHealthAggregateSummary",
    "recentQuickRecordExamples",
    "recentDiaries",
    "activeMedications",
    "recentMedicationAdjustments",
    "recentPeriodCycles",
    "recentReviewSummary",
    "recentReviewEvidence",
  ];
  const otherContext = Object.fromEntries(
    Object.entries(requestContext).filter(([key]) => !measuredKeys.includes(key)),
  );
  const recentDailyRecords = requestContext.recentDailyRecords;
  const emotions = requestContext.emotionStats?.emotions;
  const sleepEvidence = requestContext.sleepTimeStats?.bedtimeEvidence;
  const reviewEvidence = requestContext.recentReviewEvidence;
  const evidenceCount = reviewEvidence && typeof reviewEvidence === "object"
    ? Object.values(reviewEvidence).reduce(
        (total, items) => total + (Array.isArray(items) ? items.length : 0),
        0,
      )
    : 0;
  return {
    totalContextCharacters: jsonCharacters(requestContext),
    contextSourcesCharacters: jsonCharacters(sources),
    sleepTimeStatsCharacters: jsonCharacters(requestContext.sleepTimeStats),
    emotionStatsCharacters: jsonCharacters(requestContext.emotionStats),
    recentDailyRecordsCharacters: jsonCharacters(recentDailyRecords),
    dailyRecordStatsCharacters: jsonCharacters(requestContext.dailyRecordStats),
    dailyHealthAggregateSummaryCharacters: jsonCharacters(
      requestContext.dailyHealthAggregateSummary,
    ),
    recentQuickRecordExamplesCharacters: jsonCharacters(
      requestContext.recentQuickRecordExamples,
    ),
    recentDiariesCharacters: jsonCharacters(requestContext.recentDiaries),
    activeMedicationsCharacters: jsonCharacters(requestContext.activeMedications),
    recentMedicationAdjustmentsCharacters: jsonCharacters(
      requestContext.recentMedicationAdjustments,
    ),
    recentPeriodCyclesCharacters: jsonCharacters(requestContext.recentPeriodCycles),
    recentReviewSummaryCharacters: jsonCharacters(
      requestContext.recentReviewSummary,
    ),
    summaryCharacters: jsonCharacters(requestContext.recentReviewSummary),
    evidenceCharacters: jsonCharacters(reviewEvidence),
    evidenceCount,
    finalContextCharacters: jsonCharacters(requestContext),
    usedV2Summary: Boolean(usedV2Summary),
    usedLegacyFallback: Boolean(usedLegacyFallback),
    selectedDomains: Array.isArray(selectedDomains)
      ? selectedDomains.map((domain) => String(domain))
      : [],
    domainCount: Array.isArray(selectedDomains) ? selectedDomains.length : 0,
    selectedSummaryCharacters: jsonCharacters(
      requestContext.recentReviewSummary,
    ),
    fullSummaryCharacters: jsonCharacters(fullSummary),
    usedDomainFallback: Boolean(usedDomainFallback),
    otherContextCharacters: jsonCharacters(otherContext),
    recentDailyRecordCount: Array.isArray(recentDailyRecords)
      ? recentDailyRecords.length
      : 0,
    contextSourceCount: sources.length,
    emotionStatsItemCount: Array.isArray(emotions) ? emotions.length : 0,
    sleepEvidenceCount: Array.isArray(sleepEvidence) ? sleepEvidence.length : 0,
    safeHistoryCount: Math.max(0, Number(safeHistoryCount) || 0),
    historyCharacters: Math.max(0, Number(historyCharacters) || 0),
    inputTokens: completion?.usage?.prompt_tokens ?? null,
  };
}

module.exports = {
  buildInneraLatencyLog,
  buildRecentReviewContextSizeLog,
  createInneraLatencyState,
  elapsedSince,
};
