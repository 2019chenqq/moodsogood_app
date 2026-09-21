const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { openAiApiKey, revenueCatSecretApiKey, DEFAULT_AI_MODEL } = require("../config/params");
const { requireAiProAccess, requireAiCapacity } = require("../ai/access");
const { normalizeSummaryInput, alignEventSummaries } = require("./innera_event_summaries");
const { detectInneraSelfHarm } = require("../chat/innera_safety");
const { createAiUsageTracker, AI_QUOTED_POINTS } = require("../ai/ai_usage");
const { db, admin } = require("../config/firebase");
const OpenAI = require("openai");
const { stripMarkdownFence } = require("../shared/normalization");

const EVENT_SUMMARY_PROMPT_VERSION = "innera-event-summary-v1";

exports.summarizeInneraHealthEvents = onCall(
  { secrets: [openAiApiKey, revenueCatSecretApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再整理事件紀錄");
    }
    await requireAiProAccess(request.auth.uid);
    const input = normalizeSummaryInput({
      messages: request.data?.messages,
      eventDrafts: request.data?.eventDrafts,
      detectSafety: detectInneraSelfHarm,
    });
    if (!input.eventDrafts.length) {
      throw new HttpsError("invalid-argument", "沒有可整理的事件草稿");
    }
    if (!input.messages.some((item) => item.role === "user")) {
      throw new HttpsError("invalid-argument", "沒有可整理的使用者對話");
    }

    await requireAiCapacity(request.auth.uid, "innera_chat");
    const usageTracker = createAiUsageTracker({
      db,
      admin,
      uid: request.auth.uid,
      requestId: request.data?.requestId,
      feature: "innera_chat",
      model: DEFAULT_AI_MODEL,
      promptVersion: EVENT_SUMMARY_PROMPT_VERSION,
      quotedPoints: AI_QUOTED_POINTS.innera_chat,
      metadata: { task: "event_summaries", eventCount: input.eventDrafts.length },
    });
    await usageTracker.start();
    let completion;
    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) throw new HttpsError("internal", "缺少 OPENAI_API_KEY 設定");
      const client = new OpenAI({ apiKey });
      completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.2,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "innera_event_summaries",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: ["eventSummaries"],
              properties: {
                eventSummaries: {
                  type: "array",
                  maxItems: 20,
                  items: {
                    type: "object",
                    additionalProperties: false,
                    required: ["eventId", "summary"],
                    properties: {
                      eventId: { type: "string" },
                      summary: { type: "string" },
                    },
                  },
                },
              },
            },
          },
        },
        messages: [
          {
            role: "system",
            content: [
              "你是心域 Innera 的事件紀錄整理器，只做逐事件摘要。",
              "eventDrafts 的結構化欄位是事實基準，不得改寫其數值或推論新欄位。",
              "對話只用來補足使用者明確說過的自然語言脈絡；不得把 assistant 問句寫入摘要。",
              "每個 eventDraft 必須輸出且只輸出一個相同 eventId 的 summary，不得合併不同事件。",
              "同一事件的多輪使用者補充應整合成一段自然、精簡的繁體中文紀錄。",
              "不得捏造原因、壓力、睡眠、食慾或因果。數值量表是絕對 1–5；除非使用者明說，不得寫成比平常上升或下降。",
              "摘要不必機械式重複所有數字，不要診斷，不要處理或重新分類安全風險。",
            ].join("\n"),
          },
          { role: "user", content: JSON.stringify(input) },
        ],
      });
      const raw = String(completion.choices?.[0]?.message?.content || "").trim();
      if (!raw) throw new Error("Empty event summary response");
      const parsed = JSON.parse(stripMarkdownFence(raw));
      const eventSummaries = alignEventSummaries(parsed.eventSummaries, input.eventDrafts);
      if (eventSummaries.some((item) => !item.summary)) throw new Error("Missing event summary");
      await usageTracker.succeed(completion);
      return { eventSummaries, model: DEFAULT_AI_MODEL, promptVersion: EVENT_SUMMARY_PROMPT_VERSION };
    } catch (error) {
      await usageTracker.fail(error, completion);
      console.error("summarizeInneraHealthEvents failed", { message: error?.message || String(error) });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "目前無法整理事件文字，原草稿不會變更。");
    }
  },
);
