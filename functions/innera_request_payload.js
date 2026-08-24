"use strict";

function buildInneraContextPayload({
  mode,
  context,
  contextSources,
  recordDraft,
  emotionDimensions,
}) {
  const usesStructuredExtractionInput =
    mode === "dailyRecord" || mode === "physicalHealth";
  return {
    mode,
    context,
    contextSources,
    ...(usesStructuredExtractionInput
      ? { recordDraft, emotionDimensions }
      : {}),
  };
}

module.exports = { buildInneraContextPayload };
