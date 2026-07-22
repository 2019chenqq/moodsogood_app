const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");

// 初始化 Admin SDK (擁有繞過 Security Rules 的最高權限)
admin.initializeApp();
const db = admin.firestore();
const openAiApiKey = defineSecret("OPENAI_API_KEY");
const DEFAULT_AI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";

const CRISIS_KEYWORDS = [
  "想死",
  "不想活",
  "自殺",
  "傷害自己",
  "結束生命",
  "活不下去",
  "去死",
  "消失掉",
  "了結",
];

const DIARY_FIELD_KEYS = [
  "title",
  "content",
  "themeSong",
  "highlight",
  "metaphor",
  "conceited",
  "proudOf",
  "selfCare",
];

const NEGATIVE_WORDS = [
  "痛苦",
  "崩潰",
  "焦慮",
  "害怕",
  "低落",
  "沮喪",
  "疲憊",
  "絕望",
  "無助",
];

const POSITIVE_WORDS = [
  "感謝",
  "開心",
  "平靜",
  "放鬆",
  "完成",
  "進步",
  "溫暖",
  "期待",
  "希望",
];

function detectCrisis(text) {
  const source = String(text || "");
  return CRISIS_KEYWORDS.some((keyword) => source.includes(keyword));
}

function stripMarkdownFence(text) {
  const source = String(text || "").trim();
  if (!source.startsWith("```")) {
    return source;
  }

  return source
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();
}

function toNumber(value, fallback = null) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function toCleanString(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim();
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function normalizeMoodScore(value, moodScale, fallback = null) {
  const score = toNumber(value, fallback);
  if (score == null) return null;
  const scale = moodScale === 5 ? 5 : 10;
  return clamp(Number(score), 1, scale);
}

function normalizeDiaryFields(rawDiaryFields) {
  const raw =
    rawDiaryFields && typeof rawDiaryFields === "object" && !Array.isArray(rawDiaryFields)
      ? rawDiaryFields
      : {};

  const result = {};
  for (const key of DIARY_FIELD_KEYS) {
    result[key] = String(raw[key] || "").trim().slice(0, 1200);
  }

  // 也帶上三個分數欄位，方便模型補充判讀
  result.overallMood = toNumber(raw.overallMood, null);
  result.overallHealth = toNumber(raw.overallHealth, null);

  return result;
}

function buildDiaryTextFromFields(fields) {
  const sections = [
    ["標題", fields.title],
    ["內容", fields.content],
    ["今日主題曲", fields.themeSong],
    ["最想記錄的瞬間", fields.highlight],
    ["今天情緒像", fields.metaphor],
    ["為自己感到驕傲", fields.conceited],
    ["做得不錯的地方", fields.proudOf],
    ["可多照顧自己的地方", fields.selfCare],
    ["今日感恩事項", fields.gratitude],
  ]
    .filter(([, value]) => Boolean(value))
    .map(([label, value]) => `${label}: ${value}`);

  return sections.join("\n");
}

function countHits(source, words) {
  return words.reduce((acc, w) => acc + (source.includes(w) ? 1 : 0), 0);
}

function extractEmotionEntries(dailyRecord) {
  const raw = dailyRecord?.emotions;
  const entries = [];

  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (!item || typeof item !== "object") continue;
      const name = String(item.name || "").trim();
      const value = toNumber(item.value, null);
      if (!name || value == null) continue;
      entries.push({ name, score: clamp(Number(value), 0, 10) });
    }
  } else if (raw && typeof raw === "object") {
    for (const [name, value] of Object.entries(raw)) {
      const score = toNumber(value, null);
      if (!name || score == null) continue;
      entries.push({ name: String(name).trim(), score: clamp(Number(score), 0, 10) });
    }
  }

  return entries;
}

function pickEmotionScore(entries, keywords) {
  const found = entries.find((e) => keywords.some((k) => e.name.includes(k)));
  return found ? found.score : null;
}

function collectMedicationNames(source, bucket) {
  if (!source) return;

  if (typeof source === "string") {
    const s = toCleanString(source);
    if (s) bucket.add(s);
    return;
  }

  if (Array.isArray(source)) {
    source.forEach((item) => collectMedicationNames(item, bucket));
    return;
  }

  if (typeof source === "object") {
    const name =
      toCleanString(source.name) ||
      toCleanString(source.label) ||
      toCleanString(source.title) ||
      toCleanString(source.medicationName) ||
      toCleanString(source.drugName);

    if (name) {
      bucket.add(name);
      return;
    }

    Object.values(source).forEach((value) => collectMedicationNames(value, bucket));
  }
}

