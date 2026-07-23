const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");
const crypto = require("crypto");

// 初始化 Admin SDK (擁有繞過 Security Rules 的最高權限)
admin.initializeApp();
const db = admin.firestore();
const openAiApiKey = defineSecret("OPENAI_API_KEY");
const lastFmApiKey = defineSecret("LASTFM_API_KEY");
const spotifyClientId = defineSecret("SPOTIFY_CLIENT_ID");
const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");
const DEFAULT_AI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";
const INNERA_AI_PROMPT_VERSION = "innera-ai-chat-v1";
const DIARY_EXTRACTION_PROMPT_VERSION = "diary_extraction_v1";

const diarySuggestionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["value", "source", "confidence", "evidence", "reason"],
  properties: {
    value: { type: "string" },
    source: {
      type: "string",
      enum: ["explicit", "summarized", "inferred", "suggested", "missing"],
    },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    evidence: { type: "string" },
    reason: { type: "string" },
  },
};

const diaryExtractionSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "titleSuggestions",
    "content",
    "memorableMomentSuggestions",
    "didWellSuggestions",
    "selfCareSuggestions",
    "gratitudeSuggestions",
    "emotionAnalysis",
    "emotionMetaphorSuggestions",
    "songRecommendationProfile",
    "missingFields",
    "followUpQuestions",
    "safetyRisk",
  ],
  properties: {
    titleSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    content: diarySuggestionSchema,
    memorableMomentSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    didWellSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    selfCareSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    gratitudeSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    emotionAnalysis: {
      type: "object",
      additionalProperties: false,
      required: [
        "primaryEmotion",
        "secondaryEmotions",
        "valence",
        "energy",
        "intensity",
      ],
      properties: {
        primaryEmotion: { type: "string" },
        secondaryEmotions: {
          type: "array",
          maxItems: 5,
          items: { type: "string" },
        },
        valence: { type: "integer", minimum: 1, maximum: 5 },
        energy: { type: "integer", minimum: 1, maximum: 5 },
        intensity: { type: "integer", minimum: 1, maximum: 5 },
      },
    },
    emotionMetaphorSuggestions: {
      type: "array",
      maxItems: 3,
      items: diarySuggestionSchema,
    },
    songRecommendationProfile: {
      type: "object",
      additionalProperties: false,
      required: [
        "primaryEmotion",
        "secondaryEmotions",
        "desiredEffect",
        "musicTags",
        "searchKeywords",
        "preferredLanguages",
        "energy",
        "valence",
        "avoidThemes",
      ],
      properties: {
        primaryEmotion: { type: "string" },
        secondaryEmotions: {
          type: "array",
          maxItems: 5,
          items: { type: "string" },
        },
        desiredEffect: { type: "string" },
        musicTags: {
          type: "array",
          maxItems: 5,
          items: {
            type: "string",
            enum: [
              "calm",
              "comforting",
              "healing",
              "hopeful",
              "peaceful",
              "uplifting",
              "gentle",
              "reflective",
              "melancholic",
              "energetic",
              "motivational",
            ],
          },
        },
        searchKeywords: {
          type: "array",
          maxItems: 6,
          items: { type: "string" },
        },
        preferredLanguages: {
          type: "array",
          maxItems: 4,
          items: { type: "string" },
        },
        energy: { type: "integer", minimum: 1, maximum: 5 },
        valence: { type: "integer", minimum: 1, maximum: 5 },
        avoidThemes: {
          type: "array",
          maxItems: 10,
          items: { type: "string" },
        },
      },
    },
    missingFields: {
      type: "array",
      maxItems: 8,
      items: { type: "string" },
    },
    followUpQuestions: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["targetField", "question"],
        properties: {
          targetField: { type: "string" },
          question: { type: "string" },
        },
      },
    },
    safetyRisk: {
      type: "object",
      additionalProperties: false,
      required: ["detected", "level", "reason"],
      properties: {
        detected: { type: "boolean" },
        level: {
          type: "string",
          enum: ["none", "low", "medium", "high", "imminent"],
        },
        reason: { type: "string" },
      },
    },
  },
};

