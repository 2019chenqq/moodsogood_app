"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createRecentReviewApiResponse,
  createFollowUpSummaryFallbackResponse,
  createNoFollowUpQuestionsResponse,
  formatRecentReviewMedicationList,
  isFollowUpQuestionRequest,
  isFollowUpSummaryRequest,
  mergeCompletionUsage,
  normalizeFollowUpSummaryReply,
  normalizeFollowUpQuestionsReply,
  parseFollowUpQuestionsCompletion,
  parseFollowUpSummaryCompletion,
  parseInneraChatCompletion,
  recentReviewChatSchema,
} = require("../innera_ai_response");

test("recent review medication lists preserve per-unit dose and pill count", () => {
  const context = {
    activeMedications: [
      {
        name: "樂命達",
        dosePerUnit: 50,
        pillCount: 1,
        dose: 50,
        unit: "mg",
        times: ["睡前"],
      },
      {
        name: "安保思樂錠",
        dosePerUnit: 50,
        pillCount: 2,
        dose: 100,
        unit: "mg",
        times: ["睡前"],
      },
      {
        name: "克癇平",
        dosePerUnit: 0.5,
        pillCount: 0.5,
        dose: 0.25,
        unit: "mg",
        times: ["需要時"],
      },
    ],
  };
  assert.equal(
    formatRecentReviewMedicationList(
      "把我現在正在用的藥都列出來",
      context,
      "fallback",
    ),
    [
      "目前使用中的藥物：",
      "",
      "• 樂命達：50 mg × 1 顆，睡前",
      "• 安保思樂錠：50 mg × 2 顆，睡前",
      "• 克癇平：0.5 mg × 0.5 顆，需要時",
    ].join("\n"),
  );
});

test("recent review medication list falls back to total dose for legacy data", () => {
  assert.equal(
    formatRecentReviewMedicationList(
      "我目前有哪些藥？",
      {
        activeMedications: [{
          name: "舊藥物",
          dose: 12.5,
          unit: "mg",
          times: [],
        }],
      },
      "fallback",
    ),
    "目前使用中的藥物：\n\n• 舊藥物：12.5 mg",
  );
});

test("recent review medication list reads V2 summary medications", () => {
  assert.equal(
    formatRecentReviewMedicationList(
      "我目前有哪些藥？",
      {
        recentReviewSummary: {
          medications: [{
            name: "摘要藥物",
            dosePerUnit: 25,
            pillCount: 2,
            unit: "mg",
            times: ["睡前"],
          }],
        },
      },
      "fallback",
    ),
    "目前使用中的藥物：\n\n• 摘要藥物：25 mg × 2 顆，睡前",
  );
});

test("recent review medication formatter leaves unrelated replies unchanged", () => {
  assert.equal(
    formatRecentReviewMedicationList(
      "最近睡眠如何？",
      { activeMedications: [{ name: "藥物 A" }] },
      "原本的睡眠回顧",
    ),
    "原本的睡眠回顧",
  );
});

test("recent review schema contains only reply and followUpQuestion", () => {
  assert.equal(recentReviewChatSchema.type, "object");
  assert.equal(recentReviewChatSchema.additionalProperties, false);
  assert.deepEqual(recentReviewChatSchema.required, ["reply", "followUpQuestion"]);
  assert.deepEqual(Object.keys(recentReviewChatSchema.properties), [
    "reply",
    "followUpQuestion",
  ]);
});

test("recent review keeps the existing outer API response contract", () => {
  const contextSources = [{ label: "最近紀錄", dateRange: "近 7 天", count: 3 }];
  const response = createRecentReviewApiResponse({
    reply: "目前三筆資料顯示的睡眠時間不同，資料仍有限，還不能判斷長期趨勢。",
    followUpQuestion: null,
    contextSources,
    model: "test-model",
    promptVersion: "test-version",
    completion: { usage: { prompt_tokens: 180, completion_tokens: 28 } },
  });
  assert.equal(response.recordDraft, null);
  assert.deepEqual(response.eventDrafts, []);
  assert.equal(response.sources, contextSources);
  assert.deepEqual(response.suggestedActions, []);
  assert.equal(response.safetyLevel, "normal");
  assert.equal(response.requiresFixedSafetyUi, false);
  assert.equal(response.inputTokens, 180);
  assert.equal(response.outputTokens, 28);
});

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