function extractMedicationInfo(dailyRecord) {
  const names = new Set();

  collectMedicationNames(dailyRecord.medication, names);
  collectMedicationNames(dailyRecord.medications, names);
  collectMedicationNames(dailyRecord.medicines, names);

  const sleep =
    dailyRecord.sleep && typeof dailyRecord.sleep === "object" ? dailyRecord.sleep : {};
  const hypnoticName = toCleanString(sleep.hypnoticName || dailyRecord.hypnoticName);
  const hypnoticDose = toCleanString(sleep.hypnoticDose || dailyRecord.hypnoticDose);
  const tookHypnotic = sleep.tookHypnotic === true || dailyRecord.tookHypnotic === true;

  if (hypnoticName) {
    names.add(hypnoticDose ? `安眠藥:${hypnoticName}(${hypnoticDose})` : `安眠藥:${hypnoticName}`);
  } else if (tookHypnotic) {
    names.add("安眠藥");
  }

  const medicationNames = Array.from(names);
  const hasMedicationData =
    medicationNames.length > 0 ||
    Boolean(dailyRecord.medication) ||
    Boolean(dailyRecord.medications) ||
    Boolean(dailyRecord.medicines);

  return {
    hasMedicationData,
    medicationNames,
    medicationCount: medicationNames.length,
    tookHypnotic,
  };
}

function buildEmotionModel(dailyRecord, diaryFields, diaryText) {
  const emotionEntries = extractEmotionEntries(dailyRecord);
  const medication = extractMedicationInfo(dailyRecord);
  const moodScale = toNumber(
    dailyRecord.moodScale ?? diaryFields.moodScale ?? dailyRecord.diaryMoodScale,
    10,
  );
  const useFivePointScale = moodScale === 5;
  const mood = normalizeMoodScore(
    dailyRecord.overallMood ?? diaryFields.overallMood ?? dailyRecord.mood,
    moodScale,
    useFivePointScale ? 3 : 5,
  );
  const health = normalizeMoodScore(
    dailyRecord.overallHealth ?? diaryFields.overallHealth ?? dailyRecord.health,
    moodScale,
    useFivePointScale ? 3 : 5,
  );
  const anxiety = toNumber(dailyRecord.anxiety, null) ?? pickEmotionScore(emotionEntries, ["焦慮", "緊張", "擔心"]);
  const energy = toNumber(dailyRecord.energy, null) ?? pickEmotionScore(emotionEntries, ["能量", "活力", "精力"]);

  const text = String(diaryText || "");
  const negativeHits = countHits(text, NEGATIVE_WORDS);
  const positiveHits = countHits(text, POSITIVE_WORDS);
  const symptomsCount = Array.isArray(dailyRecord.symptoms) ? dailyRecord.symptoms.length : 0;

  let compositeScore = mood * 0.55 + health * 0.25;
  if (energy != null) {
    compositeScore += energy * 0.2;
  }
  if (anxiety != null) {
    // 焦慮越高，綜合情緒分數略微下修
    compositeScore -= (anxiety - 5) * 0.22;
  }

  const emotionAvg =
    emotionEntries.length > 0
      ? emotionEntries.reduce((acc, e) => acc + e.score, 0) / emotionEntries.length
      : null;

  if (emotionAvg != null) {
    compositeScore = compositeScore * 0.75 + emotionAvg * 0.25;
  }

  compositeScore += (positiveHits - negativeHits) * 0.2;
  compositeScore -= symptomsCount * 0.08;
  compositeScore = clamp(Number(compositeScore.toFixed(2)), 1, moodScale === 5 ? 5 : 10);

  let moodBand = "平穩";
  if (compositeScore >= 4.2) moodBand = "積極穩定";
  else if (compositeScore < 2.8) moodBand = "低潮偏高";

  let anxietyRisk = "未知";
  if (anxiety != null) {
    if (anxiety >= 7) anxietyRisk = "高";
    else if (anxiety >= 5) anxietyRisk = "中";
    else anxietyRisk = "低";
  }

  const topHighEmotions = [...emotionEntries]
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);
  const topLowEmotions = [...emotionEntries]
    .sort((a, b) => a.score - b.score)
    .slice(0, 2);

  return {
    compositeScore,
    moodBand,
    emotionEntries,
    topHighEmotions,
    topLowEmotions,
    drivers: {
      mood,
      health,
      anxiety,
      energy,
      emotionAvg,
      symptomsCount,
      positiveHits,
      negativeHits,
      medicationCount: medication.medicationCount,
      tookHypnotic: medication.tookHypnotic,
    },
    risks: {
      anxietyRisk,
      symptomBurden: symptomsCount >= 5 ? "高" : symptomsCount >= 3 ? "中" : "低",
    },
    medication,
  };
}

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