const ALLOWED_MUSIC_TAGS = new Set([
  "calm",
  "comforting",
  "healing",
  "hopeful",
  "peaceful",
  "uplifting",
  "gentle",
  "reflective",
  "melancholic",
  "energetic",
  "motivational",
]);
const UNWANTED_VERSION = /\b(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)\b/i;

function normalizeTrackText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFKC")
    .replace(/\b(feat|ft)\.?\s+.*$/i, "")
    .replace(/\([^)]*(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)[^)]*\)/gi, "")
    .replace(/\[[^\]]*(live|karaoke|instrumental|cover|remix|remaster(?:ed)?)[^\]]*\]/gi, "")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

function sameTrack(left, right) {
  const leftTitle = normalizeTrackText(left.title);
  const rightTitle = normalizeTrackText(right.title);
  const leftArtist = normalizeTrackText(left.artist);
  const rightArtist = normalizeTrackText(right.artist);
  return Boolean(
    leftTitle &&
      rightTitle &&
      leftArtist &&
      rightArtist &&
      leftTitle === rightTitle &&
      (leftArtist === rightArtist ||
        leftArtist.includes(rightArtist) ||
        rightArtist.includes(leftArtist)),
  );
}

async function fetchJson(url, options = {}, timeoutMs = 12000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    if (response.status === 429) {
      const error = new Error("rate_limit");
      error.status = 429;
      throw error;
    }
    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function getSpotifyToken(clientId, clientSecret) {
  const encoded = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const payload = await fetchJson(
    "https://accounts.spotify.com/api/token",
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${encoded}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    },
    12000,
  );
  if (!payload.access_token) throw new Error("Missing Spotify access token");
  return payload.access_token;
}

function spotifyTrack(item, tags = [], discoverySources = 1) {
  return {
    provider: "spotify",
    providerTrackId: String(item?.id || ""),
    title: String(item?.name || "").trim(),
    artist: (item?.artists || [])
      .map((artist) => String(artist?.name || "").trim())
      .filter(Boolean)
      .join(", "),
    album: String(item?.album?.name || "").trim(),
    artworkUrl: String(item?.album?.images?.[0]?.url || "").trim(),
    externalUrl: String(item?.external_urls?.spotify || "").trim(),
    previewUrl: String(item?.preview_url || "").trim(),
    isExplicit: item?.explicit === true,
    isPlayable: item?.is_playable !== false,
    isrc: String(item?.external_ids?.isrc || "").trim(),
    durationMs: Number(item?.duration_ms || 0) || null,
    availableMarkets: Array.isArray(item?.available_markets)
      ? item.available_markets.slice(0, 250)
      : [],
    sourceTags: tags,
    discoverySources,
  };
}

