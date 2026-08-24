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

module.exports = {
  buildInneraLatencyLog,
  createInneraLatencyState,
  elapsedSince,
};
