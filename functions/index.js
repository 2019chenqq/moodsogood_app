const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");

// 初始化 Admin SDK (擁有繞過 Security Rules 的最高權限)
admin.initializeApp();
const db = admin.firestore();
const openAiApiKey = defineSecret("OPENAI_API_KEY");

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

function normalizeReflection(payload, fallbackCrisis) {
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
    model: String(payload.model || "gpt-4.1-mini"),
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

    const { diaryContent, dailyRecord, date } = request.data || {};
    if (!diaryContent || typeof diaryContent !== "string") {
      throw new HttpsError("invalid-argument", "缺少 diaryContent");
    }

    const trimmedDiary = diaryContent.trim().slice(0, 6000);
    const safeDailyRecord =
      dailyRecord && typeof dailyRecord === "object" && !Array.isArray(dailyRecord)
        ? dailyRecord
        : {};
    const crisisDetected = detectCrisis(trimmedDiary);

    if (!trimmedDiary) {
      throw new HttpsError("invalid-argument", "日記內容不能為空");
    }

    try {
      const client = new OpenAI({ apiKey: openAiApiKey.value() });
      const completion = await client.chat.completions.create({
        model: "gpt-4.1-mini",
        temperature: 0.7,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content:
              "你是一位使用繁體中文的心理支持助理。請基於使用者日記提供溫柔、具體、簡潔的正念反思。不要做醫療診斷、不要下病名、不要保證療效。若內容包含明確自傷或自殺意圖，要將 crisisDetected 設為 true。你只能輸出 JSON。",
          },
          {
            role: "user",
            content: JSON.stringify({
              task: "請輸出日記反思 JSON",
              rules: {
                summary: "1 段 60-120 字",
                emotionObservation: "1 段 60-120 字",
                topics: "3 到 5 個短詞",
                positiveFeedback: "1 段 60-120 字",
                gratitudeQuestions: "剛好 3 題，每題一句",
                tomorrowAction: "1 句可執行的小行動",
                crisisDetected: "boolean",
              },
              date: date || "",
              dailyRecord: safeDailyRecord,
              diaryContent: trimmedDiary,
            }),
          },
        ],
      });

      const rawText = completion.choices?.[0]?.message?.content || "";
      const parsed = JSON.parse(stripMarkdownFence(rawText));
      const normalized = normalizeReflection(parsed, crisisDetected);

      if (
        !normalized.summary ||
        !normalized.emotionObservation ||
        !normalized.positiveFeedback ||
        !normalized.tomorrowAction ||
        normalized.topics.length < 3 ||
        normalized.gratitudeQuestions.length < 3
      ) {
        throw new Error("AI 回傳內容不完整");
      }

      return normalized;
    } catch (error) {
      console.error("generateAiJournalReflection failed:", error);
      throw new HttpsError("internal", "AI 生成失敗，請稍後再試");
    }
  },
);