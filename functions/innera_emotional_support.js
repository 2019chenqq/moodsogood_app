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
  followUpSummaryRequest,
  followUpQuestionsSchema,
  followUpSummarySchema,
  inneraChatSchema,
  physicalHealthChatSchema,
  recentReviewChatSchema,
  specialRecentReviewRequest,
}) {
  if (followUpQuestionRequest) return followUpQuestionsSchema;
  if (followUpSummaryRequest) return followUpSummarySchema;
  if (mode === "emotionalSupport") return emotionalSupportChatSchema;
  if (mode === "physicalHealth") return physicalHealthChatSchema;
  if (mode === "recentReview" && !specialRecentReviewRequest) {
    return recentReviewChatSchema;
  }
  return inneraChatSchema;
}

module.exports = {
  createEmotionalSupportApiResponse,
  emotionalSupportChatSchema,
  selectInneraChatResponseSchema,
};
