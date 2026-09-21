const {
  createInneraLatencyState,
  buildInneraLatencyLog,
  elapsedSince,
  buildRecentReviewContextSizeLog,
} = require("./innera_latency");
const { HttpsError } = require("firebase-functions/v2/https");
const { buildSleepTimeStats } = require("./sleep_review_stats");
const { buildEmotionStats } = require("./emotion_review_stats");
const { detectInneraSelfHarm, createInneraSafetyResponse } = require("./innera_safety");
const {
  isFollowUpQuestionRequest,
  isFollowUpSummaryRequest,
  recentReviewChatSchema,
  parseFollowUpQuestionsCompletion,
  parseFollowUpSummaryCompletion,
  createFollowUpSummaryFallbackResponse,
  sanitizeInneraModeQuestions,
  createRecentReviewApiResponse,
  formatRecentReviewMedicationList,
} = require("./innera_ai_response");
const { requireAiCapacity } = require("../ai/access");
const { createAiUsageTracker, AI_QUOTED_POINTS } = require("../ai/ai_usage");
const { db, admin } = require("../config/firebase");
const { DEFAULT_AI_MODEL, openAiApiKey } = require("../config/params");
const { buildInneraSafeHistory } = require("./innera_history");
const OpenAI = require("openai");
const { selectRecentReviewDomains } = require("./innera_recent_review_domains");
const { buildInneraContextPayload } = require("./innera_request_payload");
const { selectInneraChatResponseSchema, createEmotionalSupportApiResponse } = require("./innera_emotional_support");
const {
  followUpQuestionsSchema,
  followUpSummarySchema,
  inneraChatSchema,
  physicalHealthChatSchema,
} = require("./schemas");
const { buildInneraPrompt, sanitizeModeFollowUp } = require("./prompts/innera_mode_prompt");
const { stripMarkdownFence } = require("../shared/normalization");
const { normalizeInneraEventDrafts } = require("../health_events/innera_event_drafts");
const { createPhysicalHealthApiResponse } = require("./innera_physical_health");
const { normalizeInneraRecordDraft } = require("../diary/record_draft");

const INNERA_AI_PROMPT_VERSION = "innera-ai-chat-v25-review-domain-selection";