async function spotifySearch(token, query, market = "TW", limit = 5) {
  const params = new URLSearchParams({
    q: query,
    type: "track",
    market,
    limit: String(limit),
  });
  const payload = await fetchJson(
    `https://api.spotify.com/v1/search?${params}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  return Array.isArray(payload?.tracks?.items) ? payload.tracks.items : [];
}

function musicCacheKey(profile, market) {
  const stable = JSON.stringify({
    tags: profile.musicTags,
    keywords: profile.searchKeywords,
    languages: profile.preferredLanguages,
    market,
    energy: profile.energy,
    valence: profile.valence,
    provider: "spotify",
  });
  return crypto.createHash("sha256").update(stable).digest("hex");
}

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
  "gratitude",
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

exports.generateInneraDiaryDraft = onCall(
  { secrets: [openAiApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再整理今日紀錄");
    }
    const data = request.data || {};
    const recordDate = String(data.recordDate || "").trim().slice(0, 10);
    const requestedField = String(data.requestedField || "").trim().slice(0, 40);
    const currentDraft =
      data.currentDraft && typeof data.currentDraft === "object"
        ? data.currentDraft
        : null;
    const messages = (Array.isArray(data.messages) ? data.messages : [])
      .map((item) => {
        const role = item?.role === "user" ? "user" : "assistant";
        const content = String(item?.content || "").trim().slice(0, 2000);
        return content ? { role, content } : null;
      })
      .filter(Boolean)
      .slice(-24);
    if (!messages.some((item) => item.role === "user")) {
      throw new HttpsError("invalid-argument", "沒有可整理的使用者對話");
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(recordDate)) {
      throw new HttpsError("invalid-argument", "紀錄日期格式錯誤");
    }

    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("failed-precondition", "缺少 OPENAI_API_KEY 設定");
      }
      const client = new OpenAI({ apiKey });
      const completion = await client.chat.completions.create({
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
              "只根據提供的對話。不得虛構事件、感恩事項、成就、人物或情緒。",
              "source 必須是 explicit、summarized、inferred、suggested、missing 之一。",
              "資訊不足時使用空字串、空陣列並列入 missingFields，不得為填滿欄位而猜測。",
              "content 使用第一人稱，保留原意，約 80 至 300 個中文字；對話很短時可以更短。",
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
      return {
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
    } catch (error) {
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

exports.recommendInneraSongs = onCall(
  {
    secrets: [
      openAiApiKey,
      lastFmApiKey,
      spotifyClientId,
      spotifyClientSecret,
    ],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再取得歌曲推薦");
    }
    const raw = request.data?.profile;
    const profile = raw && typeof raw === "object" ? raw : {};
    const musicTags = (Array.isArray(profile.musicTags) ? profile.musicTags : [])
      .map((item) => String(item || "").trim().toLowerCase())
      .filter((item) => ALLOWED_MUSIC_TAGS.has(item))
      .slice(0, 4);
    const searchKeywords = (
      Array.isArray(profile.searchKeywords) ? profile.searchKeywords : []
    )
      .map((item) => String(item || "").trim().slice(0, 80))
      .filter(Boolean)
      .slice(0, 6);
    const preferredLanguages = (
      Array.isArray(profile.preferredLanguages)
        ? profile.preferredLanguages
        : []
    )
      .map((item) => String(item || "").trim().slice(0, 16))
      .filter(Boolean)
      .slice(0, 4);
    const avoidThemes = (
      Array.isArray(profile.avoidThemes) ? profile.avoidThemes : []
    )
      .map((item) => String(item || "").trim().toLowerCase())
      .filter(Boolean)
      .slice(0, 12);
    const market = String(request.data?.market || "TW")
      .trim()
      .toUpperCase()
      .slice(0, 2);
    if (musicTags.length === 0 && searchKeywords.length === 0) {
      return { recommendations: [], error: "missing_search_profile" };
    }

    const cacheProfile = {
      musicTags,
      searchKeywords,
      preferredLanguages,
      energy: Number(profile.energy || 3),
      valence: Number(profile.valence || 3),
    };
    const cacheKey = musicCacheKey(cacheProfile, market);
    const cacheRef = db.collection("musicRecommendationCache").doc(cacheKey);
    const cached = await cacheRef.get();
    const cachedData = cached.data();
    if (
      cachedData?.expiresAt?.toMillis &&
      cachedData.expiresAt.toMillis() > Date.now() &&
      Array.isArray(cachedData.recommendations)
    ) {
      return {
        recommendations: cachedData.recommendations,
        cached: true,
      };
    }

    const lastFmKey = lastFmApiKey.value();
    const spotifyId = spotifyClientId.value();
    const spotifySecret = spotifyClientSecret.value();
    if (!lastFmKey || !spotifyId || !spotifySecret) {
      return { recommendations: [], error: "music_service_not_configured" };
    }

    try {
      const spotifyToken = await getSpotifyToken(spotifyId, spotifySecret);
      const discovered = [];
      const lastFmResults = await Promise.allSettled(
        musicTags.map(async (tag) => {
          const params = new URLSearchParams({
            method: "tag.gettoptracks",
            tag,
            api_key: lastFmKey,
            format: "json",
            limit: "15",
          });
          const payload = await fetchJson(
            `https://ws.audioscrobbler.com/2.0/?${params}`,
          );
          return (payload?.tracks?.track || []).map((track) => ({
            title: String(track?.name || "").trim(),
            artist: String(track?.artist?.name || "").trim(),
            sourceTags: [tag],
            musicBrainzId: String(track?.mbid || "").trim(),
          }));
        }),
      );
      for (const result of lastFmResults) {
        if (result.status !== "fulfilled") continue;
        for (const track of result.value) {
          if (!track.title || !track.artist || UNWANTED_VERSION.test(track.title)) {
            continue;
          }
          const existing = discovered.find((item) => sameTrack(item, track));
          if (existing) {
            existing.sourceTags = [
              ...new Set([...existing.sourceTags, ...track.sourceTags]),
            ];
            existing.discoverySources += 1;
          } else {
            discovered.push({ ...track, discoverySources: 1 });
          }
        }
      }

      const verified = [];
      for (const candidate of discovered.slice(0, 20)) {
        const results = await spotifySearch(
          spotifyToken,
          `track:${candidate.title} artist:${candidate.artist}`,
          market,
          5,
        );
        const matched = results.find((item) =>
          sameTrack(candidate, {
            title: item?.name,
            artist: item?.artists?.[0]?.name,
          }),
        );
        if (!matched || UNWANTED_VERSION.test(matched.name || "")) continue;
        verified.push(
          spotifyTrack(
            matched,
            candidate.sourceTags,
            candidate.discoverySources,
          ),
        );
      }

      if (
        verified.length < 5 ||
        (preferredLanguages.some((item) => item.startsWith("zh")) &&
          !verified.some((item) =>
            /[\u3400-\u9fff]/u.test(`${item.title}${item.artist}`),
          ))
      ) {
        const fallbackQueries = [
          ...searchKeywords,
          ...(preferredLanguages.some((item) => item.startsWith("zh"))
            ? ["華語療癒", "Mandarin comforting", "Mandarin healing"]
            : []),
        ].slice(0, 8);
        for (const keyword of fallbackQueries) {
          const results = await spotifySearch(
            spotifyToken,
            keyword,
            market,
            3,
          );
          for (const item of results) {
            if (UNWANTED_VERSION.test(item?.name || "")) continue;
            const track = spotifyTrack(item, [], 1);
            if (!verified.some((existing) => sameTrack(existing, track))) {
              verified.push(track);
            }
          }
        }
      }

      const ranked = verified
        .filter((track) => {
          const text = `${track.title} ${track.artist}`.toLowerCase();
          return (
            track.providerTrackId &&
            track.externalUrl &&
            track.isPlayable &&
            !avoidThemes.some((theme) => theme && text.includes(theme))
          );
        })
        .map((track) => {
          const languageMatch =
            preferredLanguages.some((item) => item.startsWith("zh")) &&
            /[\u3400-\u9fff]/u.test(`${track.title}${track.artist}`);
          const score =
            track.sourceTags.length * 4 +
            Math.max(0, track.discoverySources - 1) * 2 +
            (languageMatch ? 3 : 0) +
            (track.externalUrl ? 1 : 0) +
            (track.artworkUrl ? 1 : 0) -
            (track.isExplicit ? 5 : 0);
          return { ...track, rankingScore: score };
        })
        .sort((a, b) => b.rankingScore - a.rankingScore)
        .slice(0, 10);

      if (ranked.length === 0) {
        return { recommendations: [], error: "no_verified_tracks" };
      }
      const candidates = ranked.map((track, index) => ({
        candidateId: `candidate_${String(index + 1).padStart(2, "0")}`,
        title: track.title,
        artist: track.artist,
        tags: track.sourceTags,
        provider: track.provider,
      }));
      let selected = [];
      try {
        const ai = new OpenAI({ apiKey: openAiApiKey.value() });
        const selection = await ai.chat.completions.create({
          model: DEFAULT_AI_MODEL,
          temperature: 0.2,
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "innera_song_selection",
              strict: true,
              schema: {
                type: "object",
                additionalProperties: false,
                required: ["recommendations"],
                properties: {
                  recommendations: {
                    type: "array",
                    maxItems: 3,
                    items: {
                      type: "object",
                      additionalProperties: false,
                      required: ["candidateId", "reason"],
                      properties: {
                        candidateId: { type: "string" },
                        reason: { type: "string" },
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
                "只能從 candidates 選最多三首，以 candidateId 回覆。",
                "不得新增或修改歌名、歌手、平台 ID 或連結。",
                "不要聲稱知道未提供的歌詞；理由只能描述推薦情境與整體陪伴方向。",
                "使用繁體中文，每個理由一至兩句。",
              ].join("\n"),
            },
            {
              role: "user",
              content: JSON.stringify({
                profile: {
                  primaryEmotion: String(profile.primaryEmotion || ""),
                  desiredEffect: String(profile.desiredEffect || ""),
                  preferredLanguages,
                },
                candidates,
              }),
            },
          ],
        });
        const parsed = JSON.parse(
          stripMarkdownFence(selection.choices?.[0]?.message?.content || ""),
        );
        selected = (Array.isArray(parsed.recommendations)
          ? parsed.recommendations
          : []
        ).filter((item) =>
          candidates.some(
            (candidate) => candidate.candidateId === item.candidateId,
          ),
        );
      } catch (error) {
        console.warn("Song AI selection failed; using ranked verified tracks", {
          message: error?.message,
        });
      }
      if (selected.length === 0) {
        selected = candidates.slice(0, 3).map((candidate) => ({
          candidateId: candidate.candidateId,
          reason: "這首已由音樂平台驗證，整體標籤較接近今天想被陪伴的方向。",
        }));
      }
      const recommendations = selected
        .map((choice) => {
          const index = candidates.findIndex(
            (candidate) => candidate.candidateId === choice.candidateId,
          );
          if (index < 0) return null;
          return {
            ...ranked[index],
            candidateId: choice.candidateId,
            reason: String(choice.reason || "").trim().slice(0, 300),
          };
        })
        .filter(Boolean)
        .slice(0, 3);
      await cacheRef.set({
        recommendations,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 12 * 60 * 60 * 1000,
        ),
      });
      return { recommendations, cached: false };
    } catch (error) {
      console.error("recommendInneraSongs failed", {
        message: error?.message,
        status: error?.status,
      });
      return {
        recommendations: [],
        error: error?.status === 429 ? "rate_limit" : "music_service_failed",
      };
    }
  },
);

