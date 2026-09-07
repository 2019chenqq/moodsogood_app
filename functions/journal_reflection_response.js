"use strict";

const journalReflectionResponseFormat = {
  type: "json_schema",
  json_schema: {
    name: "journal_reflection_response",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["summary", "emotionObservation", "topics", "positiveFeedback",
        "gratitudeQuestions", "tomorrowAction", "crisisDetected"],
      properties: {
        summary: { type: "string" },
        emotionObservation: { type: "string" },
        topics: { type: "array", items: { type: "string" }, minItems: 3, maxItems: 5 },
        positiveFeedback: { type: "string" },
        gratitudeQuestions: { type: "array", items: { type: "string" }, minItems: 3, maxItems: 3 },
        tomorrowAction: { type: "string" },
        crisisDetected: { type: "boolean" },
      },
    },
  },
};

function normalizeReflection(payload, fallbackCrisis, actualModel) {
  const topics = Array.isArray(payload.topics)
    ? payload.topics.map((item) => String(item).trim()).filter(Boolean).slice(0, 5)
    : [];
  const gratitudeQuestions = Array.isArray(payload.gratitudeQuestions)
    ? payload.gratitudeQuestions
        .map((item) => String(item).trim())
        .filter(Boolean)
        .slice(0, 3)
    : [];

  return {
    summary: String(payload.summary || "").trim(),
    emotionObservation: String(payload.emotionObservation || "").trim(),
    topics,
    positiveFeedback: String(payload.positiveFeedback || "").trim(),
    gratitudeQuestions,
    tomorrowAction: String(payload.tomorrowAction || "").trim(),
    crisisDetected: Boolean(payload.crisisDetected) || fallbackCrisis,
    isMock: false,
    model: actualModel,
    emotionModel:
      payload.emotionModel && typeof payload.emotionModel === "object"
        ? payload.emotionModel
        : null,
  };
}

module.exports = { journalReflectionResponseFormat, normalizeReflection };
