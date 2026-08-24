const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");
const { buildInneraPrompt, sanitizeModeFollowUp } = require("./innera_mode_prompt");
const {
  createEmotionalSupportApiResponse,
  selectInneraChatResponseSchema,
} = require("./innera_emotional_support");
const {
  createPhysicalHealthApiResponse,
  createPhysicalHealthChatSchema,
} = require("./innera_physical_health");
const { buildInneraSafeHistory } = require("./innera_history");
const { buildInneraContextPayload } = require("./innera_request_payload");
const {
  buildInneraLatencyLog,
  createInneraLatencyState,
  elapsedSince,
} = require("./innera_latency");
const crypto = require("crypto");
const { buildSleepTimeStats } = require("./sleep_review_stats");
const { buildEmotionStats } = require("./emotion_review_stats");
const { detectInneraSelfHarm } = require("./innera_safety");
const {
  normalizeInneraEventDrafts,
  sanitizeExplicitStateChangePatch,
} = require("./innera_event_drafts");
const {
  alignEventSummaries,
  normalizeSummaryInput,
} = require("./innera_event_summaries");
const {
  AI_QUOTED_POINTS,
  createAiUsageTracker,
} = require("./ai_usage");
const {
  AiRateLimitError,
  enforceAiRateLimit,
} = require("./ai_rate_limit");
const {
  previousTaipeiDayRange,
  summarizeAiUsageEvents,
} = require("./ai_usage_aggregation");
const {
  authorizeShareRevocation,
  buildShareDocument,
  validateShareDocument,
} = require("./follow_up_share");
const {
  isFollowUpQuestionRequest,
  parseFollowUpQuestionsCompletion,
  sanitizeInneraModeQuestions,
} = require("./innera_ai_response");

// 初始化 Admin SDK (擁有繞過 Security Rules 的最高權限)
admin.initializeApp();
const db = admin.firestore();
const openAiApiKey = defineSecret("OPENAI_API_KEY");
const lastFmApiKey = defineSecret("LASTFM_API_KEY");
const spotifyClientId = defineSecret("SPOTIFY_CLIENT_ID");
const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");
const DEFAULT_AI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";
const INNERA_AI_PROMPT_VERSION = "innera-ai-chat-v18-physical-health-small-schema";
const DIARY_EXTRACTION_PROMPT_VERSION = "diary_extraction_v1";
const EVENT_SUMMARY_PROMPT_VERSION = "innera-event-summary-v1";

async function requireAiCapacity(uid, feature) {
  try {
    await enforceAiRateLimit({
      db,
      admin,
      uid,
      feature,
    });
  } catch (error) {
    if (error instanceof AiRateLimitError) {
      throw new HttpsError(
        "resource-exhausted",
        "AI 使用過於頻繁，請稍後再試。",
        {
          reason: "ai_rate_limit",
          limitType: error.limitType,
          retryAfterSeconds: error.retryAfterSeconds,
        },
      );
    }
    console.error("AI rate limit check failed", {
      uid,
      feature,
      message: error?.message || String(error),
    });
    throw new HttpsError(
      "unavailable",
      "AI 服務暫時無法確認使用額度，請稍後再試。",
    );
  }
}

exports.aggregateDailyAiUsage = onSchedule(
  {
    schedule: "0 1 * * *",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 3,
    maxInstances: 1,
  },
  async (event) => {
    const scheduledAt = new Date(event?.scheduleTime || Date.now());
    const referenceTime = Number.isNaN(scheduledAt.getTime())
      ? new Date()
      : scheduledAt;
    const range = previousTaipeiDayRange(referenceTime);
    const snapshot = await db
      .collection("ai_usage_events")
      .where(
        "createdAt",
        ">=",
        admin.firestore.Timestamp.fromDate(range.start),
      )
      .where(
        "createdAt",
        "<",
        admin.firestore.Timestamp.fromDate(range.end),
      )
      .select(
        "feature",
        "status",
        "quotedPoints",
        "estimatedCostMicroUsd",
        "inputTokens",
        "cachedInputTokens",
        "outputTokens",
        "totalTokens",
      )
      .get();
    const summary = summarizeAiUsageEvents(
      snapshot.docs.map((doc) => doc.data()),
      range.dateKey,
    );

    await db.collection("ai_usage_daily").doc(range.dateKey).set({
      ...summary,
      periodStart: admin.firestore.Timestamp.fromDate(range.start),
      periodEnd: admin.firestore.Timestamp.fromDate(range.end),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("Daily AI usage summary updated", {
      date: range.dateKey,
      eventCount: summary.eventCount,
      succeededCount: summary.succeededCount,
      failedCount: summary.failedCount,
      estimatedCostMicroUsd: summary.estimatedCostMicroUsd,
      quotedPoints: summary.quotedPoints,
    });
  },
);
exports.createFollowUpSummaryShare = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再建立分享");
  const summaryId = String(request.data?.summaryId || "").trim();
  const summarySnapshot = request.data?.summarySnapshot;
  if (!summaryId || !summarySnapshot || typeof summarySnapshot !== "object") {
    throw new HttpsError("invalid-argument", "摘要資料不完整");
  }
  const share = buildShareDocument({ ownerUid: request.auth.uid, summarySnapshot });
  await db.collection("followUpSummaryShares").doc(share.shareId).set({ ...share.document, summaryId });
  return {
    shareId: share.shareId,
    url: `https://moodsogood-9e45b.web.app/follow-up-share.html?token=${encodeURIComponent(share.token)}`,
    expiresAt: share.expiresAt.toISOString(),
  };
});

exports.getFollowUpShareStatuses = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再查看分享");
  const summaryIds = Array.isArray(request.data?.summaryIds)
    ? request.data.summaryIds.map(String).filter(Boolean).slice(0, 100) : [];
  if (!summaryIds.length) return { activeShares: [] };
  const snapshot = await db.collection("followUpSummaryShares")
    .where("ownerUid", "==", request.auth.uid).get();
  const wanted = new Set(summaryIds);
  const now = Date.now();
  return { activeShares: snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((item) => wanted.has(item.summaryId) && !item.revokedAt && item.expiresAt?.toMillis?.() > now)
    .map((item) => ({ summaryId: item.summaryId, shareId: item.id,
      expiresAt: item.expiresAt.toDate().toISOString() })) };
});

exports.revokeFollowUpShare = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再停止分享");
  const ref = db.collection("followUpSummaryShares").doc(String(request.data?.shareId || "").trim());
  const snapshot = await ref.get();
  const authorization = authorizeShareRevocation({
    document: snapshot.exists ? snapshot.data() : null,
    ownerUid: request.auth.uid,
  });
  if (!authorization.ok) {
    throw new HttpsError(authorization.reason === "forbidden" ? "permission-denied" : "not-found", "找不到分享或沒有權限");
  }
  if (!authorization.alreadyRevoked) {
    await ref.update({ revokedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  return { revoked: true };
});

exports.getFollowUpSummaryShare = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  if (request.method === "OPTIONS") return response.status(204).send("");
  const token = String(request.query.token || "");
  if (!token) return response.status(404).json({ error: "not_found" });
  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  const matches = await db.collection("followUpSummaryShares").where("tokenHash", "==", tokenHash).limit(1).get();
  const validation = validateShareDocument({
    document: matches.empty ? null : matches.docs[0].data(), token,
  });
  if (!validation.ok) return response.status(404).json({ error: validation.reason });
  response.set("Cache-Control", "no-store");
  return response.json({ summary: validation.summarySnapshot, expiresAt: validation.expiresAt.toISOString() });
});