exports.searchInneraSongs = onCall(
  { secrets: [spotifyClientId, spotifyClientSecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再搜尋歌曲");
    }
    const query = String(request.data?.query || "").trim().slice(0, 120);
    const market = String(request.data?.market || "TW")
      .trim()
      .toUpperCase()
      .slice(0, 2);
    if (!query) {
      throw new HttpsError("invalid-argument", "請輸入歌名、歌手或關鍵字");
    }
    const clientId = spotifyClientId.value();
    const clientSecret = spotifyClientSecret.value();
    if (!clientId || !clientSecret) {
      return { tracks: [], error: "music_service_not_configured" };
    }
    try {
      const token = await getSpotifyToken(clientId, clientSecret);
      const results = await spotifySearch(token, query, market, 10);
      const seen = new Set();
      const tracks = results
        .filter((item) => !UNWANTED_VERSION.test(item?.name || ""))
        .map((item, index) => ({
          ...spotifyTrack(item),
          candidateId: `search_${String(index + 1).padStart(2, "0")}`,
          reason: "你自行搜尋並選擇的 Spotify 目錄結果。",
        }))
        .filter((item) => {
          if (!item.providerTrackId || seen.has(item.providerTrackId)) {
            return false;
          }
          seen.add(item.providerTrackId);
          return true;
        });
      return { tracks };
    } catch (error) {
      console.error("searchInneraSongs failed", {
        message: error?.message,
        status: error?.status,
      });
      return {
        tracks: [],
        error: error?.status === 429 ? "rate_limit" : "music_service_failed",
      };
    }
  },
);

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
        promptVersion: INNERA_AI_PROMPT_VERSION,
        inputTokens: completion.usage?.prompt_tokens ?? null,
        outputTokens: completion.usage?.completion_tokens ?? null,
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