exports.createCommunityPost = onCall(async (request) => {
  // 1. 安全檢查：確認用戶是否已登入
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "必須登入才能發文喔！");
  }

  const uid = request.auth.uid;
  
  // 從 App 端接收發文內容（注意：App 這裡絕對不要傳送 anonymousName）
  const { title, content } = request.data; 

  if (!title || !content) {
    throw new HttpsError("invalid-argument", "標題和內容不能為空。");
  }

  try {
    // 2. 由後端親自去查這個使用者的「匿名」是什麼
    const userDoc = await db.collection("users").doc(uid).get();
    
    if (!userDoc.exists || !userDoc.data().anonymousName) {
      throw new HttpsError("not-found", "找不到用戶資料或尚未設定匿名。");
    }

    const correctAnonymousName = userDoc.data().anonymousName;

    // 3. 將文章與「絕對正確的匿名」寫入社群看板
    const newPostRef = db.collection("community_rooms").doc(); // 自動產生一個隨機 ID
    
    await newPostRef.set({
      title: title,
      content: content,
      creatorUid: uid,                    // 紀錄真實 UID (用於後續判定誰能刪除)
      authorName: correctAnonymousName,   // 系統查到的匿名 (公開顯示用)
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // 4. 回傳成功訊息與新文章的 ID 給 App
    return { 
      success: true, 
      roomId: newPostRef.id,
      message: "發文成功！" 
    };

  } catch (error) {
    console.error("發文發生錯誤:", error);
    throw new HttpsError("internal", "伺服器發生錯誤，請稍後再試。");
  }
});

exports.generateAiJournalReflection = onCall(
  { secrets: [openAiApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再使用此功能");
    }

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

    const crisisDetected = detectCrisis(trimmedDiary);
    const emotionModel = buildEmotionModel(safeDailyRecord, safeDiaryFields, trimmedDiary);

    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("internal", "缺少 OPENAI_API_KEY 設定");
      }
      const client = new OpenAI({ apiKey });
      const completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.7,
        response_format: { type: "json_object" },
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

      return normalized;
    } catch (error) {
      console.error("generateAiJournalReflection failed:", error);
      throw new HttpsError("internal", "AI 生成失敗，請稍後再試");
    }
  },
);

