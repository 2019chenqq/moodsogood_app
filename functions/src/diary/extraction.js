const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { openAiApiKey, revenueCatSecretApiKey, DEFAULT_AI_MODEL } = require("../config/params");
const { requireAiProAccess, requireAiCapacity } = require("../ai/access");
const { prepareDiaryMessages } = require("./diary_extraction_input");
const { createAiUsageTracker, AI_QUOTED_POINTS } = require("../ai/ai_usage");
const { db, admin } = require("../config/firebase");
const OpenAI = require("openai");
const { diaryExtractionSchema } = require("./schemas");
const { stripMarkdownFence } = require("../shared/normalization");

const DIARY_EXTRACTION_PROMPT_VERSION = "diary_extraction_v2";

exports.generateInneraDiaryDraft = onCall(
  { secrets: [openAiApiKey, revenueCatSecretApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再整理今日紀錄");
    }
    await requireAiProAccess(request.auth.uid);
    const data = request.data || {};
    const recordDate = String(data.recordDate || "").trim().slice(0, 10);
    const requestedField = String(data.requestedField || "").trim().slice(0, 40);
    const currentDraft =
      data.currentDraft && typeof data.currentDraft === "object"
        ? data.currentDraft
        : null;
    let messages;
    try {
      messages = prepareDiaryMessages(data.messages);
    } catch (error) {
      if (error instanceof RangeError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }
    if (!messages.some((item) => item.role === "user")) {
      throw new HttpsError("invalid-argument", "沒有可整理的使用者對話");
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(recordDate)) {
      throw new HttpsError("invalid-argument", "紀錄日期格式錯誤");
    }

    await requireAiCapacity(request.auth.uid, "diary_draft");
    const usageTracker = createAiUsageTracker({
      db,
      admin,
      uid: request.auth.uid,
      requestId: data.requestId,
      feature: "diary_draft",
      model: DEFAULT_AI_MODEL,
      promptVersion: DIARY_EXTRACTION_PROMPT_VERSION,
      quotedPoints: AI_QUOTED_POINTS.diary_draft,
    });
    await usageTracker.start();
    let completion;

    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("failed-precondition", "缺少 OPENAI_API_KEY 設定");
      }
      const client = new OpenAI({ apiKey });
      completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.2,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "innera_diary_extraction",
            strict: true,
            schema: diaryExtractionSchema,
          },
        },
        messages: [
          {
            role: "system",
            content: [
              "你是「心域 Innera」中的每日紀錄整理助手。",
              "你的工作不是診斷使用者，也不是替使用者創造故事，而是根據當日對話整理可供確認的日記草稿。",
              "只根據使用者的原始敘述整理事實；assistant 的回覆僅用於理解問答，不可當成使用者經歷。不得虛構事件、感恩事項、成就、人物或情緒。輸出前逐一核對所有 user 訊息，確保開頭、中段、結尾的事件均有保留，並採用使用者後續更正的版本。",
              "source 必須是 explicit、summarized、inferred、suggested、missing 之一。",
              "資訊不足時使用空字串、空陣列並列入 missingFields，不得為填滿欄位而猜測。",
              "content 是完整日記正文，使用第一人稱並保留使用者語氣；依原文資訊量決定篇幅，不限制為短摘要。依時間或事件分段，保留所有不同的重要事件、人物關係、事情經過、行動、對話、原因、結果與轉折；沒有情緒或症狀的生活事件也必須保留。只刪重複語句與無資訊的口頭語，不為精簡而省略事件或把事件只改寫成情緒、症狀清單。",
              "標題提供 1 至 3 個，每個約 8 至 20 個中文字，不使用診斷標籤或制式勵志語。",
              "最想記錄的瞬間必須是具體事件、決定、對話或轉折；沒有就空陣列。",
              "做得不錯必須有具體行為證據；沒有就空陣列。",
              "自我照顧最多三項，每項低門檻、具體、不說教，不提供藥物或醫療指示。",
              "感恩只有在使用者明確提到感謝、被幫助、安心、珍惜或正向連結時整理，否則空陣列並可提供一個問題。",
              "不要過度正向化，也不要將痛苦包裝成勵志故事。",
              "情緒比喻不得污名、羞辱、恐嚇或病理化；App 會以本地審核詞庫取代此候選。",
              "主題曲只能輸出情緒與搜尋輪廓，絕對不可輸出歌名、歌手、平台 ID 或連結。",
              "musicTags 只使用 Schema 允許的英文標籤。",
              "avoidThemes 至少包含自傷、自殺、絕望、美化死亡與報復等不適合內容。",
              "不得做醫療診斷。低落本身不等於高風險；只有對話有自傷、自殺、傷人或立即危險內容時才標記 safetyRisk。",
              "evidence 只能短述對話依據，不要加入不存在的細節。",
              requestedField
                ? `這次只重新產生 ${requestedField}；其餘欄位沿用提供的 currentDraft。`
                : "完整整理所有可從對話獲得的欄位。",
              "只輸出符合 JSON Schema 的合法 JSON。",
            ].join("\n"),
          },
          ...(currentDraft
            ? [
                {
                  role: "user",
                  content: `目前草稿：${JSON.stringify(currentDraft)}`,
                },
              ]
            : []),
          ...messages,
        ],
      });
      const rawText = String(
        completion.choices?.[0]?.message?.content || "",
      ).trim();
      if (!rawText) throw new Error("Empty diary extraction response");
      const parsed = JSON.parse(stripMarkdownFence(rawText));
      const result = {
        id: recordDate,
        recordDate,
        promptVersion: DIARY_EXTRACTION_PROMPT_VERSION,
        createdAt: new Date().toISOString(),
        ...parsed,
        status: "pendingReview",
        modelName: DEFAULT_AI_MODEL,
        conversationMessageCount: messages.length,
        parseSucceeded: true,
      };
      await usageTracker.succeed(completion);
      return result;
    } catch (error) {
      await usageTracker.fail(error, completion);
      console.error("generateInneraDiaryDraft failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
        code: error?.code,
        requestId: error?.request_id,
        model: DEFAULT_AI_MODEL,
      });
      if (error instanceof HttpsError) throw error;
      if (error?.status === 401 || error?.status === 404) {
        throw new HttpsError(
          "failed-precondition",
          "AI 服務設定暫時無法使用。",
        );
      }
      if (error?.status === 429) {
        throw new HttpsError(
          "resource-exhausted",
          "AI 使用額度已達限制，請稍後再試。",
        );
      }
      throw new HttpsError(
        "internal",
        "目前無法整理今日紀錄，請稍後再試。",
      );
    }
  },
);