async function generateInneraAiChatResponse(request) {
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
      return createInneraSafetyResponse({
        existingRecordDraft,
        safetyLevel: hasMedicalUrgency
          ? "medicalUrgency"
          : safetySignal.level === "concern"
            ? "possibleSelfHarm"
            : "imminentDanger",
      });
    }

    const usageFeature =
      mode === "recentReview" ? "recent_review" : "innera_chat";
    const followUpQuestionRequest = isFollowUpQuestionRequest(mode, message);
    const followUpSummaryRequest = isFollowUpSummaryRequest(mode, message);
    const specialRecentReviewRequest = followUpQuestionRequest ||
      followUpSummaryRequest;
    const recentReviewRequestType = followUpQuestionRequest
      ? "follow_up_questions"
      : followUpSummaryRequest
        ? "follow_up_summary"
        : "general_review";
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
      quotedPoints: specialRecentReviewRequest ? 0 : AI_QUOTED_POINTS[usageFeature],
      metadata: {
        mode,
        requestType: recentReviewRequestType,
        accessPolicy: specialRecentReviewRequest ? "follow_up_free_beta" : "standard",
      },
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
      if (mode === "recentReview") {
        console.log("Innera recentReview context size", {
          mode,
          requestType: recentReviewRequestType,
          ...recentReviewContextTelemetry,
          inputTokens: completion?.usage?.prompt_tokens ?? null,
          outputTokens: completion?.usage?.completion_tokens ?? null,
          openAiMs: latencyState.openAiMs,
          totalMs: elapsedSince(latencyState.startedAt),
        });
      }
      logLatency("succeeded");
    };

    let parseNormalizeStartedAt = null;
    let recentReviewContextTelemetry = {};
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
        { isSpecialRecentReview: specialRecentReviewRequest },
      );
      console.log("generateInneraAiChat history prepared", {
        mode,
        safeHistoryLength: safeHistory.length,
        historyCharacters,
      });
      latencyState.safeHistoryCount = safeHistory.length;
      latencyState.historyCharacters = historyCharacters;

      const client = new OpenAI({ apiKey });
      const recentReviewDomainSelection =
        mode === "recentReview" && !specialRecentReviewRequest
          ? selectRecentReviewDomains(message)
          : null;
      const contextPayload = buildInneraContextPayload({
        mode,
        context,
        contextSources,
        recordDraft: existingRecordDraft,
        emotionDimensions,
        specialRecentReviewRequest,
        recentReviewDomainSelection,
      });
      recentReviewContextTelemetry = buildRecentReviewContextSizeLog({
        context: contextPayload.context,
        contextSources,
        safeHistoryCount: safeHistory.length,
        historyCharacters,
        usedV2Summary:
          recentReviewRequestType === "general_review" &&
          Boolean(contextPayload.context?.recentReviewSummary),
        usedLegacyFallback:
          recentReviewRequestType === "general_review" &&
          !contextPayload.context?.recentReviewSummary,
        selectedDomains:
          recentReviewDomainSelection?.selectedDomains || [],
        usedDomainFallback:
          recentReviewDomainSelection?.usedDomainFallback || false,
        fullSummary: context?.recentReviewSummary,
      });
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
              : followUpSummaryRequest
                ? "follow_up_summary_response"
              : mode === "emotionalSupport"
                ? "innera_emotional_support_response"
                : mode === "physicalHealth"
                  ? "innera_physical_health_response"
                  : mode === "recentReview" && !specialRecentReviewRequest
                    ? "innera_recent_review_response"
                : "innera_chat_response",
            strict: true,
            schema: selectInneraChatResponseSchema({
              mode,
              followUpQuestionRequest,
              followUpSummaryRequest,
              followUpQuestionsSchema,
              followUpSummarySchema,
              inneraChatSchema,
              physicalHealthChatSchema,
              recentReviewChatSchema,
              specialRecentReviewRequest,
            }),
          },
        },
        messages: [
          {
            role: "system",
            content: followUpSummaryRequest
              ? `${buildInneraPrompt(mode)}\nThis special follow-up summary request uses its dedicated response schema. Return the summary fields directly; do not wrap them in reply.`
              : buildInneraPrompt(mode),
          },
          {
            role: "user",
            content: JSON.stringify(contextPayload),
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

      if (followUpSummaryRequest) {
        const summaryResult = parseFollowUpSummaryCompletion(completion);
        const responseResult = summaryResult.parsed ||
          createFollowUpSummaryFallbackResponse().parsed;
        if (!summaryResult.parsed) {
          console.warn("generateInneraAiChat follow-up summary fallback", {
            requestId: usageTracker.requestId,
            reason: summaryResult.failure,
            finishReason: summaryResult.diagnostics?.finishReason,
            refused: summaryResult.diagnostics?.refused,
          });
        }
        latencyState.parseNormalizeMs = elapsedSince(parseNormalizeStartedAt);
        await succeedUsageAndLog();
        return {
          ...responseResult,
          sources: [],
          eventDrafts: [],
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
          { mode, latestMessage: message },
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

      if (mode === "recentReview" && !specialRecentReviewRequest) {
        const result = createRecentReviewApiResponse({
          reply: formatRecentReviewMedicationList(message, context, reply),
          followUpQuestion: rawFollowUpQuestion,
          contextSources,
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
            images.length ? existingRecordDraft : parsed.recordDraft,
            existingRecordDraft,
            emotionDimensions,
            message,
          )
        : null;
      const normalizedEventDrafts = supportsDailyRecordDraft
        ? normalizeInneraEventDrafts(
            images.length ? existingRecordDraft.eventDrafts : parsed.eventDrafts,
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
}

module.exports = {
  generateInneraAiChatResponse,
};