function normalizeInneraRecordDraft(rawDraft, existingDraft) {
  const raw = rawDraft && typeof rawDraft === "object" ? rawDraft : {};
  const existing = existingDraft && typeof existingDraft === "object" ? existingDraft : {};
  const safeText = (value, max = 1200) => String(value || "").trim().slice(0, max);
  const validTime = (value) => {
    const text = safeText(value, 5);
    return /^([01]?\d|2[0-3]):[0-5]\d$/.test(text) ? text.padStart(5, "0") : null;
  };
  const validScore = (value) => {
    const score = Number(value);
    return Number.isInteger(score) && score >= 1 && score <= 5 ? score : null;
  };
  const mergeNames = (first, second, max) =>
    [...new Set([...(Array.isArray(first) ? first : []), ...(Array.isArray(second) ? second : [])]
      .map((item) => safeText(item, 100))
      .filter(Boolean))].slice(0, max);
  const emotionMap = new Map();
  for (const item of Array.isArray(existing.emotions) ? existing.emotions : []) {
    const name = safeText(item && item.name, 60);
    const score = validScore(item && item.score);
    if (name && score) emotionMap.set(name, { name, score, source: item.source || "existingRecord" });
  }
  for (const item of Array.isArray(raw.emotions) ? raw.emotions : []) {
    const name = safeText(item && item.name, 60);
    const score = validScore(item && item.score);
    const source =
      item?.source === "defaultPendingConfirmation"
        ? "defaultPendingConfirmation"
        : "explicitUserInput";
    if (name && score) emotionMap.set(name, { name, score, source });
  }
  const oldSleep = existing.sleep && typeof existing.sleep === "object" ? existing.sleep : {};
  const nextSleep = raw.sleep && typeof raw.sleep === "object" ? raw.sleep : {};
  const sleep = {
    sleepTime: validTime(nextSleep.sleepTime) || validTime(oldSleep.sleepTime),
    wakeTime: validTime(nextSleep.wakeTime) || validTime(oldSleep.wakeTime),
    finalWakeTime: validTime(nextSleep.finalWakeTime) || validTime(oldSleep.finalWakeTime),
    quality: validScore(nextSleep.quality) || validScore(oldSleep.quality),
    midWakeList: safeText(nextSleep.midWakeList, 300) || safeText(oldSleep.midWakeList, 300),
    flags: mergeNames(oldSleep.flags, nextSleep.flags, 12),
    naps: Array.isArray(nextSleep.naps) ? nextSleep.naps.slice(0, 6) : (Array.isArray(oldSleep.naps) ? oldSleep.naps.slice(0, 6) : []),
  };
  const overallMood = validScore(raw.overallMood) || validScore(existing.overallMood);
  return {
    date: safeText(raw.date || existing.date, 10),
    moodScale: 5,
    overallMood: overallMood,
    emotions: [...emotionMap.values()].slice(0, 20),
    symptoms: mergeNames(existing.symptoms, raw.symptoms, 30),
    sleep,
    events: mergeNames(existing.events, raw.events, 12),
    diaryText: safeText(raw.diaryText, 8000) || safeText(existing.diaryText, 8000),
    missingFields: mergeNames([], raw.missingFields, 8),
  };
}

