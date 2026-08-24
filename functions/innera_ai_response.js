"use strict";

function stripMarkdownFence(text) {
  return String(text || "")
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "")
    .trim();
}

function isEmotionalSupportQuestion(sentence) {
  const value = String(sentence || "").trim();
  if (!value) return false;
  if (/[？?]/.test(value)) return true;

  const withoutClosingPunctuation = value.replace(/[。！!…]+$/u, "").trim();
  if (/嗎$/u.test(withoutClosingPunctuation)) return true;
  return /(?:什麼|怎麼|為什麼|哪(?:一|個|些|裡|邊)?|如何|是否|有沒有|能不能|可不可以|要不要|願不願意|還是)[^。！？?]*呢$/u
    .test(withoutClosingPunctuation);
}

function splitEmotionalSupportSentences(reply) {
  return String(reply || "")
    .match(/[^。！？?\n]+[。！？?]+|[^。！？?\n]+(?=\n|$)/gu) || [];
}

function joinEmotionalSupportSentences(sentences) {
  return sentences
    .map((sentence) => sentence.trim())
    .filter(Boolean)
    .join("")
    .trim();
}

function sanitizeEmotionalSupportQuestions(reply, followUpQuestion) {
  const originalReply = String(reply || "");
  const sentences = splitEmotionalSupportSentences(reply);
  if (!sentences.some(isEmotionalSupportQuestion)) return originalReply;
  const hasFollowUpQuestion = String(followUpQuestion || "").trim().length > 0;
  let keptQuestion = false;

  return joinEmotionalSupportSentences(sentences.filter((sentence) => {
    if (!isEmotionalSupportQuestion(sentence)) return true;
    if (hasFollowUpQuestion || keptQuestion) return false;
    keptQuestion = true;
    return true;
  }));
}

function sanitizeInneraModeQuestions(mode, reply, followUpQuestion) {
  if (mode !== "emotionalSupport") return String(reply || "");
  return sanitizeEmotionalSupportQuestions(reply, followUpQuestion);
}

function parseInneraChatCompletion(completion) {
  const choice = completion?.choices?.[0];
  const rawText = String(choice?.message?.content || "").trim();
  const diagnostics = {
    finishReason: choice?.finish_reason || null,
    refused: Boolean(choice?.message?.refusal),
    rawTextLength: rawText.length,
  };

  if (!rawText) {
    return {
      parsed: null,
      reply: "",
      failure: "empty_response",
      diagnostics,
    };
  }

  let parsed;
  try {
    parsed = JSON.parse(stripMarkdownFence(rawText));
  } catch (_) {
    return {
      parsed: null,
      reply: "",
      failure: "invalid_json",
      diagnostics,
    };
  }

  const reply = String(parsed?.reply || "").trim().slice(0, 6000);
  return {
    parsed,
    reply,
    failure: reply ? null : "missing_reply",
    diagnostics,
  };
}

function jsonObjectCandidates(text) {
  const source = String(text || "").trim();
  const candidates = [];
  const unfenced = stripMarkdownFence(source);
  if (unfenced) candidates.push(unfenced);

  for (let start = 0; start < source.length; start += 1) {
    if (source[start] !== "{") continue;
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let index = start; index < source.length; index += 1) {
      const character = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character === "\\") {
          escaped = true;
        } else if (character === '"') {
          inString = false;
        }
        continue;
      }
      if (character === '"') {
        inString = true;
      } else if (character === "{") {
        depth += 1;
      } else if (character === "}") {
        depth -= 1;
        if (depth === 0) {
          candidates.push(source.slice(start, index + 1));
          break;
        }
      }
    }
  }
  return [...new Set(candidates)];
}

function parseJsonObjectFromText(text) {
  for (const candidate of jsonObjectCandidates(text)) {
    try {
      const value = JSON.parse(candidate);
      if (value && typeof value === "object" && !Array.isArray(value)) {
        return value;
      }
    } catch (_) {
      // Try the next balanced JSON object without logging health content.
    }
  }
  return null;
}

