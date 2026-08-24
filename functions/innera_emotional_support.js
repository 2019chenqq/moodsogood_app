"use strict";

const emotionalSupportChatSchema = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["reply", "followUpQuestion"],
  properties: {
    reply: { type: "string" },
    followUpQuestion: {
      anyOf: [{ type: "string" }, { type: "null" }],
    },
  },
});

function createEmotionalSupportApiResponse({
  reply,
  followUpQuestion,
  model,
  promptVersion,
  completion,
}) {
  return {
    reply,
    followUpQuestion,
    sources: [],
    suggestedActions: [],
    recordDraft: null,
    eventDrafts: [],
    safetyLevel: "normal",
    requiresFixedSafetyUi: false,
    model,
    promptVersion,
    inputTokens: completion?.usage?.prompt_tokens ?? null,
    outputTokens: completion?.usage?.completion_tokens ?? null,
  };
}

function selectInneraChatResponseSchema({
  mode,
  followUpQuestionRequest,
  followUpQuestionsSchema,
  inneraChatSchema,
  physicalHealthChatSchema,
}) {
  if (followUpQuestionRequest) return followUpQuestionsSchema;
  if (mode === "emotionalSupport") return emotionalSupportChatSchema;
  if (mode === "physicalHealth") return physicalHealthChatSchema;
  return inneraChatSchema;
}

module.exports = {
  createEmotionalSupportApiResponse,
  emotionalSupportChatSchema,
  selectInneraChatResponseSchema,
};
