"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createFollowUpSummaryFallbackResponse,
  createNoFollowUpQuestionsResponse,
  isFollowUpQuestionRequest,
  isFollowUpSummaryRequest,
  mergeCompletionUsage,
  normalizeFollowUpSummaryReply,
  normalizeFollowUpQuestionsReply,
  parseFollowUpQuestionsCompletion,
  parseFollowUpSummaryCompletion,
  parseInneraChatCompletion,
} = require("../innera_ai_response");

test("parseInneraChatCompletion returns a non-empty structured reply", () => {
  const result = parseInneraChatCompletion({
    choices: [
      {
        finish_reason: "stop",
        message: { content: '{"reply":"摘要內容"}' },
      },
    ],
  });

  assert.equal(result.reply, "摘要內容");
  assert.equal(result.failure, null);
  assert.equal(result.diagnostics.finishReason, "stop");
});

test("parseInneraChatCompletion identifies an empty reply without exposing content", () => {
  const result = parseInneraChatCompletion({
    choices: [
      {
        finish_reason: "stop",
        message: { content: '{"reply":""}' },
      },
    ],
  });

  assert.equal(result.reply, "");
  assert.equal(result.failure, "missing_reply");
  assert.equal(result.diagnostics.rawTextLength, 12);
});

test("follow-up question requests can safely fall back to no questions", () => {
  assert.equal(
    isFollowUpQuestionRequest("recentReview", "你正在執行「回診摘要補問」。"),
    true,
  );
  const fallback = createNoFollowUpQuestionsResponse();
  assert.equal(fallback.reply, '{"questions":[]}');
});

test("direct follow-up questions are wrapped in the existing App contract", () => {
  const result = parseFollowUpQuestionsCompletion({
    choices: [{
      finish_reason: "stop",
      message: {
        content: JSON.stringify({
          questions: ["這項不適最常在一天中的什麼時段出現？", "最希望醫師先協助哪一件事？"],
        }),
      },
    }],
  });

  assert.equal(result.failure, null);
  assert.deepEqual(JSON.parse(result.reply).questions, [
    "這項不適最常在一天中的什麼時段出現？",
    "最希望醫師先協助哪一件事？",
  ]);
  assert.equal(result.parsed.reply, result.reply);
});

test("follow-up questions accept a valid empty array", () => {
  const result = normalizeFollowUpQuestionsReply('{"questions":[]}');
  assert.equal(result.failure, null);
  assert.equal(result.reply, '{"questions":[]}');
});

test("follow-up summary requests can safely fall back to local records", () => {
  assert.equal(
    isFollowUpSummaryRequest(
      "recentReview",
      "你正在產生可供回診使用的資料摘要。",
    ),
    true,
  );
  const fallback = createFollowUpSummaryFallbackResponse();
  assert.deepEqual(JSON.parse(fallback.reply).keyChanges, []);
  assert.equal(fallback.parsed.reply, fallback.reply);
});

test("follow-up summary reply accepts fenced JSON and canonicalizes arrays", () => {
  const normalized = normalizeFollowUpSummaryReply(`前言\n\`\`\`json
{"keyChanges":[" 變化一 ","變化二","變化三"],"discussionPriorities":[],"timelineRelations":["時間關聯"],"dataLimitations":[]}
\`\`\``);

  assert.equal(normalized.failure, null);
  assert.deepEqual(JSON.parse(normalized.reply), {
    keyChanges: ["變化一", "變化二", "變化三"],
    discussionPriorities: [],
    timelineRelations: ["時間關聯"],
    medicationSubjectiveSummaries: [],
    userSharedNotes: [],
    userReportedConcerns: [],
    dataLimitations: [],
  });
});

test("follow-up summary preserves medication subjective summaries", () => {
  const normalized = normalizeFollowUpSummaryReply(JSON.stringify({
      keyChanges: ["change one", "change two", "change three"],
      discussionPriorities: [],
      timelineRelations: [],
      medicationSubjectiveSummaries: [
        "使用者於調藥後第3、7天主觀回報睡眠有變化；使用者認為可能與此次用藥調整有關。",
      ],
      userSharedNotes: [],
      userReportedConcerns: [],
      dataLimitations: [],
    }));

  assert.deepEqual(
    JSON.parse(normalized.reply).medicationSubjectiveSummaries,
    [
      "使用者於調藥後第3、7天主觀回報睡眠有變化；使用者認為可能與此次用藥調整有關。",
    ],
  );
});

test("follow-up summary reply rejects an empty keyChanges array", () => {
  const normalized = normalizeFollowUpSummaryReply(JSON.stringify({
    keyChanges: [],
    discussionPriorities: [],
    timelineRelations: [],
    userReportedConcerns: [],
    dataLimitations: [],
  }));

  assert.equal(normalized.reply, "");
  assert.equal(normalized.failure, "invalid_follow_up_key_changes");
});

test("direct follow-up completion is wrapped in the existing App contract", () => {
  const result = parseFollowUpSummaryCompletion({
    choices: [{
      finish_reason: "stop",
      message: {
        content: JSON.stringify({
          keyChanges: ["變化一", "變化二", "變化三"],
          discussionPriorities: ["先討論睡眠"],
          timelineRelations: [],
          userReportedConcerns: [],
          dataLimitations: [],
        }),
      },
    }],
  });

  assert.equal(result.failure, null);
  assert.deepEqual(JSON.parse(result.reply).keyChanges, [
    "變化一",
    "變化二",
    "變化三",
  ]);
  assert.equal(result.parsed.reply, result.reply);
});

test("mergeCompletionUsage includes every retry attempt", () => {
  const merged = mergeCompletionUsage([
    {
      usage: {
        prompt_tokens: 100,
        completion_tokens: 5,
        total_tokens: 105,
        prompt_tokens_details: { cached_tokens: 20 },
      },
    },
    {
      usage: {
        prompt_tokens: 110,
        completion_tokens: 15,
        total_tokens: 125,
        prompt_tokens_details: { cached_tokens: 30 },
      },
    },
  ]);

  assert.equal(merged.usage.prompt_tokens, 210);
  assert.equal(merged.usage.completion_tokens, 20);
  assert.equal(merged.usage.total_tokens, 230);
  assert.equal(merged.usage.prompt_tokens_details.cached_tokens, 50);
});