function normalizeStringArray(value) {
  if (!Array.isArray(value)) return null;
  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizeFollowUpSummaryReply(reply) {
  const value = parseJsonObjectFromText(reply);
  if (!value) {
    return { reply: "", failure: "invalid_follow_up_summary_json" };
  }

  const keyChanges = normalizeStringArray(value.keyChanges);
  const discussionPriorities = normalizeStringArray(value.discussionPriorities);
  const timelineRelations = normalizeStringArray(value.timelineRelations);
  const medicationSubjectiveSummaries = value.medicationSubjectiveSummaries == null
    ? []
    : normalizeStringArray(value.medicationSubjectiveSummaries);
  const dataLimitations = normalizeStringArray(value.dataLimitations);
  const userSharedNotes = value.userSharedNotes == null
    ? (value.userReportedConcerns == null
      ? []
      : normalizeStringArray(value.userReportedConcerns))
    : normalizeStringArray(value.userSharedNotes);

  if (!keyChanges || keyChanges.length < 3 || keyChanges.length > 5) {
    return { reply: "", failure: "invalid_follow_up_key_changes" };
  }
  if (!discussionPriorities || !timelineRelations ||
      !medicationSubjectiveSummaries ||
      !userSharedNotes || !dataLimitations) {
    return { reply: "", failure: "invalid_follow_up_summary_arrays" };
  }

  return {
    reply: JSON.stringify({
      keyChanges,
      discussionPriorities,
      timelineRelations,
      medicationSubjectiveSummaries,
      userSharedNotes,
      userReportedConcerns: userSharedNotes,
      dataLimitations,
    }),
    failure: null,
  };
}

function parseFollowUpSummaryCompletion(completion) {
  const choice = completion?.choices?.[0];
  const rawText = String(choice?.message?.content || "").trim();
  const diagnostics = {
    finishReason: choice?.finish_reason || null,
    refused: Boolean(choice?.message?.refusal),
    rawTextLength: rawText.length,
  };
  if (!rawText) {
    return {
      parsed: null,
      reply: "",
      failure: "empty_follow_up_summary_response",
      diagnostics,
    };
  }

  const normalized = normalizeFollowUpSummaryReply(rawText);
  if (!normalized.reply) {
    return {
      parsed: null,
      reply: "",
      failure: normalized.failure,
      diagnostics,
    };
  }
  return {
    parsed: {
      reply: normalized.reply,
      followUpQuestion: null,
      sources: [],
      suggestedActions: [],
      recordDraft: null,
      safetyLevel: "normal",
      requiresFixedSafetyUi: false,
    },
    reply: normalized.reply,
    failure: null,
    diagnostics,
  };
}

function normalizeFollowUpQuestionsReply(reply) {
  const value = parseJsonObjectFromText(reply);
  if (!value) {
    return { reply: "", failure: "invalid_follow_up_questions_json" };
  }
  const questions = normalizeStringArray(value.questions);
  if (!questions || questions.length > 4) {
    return { reply: "", failure: "invalid_follow_up_questions_array" };
  }
  return {
    reply: JSON.stringify({ questions }),
    failure: null,
  };
}

function parseFollowUpQuestionsCompletion(completion) {
  const choice = completion?.choices?.[0];
  const rawText = String(choice?.message?.content || "").trim();
  const diagnostics = {
    finishReason: choice?.finish_reason || null,
    refused: Boolean(choice?.message?.refusal),
    rawTextLength: rawText.length,
  };
  if (!rawText) {
    return {
      parsed: null,
      reply: "",
      failure: "empty_follow_up_questions_response",
      diagnostics,
    };
  }
  const normalized = normalizeFollowUpQuestionsReply(rawText);
  if (!normalized.reply) {
    return {
      parsed: null,
      reply: "",
      failure: normalized.failure,
      diagnostics,
    };
  }
  return {
    parsed: {
      reply: normalized.reply,
      followUpQuestion: null,
      sources: [],
      suggestedActions: [],
      recordDraft: null,
      safetyLevel: "normal",
      requiresFixedSafetyUi: false,
    },
    reply: normalized.reply,
    failure: null,
    diagnostics,
  };
}

function isFollowUpQuestionRequest(mode, message) {
  return mode === "recentReview" && String(message || "").includes("回診摘要補問");
}

function isFollowUpSummaryRequest(mode, message) {
  return mode === "recentReview" &&
    String(message || "").includes("產生可供回診使用的資料摘要");
}

function createNoFollowUpQuestionsResponse() {
  return {
    parsed: {
      reply: '{"questions":[]}',
      followUpQuestion: null,
      suggestedActions: [],
      recordDraft: null,
    },
    reply: '{"questions":[]}',
  };
}

function createFollowUpSummaryFallbackResponse() {
  // Keep the transport contract valid. The App sees the intentionally empty
  // keyChanges and builds its deterministic fallback from local structured data.
  const reply = JSON.stringify({
    keyChanges: [],
    discussionPriorities: [],
    timelineRelations: [],
    medicationSubjectiveSummaries: [],
    userSharedNotes: [],
    userReportedConcerns: [],
    dataLimitations: [],
  });
  return {
    parsed: {
      reply,
      followUpQuestion: null,
      sources: [],
      suggestedActions: [],
      recordDraft: null,
      safetyLevel: "normal",
      requiresFixedSafetyUi: false,
    },
    reply,
  };
}

function mergeCompletionUsage(completions) {
  const attempts = (Array.isArray(completions) ? completions : []).filter(Boolean);
  if (attempts.length === 0) return undefined;
  if (attempts.length === 1) return attempts[0];

  const usage = attempts.reduce(
    (total, completion) => {
      const current = completion?.usage || {};
      total.prompt_tokens += Math.max(0, Number(current.prompt_tokens) || 0);
      total.completion_tokens += Math.max(0, Number(current.completion_tokens) || 0);
      total.total_tokens += Math.max(0, Number(current.total_tokens) || 0);
      total.prompt_tokens_details.cached_tokens += Math.max(
        0,
        Number(current.prompt_tokens_details?.cached_tokens) || 0,
      );
      return total;
    },
    {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      prompt_tokens_details: { cached_tokens: 0 },
    },
  );

  return {
    ...attempts[attempts.length - 1],
    usage,
  };
}

module.exports = {
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
  sanitizeEmotionalSupportQuestions,
  sanitizeInneraModeQuestions,
};
