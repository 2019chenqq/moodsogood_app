const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { openAiApiKey, revenueCatSecretApiKey, DEFAULT_AI_MODEL } = require("../config/params");
const { requireAiProAccess, requireAiCapacity } = require("../ai/access");
const { toNumber, stripMarkdownFence } = require("../shared/normalization");
const {
  normalizeDiaryFields,
  buildDiaryTextFromFields,
  detectCrisis,
  buildEmotionModel,
} = require("./record_context");
const { createAiUsageTracker, AI_QUOTED_POINTS } = require("../ai/ai_usage");
const { db, admin } = require("../config/firebase");
const OpenAI = require("openai");
const { journalReflectionResponseFormat, normalizeReflection } = require("./journal_reflection_response");

exports.generateAiJournalReflection = onCall(
  { secrets: [openAiApiKey, revenueCatSecretApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再使用此功能");
    }
    await requireAiProAccess(request.auth.uid);

    const { aiInput, diaryContent, diaryFields, dailyRecord, date } = request.data || {};

    let safeDiaryFields;
    let safeDailyRecord;
    let effectiveDate = String(date || "").trim();
    let trimmedDiary = "";

    const safeAiInput =
      aiInput && typeof aiInput === "object" && !Array.isArray(aiInput) ? aiInput : null;

    if (safeAiInput) {
      const aiDiaryText = String(safeAiInput.diaryText || "").trim();
      const aiEmotions = Array.isArray(safeAiInput.emotions) ? safeAiInput.emotions : [];
      const aiSymptoms = Array.isArray(safeAiInput.symptoms) ? safeAiInput.symptoms : [];
      const aiMoodScale = toNumber(safeAiInput.moodScale, 10);
      const aiSleep =
        safeAiInput.sleep && typeof safeAiInput.sleep === "object" && !Array.isArray(safeAiInput.sleep)
          ? safeAiInput.sleep
          : {};

      const overallMoodFromAi = aiEmotions.find((e) =>
        String(e?.name || "").includes("整體情緒"),
      );
      const anxietyFromAi = aiEmotions.find((e) => String(e?.name || "").includes("焦慮"));

      safeDiaryFields = normalizeDiaryFields({
        content: aiDiaryText,
        overallMood: overallMoodFromAi?.score,
        overallSleepQuality: aiSleep.quality,
      });

      safeDailyRecord = {
        moodScale: aiMoodScale,
        overallMood: toNumber(overallMoodFromAi?.score, null),
        anxiety: toNumber(anxietyFromAi?.score, null),
        emotions: aiEmotions
          .map((item) => {
            const name = String(item?.name || "").trim();
            const score = toNumber(item?.score, null);
            if (!name || score == null) return null;
            return { name, value: score };
          })
          .filter(Boolean),
        symptoms: aiSymptoms
          .map((item) => String(item?.name || item || "").trim())
          .filter(Boolean),
        sleep: {
          note: String(aiSleep.note || "").trim(),
          quality: toNumber(aiSleep.quality, null),
          hours: toNumber(aiSleep.hours, null),
        },
      };

      trimmedDiary = aiDiaryText.slice(0, 8000);
      effectiveDate = String(safeAiInput.date || effectiveDate || "").trim();
    } else {
      safeDiaryFields = normalizeDiaryFields(diaryFields);
      const composedDiaryText = [
        String(diaryContent || "").trim(),
        buildDiaryTextFromFields(safeDiaryFields),
      ]
        .filter(Boolean)
        .join("\n\n")
        .trim();
      trimmedDiary = composedDiaryText.slice(0, 8000);

      safeDailyRecord =
        dailyRecord && typeof dailyRecord === "object" && !Array.isArray(dailyRecord)
          ? dailyRecord
          : {};
    }

    if (!trimmedDiary) {
      throw new HttpsError("invalid-argument", "缺少可分析的日記內容");
    }

    await requireAiCapacity(request.auth.uid, "journal_reflection");
    const crisisDetected = detectCrisis(trimmedDiary);
    const emotionModel = buildEmotionModel(safeDailyRecord, safeDiaryFields, trimmedDiary);
    const usageTracker = createAiUsageTracker({
      db,
      admin,
      uid: request.auth.uid,
      requestId: request.data?.requestId,
      feature: "journal_reflection",
      model: DEFAULT_AI_MODEL,
      promptVersion: "journal_reflection_v2_schema_fix",
      quotedPoints: AI_QUOTED_POINTS.journal_reflection,
    });
    await usageTracker.start();
    let completion;

    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("internal", "缺少 OPENAI_API_KEY 設定");
      }
      const client = new OpenAI({ apiKey });
      completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.7,
        response_format: journalReflectionResponseFormat,
        messages: [
          {
            role: "system",
            content: [
              "你是一位使用繁體中文的心理支持助理。請基於完整日記欄位做文本分析，並結合提供的 emotionModel（每日紀錄情緒分析模型）產生回饋。整體情緒與綜合分數皆使用 1 到 5 分制，不可用 10 分制描述。若 emotionModel.medication.hasMedicationData 為 true，請把用藥作為觀察脈絡之一，但禁止推論藥效與醫療結果。不要做醫療診斷、不要下病名、不要保證療效。情緒觀察段落禁止提及睡眠、就寢、醒來、失眠等睡眠資訊。若內容包含明確自傷或自殺意圖，要將 crisisDetected 設為 true。你只能輸出 JSON。",
              "請依 emotionModel.moodScale 使用正確量表：moodScale 為 5 時請用 1 到 5 分制；moodScale 為 10 時請保留 1 到 10 分制，不要自行換算或折半。",
              "請用溫柔、支持、不批判的語氣回應，像一位專業心理師，避免說教、避免過度正向或空泛鼓勵。",
              "",
              "請做到：",
              "- 具體提到使用者的情緒與內容",
              "- 適度共感（讓人覺得被理解）",
              "- 不要使用制式句型",
            ].join("\n"),
          },
          {
            role: "user",
            content: JSON.stringify({
              task: "請輸出日記反思 JSON",
              rules: {
                summary: "1 段 70-140 字，須反映多個日記欄位內容",
                emotionObservation: "1 段 70-140 字，必須解讀 emotionModel.emotionEntries 的情緒名稱與分數，至少提到 2 個情緒名稱與其分數，並結合 emotionModel.moodScale 對應的整體情緒分數與風險觀察。若 moodScale 為 5，使用 1 到 5 分制；若 moodScale 為 10，保留 1 到 10 分制。若有 medication 資料可輕量提及，但不得推論療效。且不得出現任何睡眠相關字詞",
                topics: "3 到 5 個短詞",
                positiveFeedback: "1 段 70-140 字，聚焦使用者已做到的具體行為",
                gratitudeQuestions: "剛好 3 題，每題一句",
                tomorrowAction: "1 句可執行的小行動",
                crisisDetected: "boolean",
              },
              date: effectiveDate,
              aiInput: safeAiInput,
              diaryFields: safeDiaryFields,
              dailyRecord: safeDailyRecord,
              emotionModel,
              diaryContent: trimmedDiary,
            }),
          },
        ],
      });

      const rawText = completion.choices?.[0]?.message?.content || "";
      const parsed = JSON.parse(stripMarkdownFence(rawText));
      const normalized = normalizeReflection(
        parsed,
        crisisDetected,
        DEFAULT_AI_MODEL,
      );
      normalized.emotionModel = emotionModel;

      const emotionNames = (emotionModel.emotionEntries || []).map((e) => e.name);
      const usedEmotionNameCount = emotionNames.filter(
        (name) => name && normalized.emotionObservation.includes(name),
      ).length;

      if (
        !normalized.summary ||
        !normalized.emotionObservation ||
        !normalized.positiveFeedback ||
        !normalized.tomorrowAction ||
        normalized.topics.length < 3 ||
        normalized.gratitudeQuestions.length < 3 ||
        (emotionNames.length >= 2 && usedEmotionNameCount < 2)
      ) {
        throw new Error("AI 回傳內容不完整或未解讀情緒名稱分數");
      }

      await usageTracker.succeed(completion);
      return normalized;
    } catch (error) {
      await usageTracker.fail(error, completion);
      console.error("generateAiJournalReflection failed:", error);
      throw new HttpsError("internal", "AI 生成失敗，請稍後再試");
    }
  },
);
