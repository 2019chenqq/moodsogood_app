"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createEmotionalSupportApiResponse,
  emotionalSupportChatSchema,
  selectInneraChatResponseSchema,
} = require("../innera_emotional_support");
const { inneraModePrompt, sanitizeModeFollowUp } = require("../innera_mode_prompt");

test("emotional support schema contains only reply and followUpQuestion", () => {
  assert.equal(emotionalSupportChatSchema.type, "object");
  assert.equal(emotionalSupportChatSchema.additionalProperties, false);
  assert.deepEqual(emotionalSupportChatSchema.required, ["reply", "followUpQuestion"]);
  assert.deepEqual(Object.keys(emotionalSupportChatSchema.properties), [
    "reply",
    "followUpQuestion",
  ]);
});

test("emotional support keeps the existing outer API response contract", () => {
  const response = createEmotionalSupportApiResponse({
    reply: "今天像是累積了不少煩躁。如果你現在想說，我會陪你慢慢整理；不想一次講完整也沒關係。是工作上的事比較卡，還是整天都有這種感覺？",
    followUpQuestion: null,
    model: "test-model",
    promptVersion: "test-version",
    completion: {
      usage: { prompt_tokens: 120, completion_tokens: 35 },
    },
  });

  assert.deepEqual(Object.keys(response), [
    "reply",
    "followUpQuestion",
    "sources",
    "suggestedActions",
    "recordDraft",
    "eventDrafts",
    "safetyLevel",
    "requiresFixedSafetyUi",
    "model",
    "promptVersion",
    "inputTokens",
    "outputTokens",
  ]);
  assert.equal(response.recordDraft, null);
  assert.deepEqual(response.eventDrafts, []);
  assert.deepEqual(response.sources, []);
  assert.deepEqual(response.suggestedActions, []);
  assert.equal(response.safetyLevel, "normal");
  assert.equal(response.requiresFixedSafetyUi, false);
  assert.equal(response.inputTokens, 120);
  assert.equal(response.outputTokens, 35);
});

test("short emotional messages retain non-form conversational constraints", () => {
  const prompt = inneraModePrompt("emotionalSupport");
  for (const message of ["今天真的很煩。", "工作好累，我現在什麼都不想講。"]) {
    assert.ok(message.length > 0);
    assert.match(prompt, /自然承接/);
    assert.match(prompt, /最多提出一個|至多提出一個/);
    assert.match(prompt, /不強迫量化/);
    assert.match(prompt, /不得宣稱已記錄|不得宣稱已記錄或已正式保存/);
  }
  assert.equal(sanitizeModeFollowUp("emotionalSupport", "你的情緒強度 1～5 分是幾分？"), "");
});

test("other modes and special follow-up requests keep their existing schemas", () => {
  const fullSchema = { name: "full" };
  const followUpSchema = { name: "follow-up" };
  const followUpSummarySchema = { name: "follow-up-summary" };
  const physicalHealthSchema = { name: "physical-health" };
  const recentReviewSchema = { name: "recent-review" };
  assert.equal(selectInneraChatResponseSchema({
    mode: "dailyRecord",
    followUpQuestionRequest: false,
    followUpQuestionsSchema: followUpSchema,
    inneraChatSchema: fullSchema,
    physicalHealthChatSchema: physicalHealthSchema,
    recentReviewChatSchema: recentReviewSchema,
    specialRecentReviewRequest: false,
  }), fullSchema);
  assert.equal(selectInneraChatResponseSchema({
    mode: "physicalHealth",
    followUpQuestionRequest: false,
    followUpQuestionsSchema: followUpSchema,
    inneraChatSchema: fullSchema,
    physicalHealthChatSchema: physicalHealthSchema,
    recentReviewChatSchema: recentReviewSchema,
    specialRecentReviewRequest: false,
  }), physicalHealthSchema);
  assert.equal(selectInneraChatResponseSchema({
    mode: "recentReview",
    followUpQuestionRequest: false,
    followUpQuestionsSchema: followUpSchema,
    inneraChatSchema: fullSchema,
    physicalHealthChatSchema: physicalHealthSchema,
    recentReviewChatSchema: recentReviewSchema,
    specialRecentReviewRequest: false,
  }), recentReviewSchema);
  assert.equal(selectInneraChatResponseSchema({
    mode: "recentReview",
    followUpQuestionRequest: true,
    followUpQuestionsSchema: followUpSchema,
    inneraChatSchema: fullSchema,
    physicalHealthChatSchema: physicalHealthSchema,
    recentReviewChatSchema: recentReviewSchema,
    specialRecentReviewRequest: true,
  }), followUpSchema);
  assert.equal(selectInneraChatResponseSchema({
    mode: "recentReview",
    followUpQuestionRequest: false,
    followUpSummaryRequest: true,
    followUpQuestionsSchema: followUpSchema,
    followUpSummarySchema,
    inneraChatSchema: fullSchema,
    physicalHealthChatSchema: physicalHealthSchema,
    recentReviewChatSchema: recentReviewSchema,
    specialRecentReviewRequest: true,
  }), followUpSummarySchema);
});
