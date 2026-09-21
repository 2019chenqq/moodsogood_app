"use strict";

function createPhysicalHealthChatSchema(eventDraftsSchema) {
  return Object.freeze({
    type: "object",
    additionalProperties: false,
    required: ["reply", "followUpQuestion", "eventDrafts"],
    properties: {
      reply: { type: "string" },
      followUpQuestion: {
        anyOf: [{ type: "string" }, { type: "null" }],
      },
      eventDrafts: eventDraftsSchema,
    },
  });
}

function createPhysicalHealthApiResponse({
  reply,
  followUpQuestion,
  eventDrafts,
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
    eventDrafts,
    safetyLevel: "normal",
    requiresFixedSafetyUi: false,
    model,
    promptVersion,
    inputTokens: completion?.usage?.prompt_tokens ?? null,
    outputTokens: completion?.usage?.completion_tokens ?? null,
  };
}

module.exports = {
  createPhysicalHealthApiResponse,
  createPhysicalHealthChatSchema,
};