exports.cleanupFollowUpSummaryShares = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 1,
    maxInstances: 1,
  },
  async () => {
    const now = Date.now();
    let deletedCount = 0;
    for (const collectionName of [
      "followUpSummaryShares",
      "follow_up_summary_shares",
    ]) {
      const snapshot = await db.collection(collectionName).get();
      const deletions = snapshot.docs.filter((doc) => {
        const data = doc.data();
        const expiresAt = data.expiresAt?.toMillis?.() ??
          new Date(data.expiresAt || 0).getTime();
        const containsPlaintext = Object.prototype.hasOwnProperty.call(
          data,
          "summarySnapshot",
        );
        return containsPlaintext || !Number.isFinite(expiresAt) || expiresAt <= now;
      });
      for (let index = 0; index < deletions.length; index += 500) {
        const batch = db.batch();
        for (const doc of deletions.slice(index, index + 500)) {
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
      deletedCount += deletions.length;
    }
    console.log("Follow-up summary share cleanup completed", { deletedCount });
  },
);

exports.cleanupExpiredAiChatImages = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 1,
    maxInstances: 1,
  },
  async () => {
    const bucket = admin.storage().bucket();
    const [files] = await bucket.getFiles({ prefix: "ai_chat_temp/" });
    const now = Date.now();
    const fallbackCutoff = now - 60 * 60 * 1000;
    const expired = files.filter((file) => {
      const expiresAt = Date.parse(file.metadata?.metadata?.expiresAt || "");
      const createdAt = Date.parse(file.metadata?.timeCreated || "");
      const metadataExpired = !Number.isNaN(expiresAt) && expiresAt <= now;
      const ageExpired =
        !Number.isNaN(createdAt) && createdAt <= fallbackCutoff;
      return metadataExpired || ageExpired;
    });

    for (let index = 0; index < expired.length; index += 50) {
      await Promise.all(
        expired.slice(index, index + 50).map(async (file) => {
          try {
            await file.delete();
          } catch (error) {
            if (Number(error?.code) !== 404) throw error;
          }
        }),
      );
    }

    console.log("Expired AI chat image cleanup completed", {
      scannedCount: files.length,
      deletedCount: expired.length,
    });
  },
);

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