exports.generateInneraAiChat = onCall(
  { secrets: [openAiApiKey] },
  async (request) => {
    console.log("generateInneraAiChat invoked", {
      mode: request.data?.mode,
      authenticated: Boolean(request.auth),
    });
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再使用心域 AI");
    }

    const data = request.data || {};
    const mode = String(data.mode || "emotionalSupport").trim();
    const message = String(data.message || "").trim().slice(0, 2000);
    const context =
      data.context && typeof data.context === "object" ? { ...data.context } : {};
    const history = Array.isArray(data.messages) ? data.messages : [];
    const existingRecordDraft =
      data.recordDraft && typeof data.recordDraft === "object" ? data.recordDraft : {};
    const contextSources = Array.isArray(data.contextSources)
      ? data.contextSources
          .map((item) => ({
            label: String((item && item.label) || "").trim().slice(0, 120),
            dateRange: String((item && item.dateRange) || "").trim().slice(0, 120),
            count: Math.max(0, Math.min(1000, Number((item && item.count) || 0) || 0)),
          }))
          .filter((item) => item.label)
      : [];
    const allowedModes = new Set([
      "dailyRecord",
      "emotionalSupport",
      "physicalHealth",
      "recentReview",
    ]);

    if (!allowedModes.has(mode)) {
      throw new HttpsError("invalid-argument", "Unsupported AI mode");
    }
    if (mode === "dailyRecord") {
      // Older app versions may still send this field. Daily-record AI uses only today.
      delete context.yesterdaySleep;
    }
    if (!message) {
      throw new HttpsError("invalid-argument", "請輸入想和心域 AI 說的內容");
    }

    const imminentPhrases = [
      "割腕",
      "跳樓",
      "吞藥",
      "已經準備好工具",
      "等一下就要做",
      "正在傷害自己",
      "想殺人",
      "想傷害別人",
    ];
    const medicalUrgencyPhrases = [
      "吐血",
      "黑便",
      "呼吸困難",
      "胸痛",
      "昏倒",
      "嚴重過敏",
      "意識不清",
      "持續大量出血",
    ];
    const hasImminentDanger = imminentPhrases.some((phrase) => message.includes(phrase));
    const hasMedicalUrgency = medicalUrgencyPhrases.some((phrase) => message.includes(phrase));
    if (hasImminentDanger || hasMedicalUrgency) {
      return {
        reply: "",
        followUpQuestion: null,
        sources: [],
        suggestedActions: [],
        recordDraft: null,
        safetyLevel: hasMedicalUrgency ? "medicalUrgency" : "imminentDanger",
        requiresFixedSafetyUi: true,
        model: null,
      };
    }

    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("internal", "缺少 OPENAI_API_KEY 設定");
      }

      const safeHistory = history
        .map((item) => {
          const role = item && item.role === "user" ? "user" : "assistant";
          const content = String((item && item.content) || "").trim().slice(0, 1600);
          if (!content) return null;
          return { role, content };
        })
        .filter(Boolean)
        .slice(-12);

      const client = new OpenAI({ apiKey });
      const completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.55,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: [
              "You are Innera AI, a mental-health record and reflection assistant.",
              "Reply in Traditional Chinese with a gentle, respectful, non-judgmental tone.",
              "You are not a doctor, therapist, or emergency service.",
              "Do not diagnose, claim causation, recommend medication changes, or invent records.",
              "Do not minimize self-harm, violence, or medical emergency risk.",
              "Return only JSON with reply, followUpQuestion, sources, suggestedActions, recordDraft, safetyLevel, requiresFixedSafetyUi.",
              "sources must only reuse the supplied contextSources without private text.",
              "requiresFixedSafetyUi must be false unless an urgent risk needs emergency help.",
              mode === "dailyRecord"
                ? "You are completing today's structured record. Every response must include recordDraft. All new mood scores use a 1 to 5 scale only: 1 lowest and 5 highest. Never ask for, output, or store a 10-point scale. Extract every emotion the user explicitly names into recordDraft.emotions. When the user names an emotion but gives no strength, include it with score 3 and source defaultPendingConfirmation, add its strength to missingFields, and clearly say it is a temporary 3/5 value the user can adjust before confirming. Extract symptoms, sleep, events, and diary text. Use only sleep values supplied for today's date; if today's sleep is absent, say it has not been recorded. Do not infer or refer to yesterday's sleep. Ask only one or two missing details already absent from recordDraft. If the user gives 8 or another score above 5, ask them to restate it on 1 to 5 and do not store that score."
                : mode === "physicalHealth"
                  ? "Separate observations, missing information, what to keep recording, and when to seek care. Do not diagnose."
                  : mode === "recentReview"
                    ? "Separate record facts, possible relationships, and directions to notice. Missing data does not mean an event did not occur."
                    : "Respond to emotions first. Ask at most one open question and encourage real-world support when appropriate.",
            ].join("\n"),
          },
          {
            role: "user",
            content: JSON.stringify({
              mode,
              context,
              contextSources,
              recordDraft: existingRecordDraft,
            }),
          },
          ...safeHistory,
          {
            role: "user",
            content: message,
          },
        ],
      });

      const rawText = String(completion.choices?.[0]?.message?.content || "").trim();
      if (!rawText) {
        throw new Error("Empty OpenAI response");
      }
      const parsed = JSON.parse(stripMarkdownFence(rawText));
      const reply = String(parsed.reply || "").trim().slice(0, 6000);
      if (!reply) {
        throw new Error("Missing AI reply");
      }

      return {
        reply,
        followUpQuestion: String(parsed.followUpQuestion || "").trim().slice(0, 600),
        sources: contextSources,
        suggestedActions: Array.isArray(parsed.suggestedActions)
          ? parsed.suggestedActions.map((item) => String(item).trim()).filter(Boolean).slice(0, 4)
          : [],
        recordDraft:
          mode === "dailyRecord"
            ? normalizeInneraRecordDraft(parsed.recordDraft, existingRecordDraft)
            : null,
        safetyLevel: "normal",
        requiresFixedSafetyUi: false,
        model: DEFAULT_AI_MODEL,
      };
    } catch (error) {
      console.error("generateInneraAiChat failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
        code: error?.code,
        type: error?.type,
        requestId: error?.request_id,
        model: DEFAULT_AI_MODEL,
      });

      if (error?.status === 401) {
        throw new HttpsError(
          "failed-precondition",
          "AI 服務驗證失敗，請檢查伺服器設定。",
        );
      }

      if (error?.status === 404) {
        throw new HttpsError(
          "failed-precondition",
          `目前設定的 AI 模型無法使用：${DEFAULT_AI_MODEL}`,
        );
      }

      if (error?.status === 429) {
        throw new HttpsError(
          "resource-exhausted",
          "AI 服務目前已達使用限制，請稍後再試。",
        );
      }

      throw new HttpsError(
        "internal",
        "AI 服務暫時無法回覆，請稍後再試。",
      );
    }
  },
);