const nullableStringSchema = {
  anyOf: [{ type: "string" }, { type: "null" }],
};
const nullableScoreSchema = {
  anyOf: [
    { type: "integer", minimum: 1, maximum: 5 },
    { type: "null" },
  ],
};
const inneraChatSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "reply",
    "followUpQuestion",
    "sources",
    "suggestedActions",
    "recordDraft",
    "eventDrafts",
    "safetyLevel",
    "requiresFixedSafetyUi",
  ],
  properties: {
    reply: { type: "string" },
    followUpQuestion: nullableStringSchema,
    sources: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "dateRange", "count"],
        properties: {
          label: { type: "string" },
          dateRange: { type: "string" },
          count: { type: "integer" },
        },
      },
    },
    suggestedActions: {
      type: "array",
      maxItems: 4,
      items: { type: "string" },
    },
    recordDraft: {
      type: "object",
      additionalProperties: false,
      required: [
        "date",
        "moodScale",
        "overallMood",
        "emotionMentions",
        "symptoms",
        "stateChanges",
        "bodyMeasurement",
        "sleep",
        "events",
        "diaryText",
        "missingFields",
      ],
      properties: {
        date: { type: "string" },
        moodScale: { type: "integer", enum: [5] },
        overallMood: nullableScoreSchema,
        emotionMentions: {
          type: "array",
          maxItems: 20,
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "rawText",
              "normalizedDimensionId",
              "normalizedDimensionName",
              "value",
              "mentioned",
              "source",
              "needsFollowUp",
              "needsConfirmation",
              "confidence",
              "timeContext",
              "evidence",
              "subjectType",
              "subjectText",
              "isQuotedSpeech",
            ],
            properties: {
              rawText: { type: "string" },
              normalizedDimensionId: nullableStringSchema,
              normalizedDimensionName: nullableStringSchema,
              value: nullableScoreSchema,
              mentioned: { type: "boolean" },
              source: {
                type: "string",
                enum: ["explicit", "summarized", "inferred"],
              },
              needsFollowUp: { type: "boolean" },
              needsConfirmation: { type: "boolean" },
              confidence: { type: "number", minimum: 0, maximum: 1 },
              timeContext: nullableStringSchema,
              evidence: { type: "string" },
              subjectType: {
                type: "string",
                enum: ["user", "other", "shared", "unknown"],
              },
              subjectText: nullableStringSchema,
              isQuotedSpeech: { type: "boolean" },
            },
          },
        },
        symptoms: {
          type: "array",
          maxItems: 30,
          items: {
            type: "object",
            additionalProperties: false,
            required: ["name", "source"],
            properties: {
              name: { type: "string" },
              source: {
                type: "string",
                enum: ["explicit", "summarized", "inferred"],
              },
            },
          },
        },
        stateChanges: {
          type: "object",
          additionalProperties: false,
          required: ["energy_change", "appetite_change", "activity_change"],
          properties: {
            energy_change: nullableScoreSchema,
            appetite_change: nullableScoreSchema,
            activity_change: nullableScoreSchema,
          },
        },
        bodyMeasurement: {
          type: "object",
          additionalProperties: false,
          required: ["weightKg", "bodyFatPercent", "waistCm", "measurementTiming", "customMeasurementTime"],
          properties: {
            weightKg: { anyOf: [{ type: "number" }, { type: "null" }] },
            bodyFatPercent: { anyOf: [{ type: "number" }, { type: "null" }] },
            waistCm: { anyOf: [{ type: "number" }, { type: "null" }] },
            measurementTiming: {
              anyOf: [
                { type: "string", enum: ["afterWaking", "afterBreakfast", "afterLunch", "afterDinner", "beforeSleep", "other"] },
                { type: "null" },
              ],
            },
            customMeasurementTime: nullableStringSchema,
          },
        },
        sleep: {
          type: "object",
          additionalProperties: false,
          required: [
            "sleepTime",
            "wakeTime",
            "finalWakeTime",
            "quality",
            "midWakeList",
            "flags",
            "naps",
          ],
          properties: {
            sleepTime: nullableStringSchema,
            wakeTime: {
              ...nullableStringSchema,
              description: "離床活動時刻：起床、離床、下床開始活動。不是睜眼甦醒時刻。",
            },
            finalWakeTime: {
              ...nullableStringSchema,
              description: "甦醒時刻：醒來、醒著、睜眼、清醒。不是起床離床時刻。",
            },
            quality: nullableScoreSchema,
            midWakeList: nullableStringSchema,
            flags: {
              type: "array",
              items: {
                type: "string",
                enum: [
                  "good",
                  "ok",
                  "earlyWake",
                  "dreams",
                  "lightSleep",
                  "fragmented",
                  "insufficient",
                  "initInsomnia",
                  "interrupted",
                  "nocturia",
                ],
              },
            },
            naps: {
              type: "array",
              maxItems: 6,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["startTime", "endTime", "durationMinutes"],
                properties: {
                  startTime: nullableStringSchema,
                  endTime: nullableStringSchema,
                  durationMinutes: {
                    anyOf: [{ type: "integer" }, { type: "null" }],
                  },
                },
              },
            },
          },
        },
        events: {
          type: "array",
          maxItems: 12,
          items: { type: "string" },
        },
        diaryText: { type: "string" },
        missingFields: {
          type: "array",
          maxItems: 20,
          items: { type: "string" },
        },
      },
    },
    eventDrafts: {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "id",
          "eventTime",
          "timeContext",
          "timePrecision",
          "emotionMentions",
          "symptoms",
          "stateChanges",
          "rawUserEntries",
          "note",
        ],
        properties: {
          id: { type: "string" },
          eventTime: nullableStringSchema,
          timeContext: nullableStringSchema,
          timePrecision: {
            type: "string",
            enum: ["exact", "approximate", "unspecified"],
          },
          emotionMentions: {
            type: "array",
            maxItems: 20,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["rawText", "normalizedDimensionId", "normalizedDimensionName", "value"],
              properties: {
                rawText: { type: "string" },
                normalizedDimensionId: nullableStringSchema,
                normalizedDimensionName: nullableStringSchema,
                value: nullableScoreSchema,
              },
            },
          },
          symptoms: {
            type: "array",
            maxItems: 20,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["name", "severity"],
              properties: {
                name: { type: "string" },
                severity: nullableScoreSchema,
              },
            },
          },
          stateChanges: {
            type: "object",
            additionalProperties: false,
            required: ["energy_change", "appetite_change", "activity_change"],
            properties: {
              energy_change: nullableScoreSchema,
              appetite_change: nullableScoreSchema,
              activity_change: nullableScoreSchema,
            },
          },
          rawUserEntries: {
            type: "array",
            maxItems: 20,
            items: { type: "string" },
          },
          note: { type: "string" },
        },
      },
    },
    safetyLevel: {
      type: "string",
      enum: [
        "normal",
        "possibleSelfHarm",
        "imminentDanger",
        "medicalUrgency",
      ],
    },
    requiresFixedSafetyUi: { type: "boolean" },
  },
};
const physicalHealthChatSchema = createPhysicalHealthChatSchema(
  inneraChatSchema.properties.eventDrafts,
);
const followUpQuestionsSchema = {
  type: "object",
  additionalProperties: false,
  required: ["questions"],
  properties: {
    questions: {
      type: "array",
      maxItems: 4,
      items: { type: "string" },
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
  { secrets: [openAiApiKey], enforceAppCheck: true },
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
      promptVersion: "journal_reflection_v1",
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
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "innera_ai_chat_response",
            strict: true,
            schema: inneraChatSchema,
          },
        },
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

function extractExplicitSleepTimes(rawText) {
  const result = { wakeTime: null, finalWakeTime: null };
  const clauses = String(rawText || "").split(/[，。！？\n]+/).filter(Boolean);
  const clockBeforeAction = (clause, actionPattern) => {
    const match = clause.match(new RegExp(
      "(凌晨|清晨|早上|上午|下午|晚上)?\\s*" +
      "(\\d{1,2})(?:[:：]([0-5]\\d)|點(?:(半)|([0-5]?\\d)\\s*分?)?)" +
      "\\s*(?:多|左右)?" +
      `[^0-9０-９，。！？\\n]{0,12}(?:${actionPattern})`,
    ));
    if (!match) return null;
    let hour = Number(match[2]);
    if (!Number.isInteger(hour) || hour > 23) return null;
    if ((match[1] === "下午" || match[1] === "晚上") && hour < 12) hour += 12;
    if (match[1] === "凌晨" && hour === 12) hour = 0;
    const minute = match[4] ? 30 : Number(match[3] || match[5] || 0);
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  };
  for (const clause of clauses) {
    if (/昨天|前天|昨晚/.test(clause)) continue;
    result.wakeTime ||= clockBeforeAction(clause, "起床|離床|下床|開始活動");
    const awakening = clockBeforeAction(
      clause,
      "醒來|醒了|醒著|清醒|睜眼|睜開眼",
    );
    const returnedToSleep =
      /(?:醒來|醒了|醒著|清醒|睜眼|睜開眼)[^，。！？\n]{0,16}(?:又睡|再睡|睡回去|繼續睡)/.test(clause);
    if (!returnedToSleep) result.finalWakeTime ||= awakening;
  }
  return result;
}

function normalizeInneraRecordDraft(rawDraft, existingDraft, emotionDimensions, latestMessage) {
  const raw = rawDraft && typeof rawDraft === "object" ? rawDraft : {};
  const existing = existingDraft && typeof existingDraft === "object" ? existingDraft : {};
  const safeText = (value, max = 1200) => String(value || "").trim().slice(0, max);
  const validTime = (value) => {
    const text = safeText(value, 5);
    return /^([01]?\d|2[0-3]):[0-5]\d$/.test(text) ? text.padStart(5, "0") : null;
  };
  const validScore = (value) => {
    if (value == null || value === "") return null;
    const score = Number(value);
    return Number.isInteger(score) && score >= 1 && score <= 5 ? score : null;
  };
  const itemName = (item) =>
    safeText(item && typeof item === "object" ? item.name : item, 100);
  const symptomPatterns = [
    ["疲倦", /疲倦|疲憊|很累|好累|很倦|倦怠/],
    ["動力不足", /動力不足|沒有動力|沒動力|缺乏動力|提不起勁/],
    ["一直想吃東西", /食慾增加|食慾變大|食量增加|吃得比平常多|一直想吃/],
    ["食慾降低", /食慾下降|食慾降低|食慾不振|沒有食慾|沒胃口|吃不下/],
    ["噁心反胃", /想吐|噁心|反胃/],
    ["頭痛", /頭痛|頭疼/],
    ["心悸", /心悸|心跳很快/],
    ["胃痛", /胃痛|胃不舒服/],
  ];
  const symptomNamesFromText = (value) => {
    const text = safeText(value, 500);
    return symptomPatterns
      .filter(([, pattern]) => pattern.test(text))
      .map(([name]) => name);
  };
  const dimensions = Array.isArray(emotionDimensions) ? emotionDimensions : [];
  const dimensionById = new Map(dimensions.map((item) => [item.id, item]));
  const dimensionByTerm = new Map();
  for (const dimension of dimensions) {
    dimensionByTerm.set(dimension.displayName, dimension);
    for (const alias of dimension.aliases) dimensionByTerm.set(alias, dimension);
  }
  const resolveDimension = (item, rawText) => {
    const requestedId = safeText(item?.normalizedDimensionId, 80);
    const requestedName = safeText(item?.normalizedDimensionName, 80);
    const byId = dimensionById.get(requestedId);
    if (byId && (!requestedName || requestedName === byId.displayName)) return byId;
    return dimensionByTerm.get(requestedName) || dimensionByTerm.get(rawText) || null;
  };
  const stateIds = ["energy_change", "appetite_change", "activity_change"];
  const rawStateChanges = sanitizeExplicitStateChangePatch(
    raw.stateChanges,
    latestMessage,
  );
  const stateChanges = {};
  for (const id of stateIds) {
    const next = validScore(rawStateChanges[id]);
    const old = validScore(existing.stateChanges?.[id]);
    if (next != null || old != null) stateChanges[id] = next ?? old;
  }
  const validMeasurement = (value, min, max) => {
    if (value == null || value === "") return null;
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < min || parsed > max) return null;
    const scaled = parsed * 10;
    if (Math.abs(scaled - Math.round(scaled)) > 1e-9) return null;
    return Math.round(scaled) / 10;
  };
  const nextBody = raw.bodyMeasurement && typeof raw.bodyMeasurement === "object"
    ? raw.bodyMeasurement
    : {};
  const oldBody = existing.bodyMeasurement && typeof existing.bodyMeasurement === "object"
    ? existing.bodyMeasurement
    : {};
  const timingValues = new Set(["afterWaking", "afterBreakfast", "afterLunch", "afterDinner", "beforeSleep", "other"]);
  const measurementTimingTerms = "(?:起床(?:後)?|早餐後|午餐後|晚餐後|吃飯後|飯後|睡前|運動後)";
  const measurementTerms = "(?:量|測|體重|體脂|腰圍)";
  const measurementTimingWasExplicit = new RegExp(
    `${measurementTimingTerms}[^，。！？；\\n]{0,12}${measurementTerms}|` +
    `${measurementTerms}[^，。！？；\\n]{0,12}${measurementTimingTerms}`,
  ).test(safeText(latestMessage, 4000));
  const requestedTiming = measurementTimingWasExplicit
    ? nextBody.measurementTiming ?? oldBody.measurementTiming
    : oldBody.measurementTiming;
  let measurementTiming = timingValues.has(requestedTiming) ? requestedTiming : null;
  const customMeasurementTime = measurementTiming === "other"
    ? safeText(nextBody.customMeasurementTime, 100) ||
      (oldBody.measurementTiming === "other"
        ? safeText(oldBody.customMeasurementTime, 100)
        : "")
    : "";
  if (measurementTiming === "other" && !customMeasurementTime) {
    measurementTiming = null;
  }
  const weightKg = validMeasurement(nextBody.weightKg, 20, 300) ?? validMeasurement(oldBody.weightKg, 20, 300);
  const bodyFatPercent = validMeasurement(nextBody.bodyFatPercent, 1, 70) ?? validMeasurement(oldBody.bodyFatPercent, 1, 70);
  const waistCm = validMeasurement(nextBody.waistCm, 30, 250) ?? validMeasurement(oldBody.waistCm, 30, 250);
  const hasBodyMeasurementValue = weightKg != null || bodyFatPercent != null || waistCm != null;
  if (!hasBodyMeasurementValue) measurementTiming = null;
  const bodyMeasurement = {
    weightKg,
    bodyFatPercent,
    waistCm,
    measurementTiming,
    customMeasurementTime:
      hasBodyMeasurementValue && measurementTiming === "other"
        ? customMeasurementTime
        : null,
  };
  const otherSubjectPattern = /(爸爸|爸媽|媽媽|母親|父親|弟弟|妹妹|哥哥|姊姊|姐姐|家人|朋友|同事|同學|老師|醫師|醫生|護理師|伴侶|男友|女友|先生|太太|孩子|兒子|女兒|對方|他們|她們|他|她)/;
  const explicitUserPattern = /(我(?:自己|本人|也|還|真的|其實|現在|今天|當下|開始|感到|感覺|覺得|變得|很|好|超|有點|有些|有一點|心裡|心情)?|讓我|害我|使我|令我|我的)/;
  const sharedUserPattern = /(我們(?:都|一起)?|我也(?:一樣|開始|覺得|感到)?|我和[^，。！？；\n]{0,12}(?:都|一樣))/;
  const speechOrMediaPattern = /(說|表示|告訴|問|寫著|提到|看起來|覺得我|歌詞|歌曲|電影|影集|文章|貼文|新聞|小說)/;
  const quotePattern = /[「『\"“].+[」』\"”]/;
  const subjectTextFromEvidence = (text) =>
    (safeText(text, 500).match(otherSubjectPattern) || [null])[0];
  const emotionInsideQuote = (text, rawText) => {
    const evidence = safeText(text, 500);
    const term = safeText(rawText, 100);
    if (!term) return false;
    const quotedParts = evidence.match(/[「『\"“][^」』\"”]+[」』\"”]/g) || [];
    return quotedParts.some((part) => part.includes(term));
  };
  const matchingEvidence = (item, rawText) => {
    const evidence = safeText(item?.evidence, 300);
    if (evidence) return evidence;
    return latestClauses.find((clause) => clause.includes(rawText)) || "";
  };
  const classifyEmotionSubject = (item, rawText, isExisting = false) => {
    const evidence = matchingEvidence(item, rawText);
    const requested = ["user", "other", "shared", "unknown"].includes(item?.subjectType)
      ? item.subjectType
      : null;
    const explicitUser = explicitUserPattern.test(evidence);
    const sharedUser = sharedUserPattern.test(evidence);
    const otherSubject = otherSubjectPattern.test(evidence);
    const emotionIndex = evidence.indexOf(rawText);
    const evidenceBeforeEmotion = emotionIndex >= 0
      ? evidence.slice(0, emotionIndex)
      : evidence;
    const lastUserBeforeEmotion = Math.max(
      evidenceBeforeEmotion.lastIndexOf("我"),
      evidenceBeforeEmotion.lastIndexOf("自己"),
    );
    let lastOtherBeforeEmotion = -1;
    for (const match of evidenceBeforeEmotion.matchAll(new RegExp(otherSubjectPattern.source, "g"))) {
      lastOtherBeforeEmotion = Math.max(lastOtherBeforeEmotion, match.index ?? -1);
    }
    const otherOwnsEmotion =
      lastOtherBeforeEmotion >= 0 && lastOtherBeforeEmotion > lastUserBeforeEmotion;
    const quoted = item?.isQuotedSpeech === true ||
      emotionInsideQuote(evidence, rawText) ||
      (otherSubject && speechOrMediaPattern.test(evidence));
    let subjectType = requested;
    if (isExisting && item?.source === "existingRecord") {
      subjectType = "user";
    } else if (quoted && !sharedUser) {
      subjectType = "other";
    } else if ((otherOwnsEmotion || (otherSubject && !explicitUser)) && !sharedUser) {
      subjectType = "other";
    } else if (sharedUser) {
      subjectType = "shared";
    } else if (!subjectType) {
      // Old drafts are migrated conservatively: never assume an unspecified
      // subject is the user without explicit first-person evidence.
      subjectType = explicitUser ? "user" : "unknown";
    }
    const source = safeText(item?.source, 40);
    const inferred = source === "inferred";
    return {
      subjectType,
      subjectText: subjectType === "other"
        ? safeText(item?.subjectText, 80) || subjectTextFromEvidence(evidence)
        : (safeText(item?.subjectText, 80) || (explicitUser ? "我" : null)),
      isQuotedSpeech: quoted,
      evidence,
      source,
      inferred,
      explicitUser,
      keep: (subjectType === "user" ||
        (subjectType === "shared" && explicitUser && !quoted)) &&
        !(quoted && subjectType !== "shared"),
    };
  };
  const latestClauses = safeText(latestMessage, 4000)
    .replace(/但|可是|不過|然而/g, "，")
    .split(/[，。！？；\n]+/)
    .map((clause) => clause.trim())
    .filter(Boolean);
  const timeContextFromClause = (clause) => {
    if (/昨天|昨晚/.test(clause)) return "昨天";
    if (/前天/.test(clause)) return "前天";
    if (/今天|今日/.test(clause)) return null;
    if (/早上|早晨/.test(clause)) return "早上";
    if (/中午/.test(clause)) return "中午";
    if (/下午/.test(clause)) return "下午";
    if (/晚上|今晚/.test(clause)) return "晚上";
    if (/剛剛|現在/.test(clause)) return "當下";
    return null;
  };
  const temporalScopeForMention = (item, dimension, rawText) => {
    const comparable = (value) =>
      safeText(value, 500).replace(/\s+|也|有點|還是|仍然|還|很|真的/g, "");
    const terms = [
      rawText,
      safeText(item?.evidence, 300),
      dimension?.displayName,
      ...(Array.isArray(dimension?.aliases) ? dimension.aliases : []),
    ]
      .map((term) => safeText(term, 300))
      .filter(Boolean)
      .sort((left, right) => right.length - left.length);
    for (let index = latestClauses.length - 1; index >= 0; index -= 1) {
      const clause = latestClauses[index];
      const comparableClause = comparable(clause);
      const matched = terms.some(
        (term) =>
          clause.includes(term) ||
          (comparable(term) &&
            comparableClause.includes(comparable(term))) ||
          (term.length >= 4 && term.includes(clause)),
      );
      if (matched) {
        return { matched: true, timeContext: timeContextFromClause(clause) };
      }
    }
    return { matched: false, timeContext: null };
  };
  const sleepFlagAliases = new Map([
    ["maintInsomnia", "interrupted"],
    ["earlyWake", "earlyWake"],
    ["light", "lightSleep"],
    ["lightSleep", "lightSleep"],
    ["dreams", "dreams"],
    ["lack", "insufficient"],
    ["insufficient", "insufficient"],
    ["fragile", "fragmented"],
    ["fragmented", "fragmented"],
    ["initInsomnia", "initInsomnia"],
    ["interrupted", "interrupted"],
    ["nocturia", "nocturia"],
    ["good", "good"],
    ["ok", "ok"],
  ]);
  const sleepFlagFromText = (value) => {
    const text = safeText(value, 120);
    if (/睡不著|難入睡|入睡困難|躺很久|翻來覆去|無法進入睡眠|闔眼.*張開/.test(text)) {
      return "initInsomnia";
    }
    if (/半夜.*醒|夜裡.*醒|反覆醒|睡眠中斷|維持睡眠/.test(text)) return "interrupted";
    if (/太早醒|提早醒|早醒/.test(text)) return "earlyWake";
    if (/淺眠|睡很淺/.test(text)) return "lightSleep";
    if (/多夢|惡夢|噩夢/.test(text)) return "dreams";
    if (/睡眠不足|沒睡飽|睡不夠/.test(text)) return "insufficient";
    if (/斷斷續續|睡睡醒醒/.test(text)) return "fragmented";
    if (/夜尿|半夜.*上廁所/.test(text)) return "nocturia";
    return null;
  };
  const mergeNames = (first, second, max) =>
    [...new Set([...(Array.isArray(first) ? first : []), ...(Array.isArray(second) ? second : [])]
      .map(itemName)
      .filter(Boolean))].slice(0, max);
  const emotionMap = new Map();
  const migratedEmotionSymptoms = new Set();
  const excludedEmotionEvents = new Set();
  const excludedEmotionTerms = new Set();
  const existingMentions = Array.isArray(existing.emotionMentions)
    ? existing.emotionMentions
    : (Array.isArray(existing.emotions) ? existing.emotions : []);
  for (const item of existingMentions) {
    const rawText = safeText(item?.rawText || itemName(item), 100);
    const symptomNames = symptomNamesFromText(
      `${rawText} ${safeText(item?.evidence, 300)}`,
    );
    if (symptomNames.length > 0) {
      for (const name of symptomNames) migratedEmotionSymptoms.add(name);
      continue;
    }
    const dimension = resolveDimension(item, rawText);
    const score = validScore(item?.value ?? item?.score);
    if (!rawText) continue;
    const subject = classifyEmotionSubject(item, rawText, true);
    if (!subject.keep) {
      excludedEmotionTerms.add(rawText);
      if (dimension?.displayName) excludedEmotionTerms.add(dimension.displayName);
      if (subject.subjectType === "other" && subject.evidence) {
        excludedEmotionEvents.add(subject.evidence);
      }
      continue;
    }
    const key = dimension?.id || `raw:${rawText}`;
    const inferredConfidence = subject.inferred
      ? Math.min(0.75, Number(item?.confidence) || 0)
      : Math.max(0, Math.min(1, Number(item?.confidence) || 0));
    emotionMap.set(key, {
      rawText,
      normalizedDimensionId: dimension?.id || null,
      normalizedDimensionName: dimension?.displayName || null,
      value: score,
      mentioned: item?.mentioned !== false,
      needsFollowUp: score == null,
      needsConfirmation: !dimension || subject.inferred || item?.needsConfirmation === true,
      confidence: inferredConfidence,
      source: item?.source || "existingRecord",
      timeContext: safeText(item?.timeContext, 40) || null,
      evidence: subject.evidence,
      subjectType: subject.subjectType,
      subjectText: subject.subjectText,
      isQuotedSpeech: subject.isQuotedSpeech,
    });
  }
  const rawMentions = Array.isArray(raw.emotionMentions)
    ? raw.emotionMentions
    : (Array.isArray(raw.emotions) ? raw.emotions : []);
  for (const item of rawMentions) {
    const rawText = safeText(item?.rawText || itemName(item), 100);
    if (!rawText) continue;
    const symptomNames = symptomNamesFromText(
      `${rawText} ${safeText(item?.evidence, 300)}`,
    );
    if (symptomNames.length > 0) {
      for (const name of symptomNames) migratedEmotionSymptoms.add(name);
      continue;
    }
    const dimension = resolveDimension(item, rawText);
    const score = validScore(item?.value ?? item?.score);
    const subject = classifyEmotionSubject(item, rawText);
    if (!subject.keep) {
      excludedEmotionTerms.add(rawText);
      if (dimension?.displayName) excludedEmotionTerms.add(dimension.displayName);
      if (subject.subjectType === "other" && subject.evidence) {
        excludedEmotionEvents.add(subject.evidence);
      }
      continue;
    }
    const key = dimension?.id || `raw:${rawText}`;
    const previousEmotion = emotionMap.get(key);
    const resolvedScore = score ?? previousEmotion?.value ?? null;
    const temporalScope = temporalScopeForMention(item, dimension, rawText);
    emotionMap.set(key, {
      rawText,
      normalizedDimensionId: dimension?.id || null,
      normalizedDimensionName: dimension?.displayName || null,
      value: resolvedScore,
      mentioned: item?.mentioned !== false,
      needsFollowUp: resolvedScore == null,
      needsConfirmation: !dimension || subject.inferred || item?.needsConfirmation === true,
      confidence: subject.inferred
        ? Math.min(0.75, Number(item?.confidence) || 0)
        : Math.max(0, Math.min(1, Number(item?.confidence) || 0)),
      source:
        item?.source === "explicit" || item?.source === "explicitUserInput"
          ? "explicitUserInput"
          : item?.source || "aiExtracted",
      timeContext: temporalScope.matched
        ? temporalScope.timeContext
        : previousEmotion?.timeContext || null,
      evidence: subject.evidence || previousEmotion?.evidence || "",
      subjectType: subject.subjectType,
      subjectText: subject.subjectText,
      isQuotedSpeech: subject.isQuotedSpeech,
    });
  }
  const oldSleep = existing.sleep && typeof existing.sleep === "object" ? existing.sleep : {};
  const nextSleep = raw.sleep && typeof raw.sleep === "object" ? raw.sleep : {};
  const sleepFlags = new Set();
  for (const flag of [...(Array.isArray(oldSleep.flags) ? oldSleep.flags : []), ...(Array.isArray(nextSleep.flags) ? nextSleep.flags : [])]) {
    const normalized = sleepFlagAliases.get(safeText(flag, 40)) || sleepFlagFromText(flag);
    if (normalized) sleepFlags.add(normalized);
  }
  const symptoms = [...migratedEmotionSymptoms];
  for (const item of [...(Array.isArray(existing.symptoms) ? existing.symptoms : []), ...(Array.isArray(raw.symptoms) ? raw.symptoms : [])]) {
    const name = itemName(item);
    if (!name) continue;
    const sleepFlag = sleepFlagFromText(name);
    if (sleepFlag) {
      sleepFlags.add(sleepFlag);
    } else {
      const canonicalNames = symptomNamesFromText(name);
      if (canonicalNames.length > 0) {
        for (const canonicalName of canonicalNames) {
          if (!symptoms.includes(canonicalName)) symptoms.push(canonicalName);
        }
      } else if (!symptoms.includes(name)) {
        symptoms.push(name);
      }
    }
  }
  const explicitSleepTimes = extractExplicitSleepTimes(latestMessage);
  const sleep = {
    sleepTime: validTime(nextSleep.sleepTime) || validTime(oldSleep.sleepTime),
    wakeTime: explicitSleepTimes.wakeTime || validTime(nextSleep.wakeTime) || validTime(oldSleep.wakeTime),
    finalWakeTime: explicitSleepTimes.finalWakeTime || validTime(nextSleep.finalWakeTime) || validTime(oldSleep.finalWakeTime),
    quality: validScore(nextSleep.quality) || validScore(oldSleep.quality),
    midWakeList: safeText(nextSleep.midWakeList, 300) || safeText(oldSleep.midWakeList, 300),
    flags: [...sleepFlags].slice(0, 12),
    naps: Array.isArray(nextSleep.naps) ? nextSleep.naps.slice(0, 6) : (Array.isArray(oldSleep.naps) ? oldSleep.naps.slice(0, 6) : []),
  };
  const overallMood = validScore(raw.overallMood) ?? validScore(existing.overallMood);
  const pendingEmotionFields = [...emotionMap.values()]
    .filter((item) => item.value == null || item.normalizedDimensionId == null)
    .map((item) => `${item.rawText}的正式情緒與強度`);
  const result = {
    date: safeText(raw.date || existing.date, 10),
    moodScale: 5,
    overallMood: overallMood,
    emotionMentions: [...emotionMap.values()].slice(0, 20),
    symptoms: symptoms.slice(0, 30),
    stateChanges,
    bodyMeasurement,
    sleep,
    events: mergeNames(
      mergeNames(existing.events, raw.events, 12),
      [...excludedEmotionEvents],
      12,
    ),
    diaryText: safeText(raw.diaryText ?? raw.diaryTextDraft, 8000) ||
      safeText(existing.diaryText ?? existing.diaryTextDraft, 8000),
    missingFields: mergeNames([], [
      ...(Array.isArray(raw.missingFields)
        ? raw.missingFields.filter((field) =>
          ![...excludedEmotionTerms].some((term) => safeText(field, 200).includes(term)))
        : []),
      ...pendingEmotionFields,
    ], 20),
  };
  Object.defineProperty(result, "excludedEmotionTerms", {
    value: [...excludedEmotionTerms],
    enumerable: false,
  });
  return result;
}

exports.generateInneraDiaryDraft = onCall(
  { secrets: [openAiApiKey], enforceAppCheck: true },
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

exports.recommendInneraSongs = onCall(
  {
    secrets: [
      openAiApiKey,
      lastFmApiKey,
      spotifyClientId,
      spotifyClientSecret,
    ],
    enforceAppCheck: true,
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

    await requireAiCapacity(request.auth.uid, "song_recommendation");
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
      let selection;
      const usageTracker = createAiUsageTracker({
        db,
        admin,
        uid: request.auth.uid,
        requestId: request.data?.requestId,
        feature: "song_recommendation",
        model: DEFAULT_AI_MODEL,
        promptVersion: "song_selection_v1",
        quotedPoints: AI_QUOTED_POINTS.song_recommendation,
      });
      await usageTracker.start();
      try {
        const ai = new OpenAI({ apiKey: openAiApiKey.value() });
        selection = await ai.chat.completions.create({
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
        await usageTracker.succeed(selection);
      } catch (error) {
        await usageTracker.fail(error, selection);
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
  {
    secrets: [spotifyClientId, spotifyClientSecret],
    enforceAppCheck: true,
  },
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
    await requireAiCapacity(request.auth.uid, "music_search");
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

exports.summarizeInneraHealthEvents = onCall(
  { secrets: [openAiApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再整理事件紀錄");
    }
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

exports.generateInneraAiChat = onCall(
  { secrets: [openAiApiKey], enforceAppCheck: true },
  async (request) => {
    const latencyState = createInneraLatencyState();
    let latencyLogged = false;
    let latencyMode = String(request.data?.mode || "emotionalSupport").trim();
    let completion;
    const logLatency = (status) => {
      if (latencyLogged) return;
      latencyLogged = true;
      console.log("Innera AI latency", buildInneraLatencyLog({
        state: latencyState,
        mode: latencyMode,
        completion,
        promptVersion: INNERA_AI_PROMPT_VERSION,
        status,
      }));
    };
    console.log("generateInneraAiChat invoked", {
      mode: request.data?.mode,
      authenticated: Boolean(request.auth),
    });
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "請先登入後再使用心域 AI");
    }

    const data = request.data || {};
    const mode = String(data.mode || "emotionalSupport").trim();
    latencyMode = mode;
    const supportsDailyRecordDraft = mode !== "recentReview";
    // Follow-up summaries include a structured output contract and can be
    // substantially longer than ordinary chat messages. Truncating them at
    // the generic chat limit can remove the required JSON instructions and
    // cause the model to return an empty reply.
    const messageLimit = mode === "recentReview" ? 16000 : 2000;
    const message = String(data.message || "").trim().slice(0, messageLimit);
    const requestedImages = Array.isArray(data.images)
      ? data.images
      : data.image && typeof data.image === "object"
        ? [data.image]
        : [];
    if (requestedImages.length > 10) {
      throw new HttpsError("invalid-argument", "AI chat accepts at most 10 images");
    }
    const images = requestedImages.map((requestedImage) => {
      const storagePath = String(requestedImage.storagePath || "").trim();
      const contentType = String(requestedImage.contentType || "").trim();
      const expectedPrefix = `ai_chat_temp/${request.auth.uid}/`;
      const allowedContentTypes = new Set([
        "image/jpeg",
        "image/png",
        "image/webp",
      ]);
      if (
        !storagePath.startsWith(expectedPrefix) ||
        storagePath.includes("..") ||
        !allowedContentTypes.has(contentType)
      ) {
        throw new HttpsError("invalid-argument", "Invalid AI chat image");
      }
      return { storagePath, contentType };
    });
    const context =
      data.context && typeof data.context === "object" ? { ...data.context } : {};
    const history = Array.isArray(data.messages) ? data.messages : [];
    const existingRecordDraft =
      supportsDailyRecordDraft &&
      data.recordDraft &&
      typeof data.recordDraft === "object"
        ? data.recordDraft
        : {};
    const emotionDimensions = (Array.isArray(data.emotionDimensions)
      ? data.emotionDimensions
      : [])
      .map((item) => {
        const id = String(item?.id || "").trim().slice(0, 80);
        const displayName = String(item?.displayName || "").trim().slice(0, 80);
        const aliases = (Array.isArray(item?.aliases) ? item.aliases : [])
          .map((alias) => String(alias || "").trim().slice(0, 80))
          .filter(Boolean)
          .slice(0, 20);
        return id && displayName ? { id, displayName, aliases } : null;
      })
      .filter(Boolean)
      .filter(
        (item, index, items) =>
          items.findIndex(
            (candidate) =>
              candidate.id === item.id ||
              candidate.displayName === item.displayName,
          ) === index,
      )
      .slice(0, 80);
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
    if (mode === "recentReview") {
      context.sleepTimeStats = buildSleepTimeStats(context.recentDailyRecords);
      context.emotionStats = buildEmotionStats(context.recentDailyRecords);
    }
    if (!message) {
      throw new HttpsError("invalid-argument", "請輸入想和心域 AI 說的內容");
    }

    const safetySignal = detectInneraSelfHarm(message);
    const harmToOthersPhrases = ["想殺人", "想傷害別人"];
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
    const hasImminentDanger = harmToOthersPhrases.some((phrase) =>
      message.includes(phrase),
    );
    const hasMedicalUrgency = medicalUrgencyPhrases.some((phrase) => message.includes(phrase));
    if (safetySignal.detected || hasImminentDanger || hasMedicalUrgency) {
      logLatency("safety_bypass");
      return {
        reply: "",
        followUpQuestion: null,
        sources: [],
        suggestedActions: [],
        recordDraft: null,
        eventDrafts: [],
        safetyLevel: hasMedicalUrgency
          ? "medicalUrgency"
          : safetySignal.level === "concern"
            ? "possibleSelfHarm"
            : "imminentDanger",
        requiresFixedSafetyUi: true,
        model: null,
      };
    }

    const usageFeature =
      mode === "recentReview" ? "recent_review" : "innera_chat";
    const followUpQuestionRequest = isFollowUpQuestionRequest(mode, message);
    const rateLimitStartedAt = Date.now();
    try {
      await requireAiCapacity(request.auth.uid, usageFeature);
    } catch (error) {
      latencyState.rateLimitMs = elapsedSince(rateLimitStartedAt);
      logLatency("rate_limit_failed");
      throw error;
    }
    latencyState.rateLimitMs = elapsedSince(rateLimitStartedAt);
    const preparationStartedAt = Date.now();
    const usageTracker = createAiUsageTracker({
      db,
      admin,
      uid: request.auth.uid,
      requestId: data.requestId,
      feature: usageFeature,
      model: DEFAULT_AI_MODEL,
      promptVersion: INNERA_AI_PROMPT_VERSION,
      quotedPoints: AI_QUOTED_POINTS[usageFeature],
      metadata: { mode },
    });
    try {
      await usageTracker.start();
    } catch (error) {
      latencyState.preparationMs = elapsedSince(preparationStartedAt);
      logLatency("usage_start_failed");
      throw error;
    }

    const succeedUsageAndLog = async () => {
      const usageWriteStartedAt = Date.now();
      await usageTracker.succeed(completion);
      latencyState.usageWriteMs += elapsedSince(usageWriteStartedAt);
      logLatency("succeeded");
    };

    let parseNormalizeStartedAt = null;
    try {
      const apiKey = openAiApiKey.value();
      if (!apiKey) {
        throw new HttpsError("internal", "缺少 OPENAI_API_KEY 設定");
      }

      let currentUserContent = message;
      if (images.length) {
        const imageContents = [];
        for (const image of images) {
          const file = admin.storage().bucket().file(image.storagePath);
          const [metadata] = await file.getMetadata();
          const storedContentType = String(metadata.contentType || "");
          const storedSize = Number(metadata.size || 0);
          if (
            storedContentType !== image.contentType ||
            storedSize <= 0 ||
            storedSize > 5 * 1024 * 1024 ||
            metadata.metadata?.purpose !== "innera-ai-chat-temporary"
          ) {
            throw new HttpsError("invalid-argument", "Invalid stored AI chat image");
          }
          const [imageBytes] = await file.download();
          try {
            await file.delete();
          } catch (cleanupError) {
            console.warn("Temporary AI chat image cleanup failed", {
              uid: request.auth.uid,
              storagePath: image.storagePath,
              error: cleanupError?.message || String(cleanupError),
            });
          }
          imageContents.push({
            type: "image_url",
            image_url: {
              url: `data:${image.contentType};base64,${imageBytes.toString("base64")}`,
              detail: "low",
            },
          });
        }
        currentUserContent = [{ type: "text", text: message }, ...imageContents];
      }

      const { safeHistory, historyCharacters } = buildInneraSafeHistory(
        history,
        mode,
      );
      console.log("generateInneraAiChat history prepared", {
        mode,
        safeHistoryLength: safeHistory.length,
        historyCharacters,
      });
      latencyState.safeHistoryCount = safeHistory.length;
      latencyState.historyCharacters = historyCharacters;

      const client = new OpenAI({ apiKey });
      latencyState.preparationMs = elapsedSince(preparationStartedAt);
      const openAiStartedAt = Date.now();
      try {
        completion = await client.chat.completions.create({
        model: DEFAULT_AI_MODEL,
        temperature: 0.55,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: followUpQuestionRequest
              ? "follow_up_questions_response"
              : mode === "emotionalSupport"
                ? "innera_emotional_support_response"
                : mode === "physicalHealth"
                  ? "innera_physical_health_response"
                : "innera_chat_response",
            strict: true,
            schema: selectInneraChatResponseSchema({
              mode,
              followUpQuestionRequest,
              followUpQuestionsSchema,
              inneraChatSchema,
              physicalHealthChatSchema,
            }),
          },
        },
        messages: [
          {
            role: "system",
            content: buildInneraPrompt(mode),
          },
          {
            role: "user",
            content: JSON.stringify(buildInneraContextPayload({
              mode,
              context,
              contextSources,
              recordDraft: existingRecordDraft,
              emotionDimensions,
            })),
          },
          ...safeHistory,
          {
            role: "user",
            content: currentUserContent,
          },
        ],
        });
      } finally {
        latencyState.openAiMs = elapsedSince(openAiStartedAt);
      }

      parseNormalizeStartedAt = Date.now();

      if (followUpQuestionRequest) {
        const questionResult = parseFollowUpQuestionsCompletion(completion);
        if (!questionResult.parsed) {
          throw new Error(questionResult.failure || "Invalid follow-up questions response");
        }
        latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
        await succeedUsageAndLog();
        return {
          ...questionResult.parsed,
          sources: [],
          safetyLevel: "normal",
          requiresFixedSafetyUi: false,
          model: DEFAULT_AI_MODEL,
          promptVersion: INNERA_AI_PROMPT_VERSION,
          inputTokens: completion.usage?.prompt_tokens ?? null,
          outputTokens: completion.usage?.completion_tokens ?? null,
        };
      }

      const rawText = String(completion.choices?.[0]?.message?.content || "").trim();
      if (!rawText) {
        throw new Error("Empty OpenAI response");
      }
      const parsed = JSON.parse(stripMarkdownFence(rawText));
      const rawFollowUpQuestion = String(parsed.followUpQuestion || "")
        .trim()
        .slice(0, 600);
      // The structured chat schema exposes a dedicated followUpQuestion field.
      // During the follow-up-summary clarification step the model can correctly
      // place its only question there and leave reply empty. Treat that valid
      // question as the textual reply so the app's existing question parser can
      // continue instead of turning it into an internal server error.
      let reply = String(parsed.reply || rawFollowUpQuestion)
        .trim()
        .slice(0, 6000);
      if (!reply && mode === "recentReview") {
        // The follow-up client already has a deterministic local summary
        // fallback when the model does not provide the requested JSON shape.
        // Return an empty JSON object to activate it instead of surfacing an
        // opaque internal error and discarding the whole workflow.
        console.warn("generateInneraAiChat received empty recentReview reply", {
          requestId: usageTracker.requestId,
          finishReason: completion.choices?.[0]?.finish_reason,
          hasRefusal: Boolean(completion.choices?.[0]?.message?.refusal),
        });
        reply = "{}";
      }
      if (!reply) {
        throw new Error("Missing AI reply");
      }

      if (mode === "emotionalSupport" && !followUpQuestionRequest) {
        const followUpQuestion = sanitizeModeFollowUp(
          mode,
          rawFollowUpQuestion,
        );
        const result = createEmotionalSupportApiResponse({
          reply: sanitizeInneraModeQuestions(mode, reply, followUpQuestion),
          followUpQuestion,
          model: DEFAULT_AI_MODEL,
          promptVersion: INNERA_AI_PROMPT_VERSION,
          completion,
        });
        latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
        await succeedUsageAndLog();
        return result;
      }

      if (mode === "physicalHealth") {
        const normalizedEventDrafts = normalizeInneraEventDrafts(
          images.length ? existingRecordDraft.eventDrafts : parsed.eventDrafts,
          existingRecordDraft.eventDrafts,
        );
        const result = createPhysicalHealthApiResponse({
          reply,
          followUpQuestion: rawFollowUpQuestion,
          eventDrafts: normalizedEventDrafts,
          model: DEFAULT_AI_MODEL,
          promptVersion: INNERA_AI_PROMPT_VERSION,
          completion,
        });
        latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
        await succeedUsageAndLog();
        return result;
      }

      const normalizedRecordDraft = supportsDailyRecordDraft
        ? normalizeInneraRecordDraft(
            image ? existingRecordDraft : parsed.recordDraft,
            existingRecordDraft,
            emotionDimensions,
            message,
          )
        : null;
      const normalizedEventDrafts = supportsDailyRecordDraft
        ? normalizeInneraEventDrafts(
            image ? existingRecordDraft.eventDrafts : parsed.eventDrafts,
            existingRecordDraft.eventDrafts,
          )
        : [];
      if (normalizedRecordDraft) {
        normalizedRecordDraft.eventDrafts = normalizedEventDrafts;
      }
      const asksExcludedEmotionScore =
        normalizedRecordDraft &&
        /(幾分|分數|強度|程度)/.test(rawFollowUpQuestion) &&
        normalizedRecordDraft.excludedEmotionTerms.some((term) =>
          rawFollowUpQuestion.includes(term),
        );
      const result = {
        reply,
        followUpQuestion: asksExcludedEmotionScore
          ? ""
          : sanitizeModeFollowUp(mode, rawFollowUpQuestion),
        sources: contextSources,
        suggestedActions: Array.isArray(parsed.suggestedActions)
          ? parsed.suggestedActions.map((item) => String(item).trim()).filter(Boolean).slice(0, 4)
          : [],
        recordDraft: normalizedRecordDraft,
        eventDrafts: normalizedEventDrafts,
        safetyLevel: "normal",
        requiresFixedSafetyUi: false,
        model: DEFAULT_AI_MODEL,
        promptVersion: INNERA_AI_PROMPT_VERSION,
        inputTokens: completion.usage?.prompt_tokens ?? null,
        outputTokens: completion.usage?.completion_tokens ?? null,
      };
      latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
      await succeedUsageAndLog();
      return result;
    } catch (error) {
      if (latencyState.preparationMs === 0) {
        latencyState.preparationMs = elapsedSince(preparationStartedAt);
      }
      if (parseNormalizeStartedAt != null && latencyState.parseNormalizeMs === 0) {
        latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
      }
      const usageWriteStartedAt = Date.now();
      await usageTracker.fail(error, completion);
      latencyState.usageWriteMs += elapsedSince(usageWriteStartedAt);
      logLatency("failed");
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
