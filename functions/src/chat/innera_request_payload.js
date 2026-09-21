"use strict";

const {
  selectRecentReviewEvidence,
  selectRecentReviewSummary,
} = require("./innera_recent_review_domains");

const adjustmentTypeLabels = {
  added: "新增藥物",
  doseChanged: "劑量調整",
  scheduleChanged: "服用時間調整",
  stopped: "停藥",
  resumed: "恢復使用",
  injected: "已施打",
  injection: "已施打",
};

function compactNumber(value) {
  if (value === null || value === undefined || String(value).trim() === "") {
    return null;
  }
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Number.isInteger(number) ? String(number) : number.toFixed(1);
}

function doseText({ dose, dosePerUnit, pillCount, unit }) {
  const normalizedDose = compactNumber(dose);
  const normalizedDosePerUnit = compactNumber(dosePerUnit);
  const normalizedPillCount = compactNumber(pillCount);
  const normalizedUnit = String(unit || "").trim();
  const suffix = normalizedUnit ? ` ${normalizedUnit}` : "";
  if (normalizedDose !== null) return `${normalizedDose}${suffix}`;
  if (normalizedDosePerUnit !== null && normalizedPillCount !== null) {
    return `${normalizedDosePerUnit}${suffix} × ${normalizedPillCount} 顆`;
  }
  return "未提供劑量";
}

function adjustmentChangeSummary(item) {
  const supplied = String(item.changeSummary || "").trim();
  if (supplied) return supplied;
  const type = String(item.type || "").trim();
  if (type === "stopped") {
    const reason = String(item.stopReason || "").trim();
    return reason ? `停藥（${reason}）` : "停藥";
  }
  if (type === "resumed") return "恢復使用";
  if (type === "injected" || type === "injection") return "已施打";
  if (type === "scheduleChanged") {
    const timesText = (value) => Array.isArray(value) && value.length
      ? value.map((entry) => String(entry).trim()).filter(Boolean).join("、")
      : "未設定";
    return `${timesText(item.oldTimes)} → ${timesText(item.newTimes)}`;
  }
  const oldValue = doseText({
    dose: item.oldDose,
    dosePerUnit: item.oldDosePerUnit,
    pillCount: item.oldPillCount,
    unit: item.oldUnit,
  });
  const newValue = doseText({
    dose: item.newDose,
    dosePerUnit: item.newDosePerUnit,
    pillCount: item.newPillCount,
    unit: item.newUnit,
  });
  if (type === "added") {
    return newValue === "未提供劑量" ? "新增藥物" : newValue;
  }
  if (oldValue !== "未提供劑量" || newValue !== "未提供劑量") {
    return `${oldValue} → ${newValue}`;
  }
  return adjustmentTypeLabels[type] || "藥物調整";
}

function compactRecentMedicationAdjustments(adjustments) {
  if (!Array.isArray(adjustments)) return adjustments;
  return adjustments.map((adjustment) => {
    const source = adjustment && typeof adjustment === "object" ? adjustment : {};
    const date = String(source.date || "").trim();
    const note = String(source.note || "").trim();
    const items = Array.isArray(source.items) ? source.items : [];
    return {
      ...(date ? { date } : {}),
      items: items
        .filter((item) => item && typeof item === "object")
        .map((item) => ({
          name: String(item.name || item.medName || "未命名藥物").trim(),
          type: String(item.type || "").trim(),
          changeSummary: adjustmentChangeSummary(item),
        })),
      ...(note ? { note: note.slice(0, 80) } : {}),
    };
  });
}

function isRecentReviewSummary(value) {
  return value &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    value.period &&
    typeof value.period === "object";
}

function generalRecentReviewContext(context, domainSelection) {
  const source = context && typeof context === "object" ? context : {};
  if (isRecentReviewSummary(source.recentReviewSummary)) {
    return {
      ...(source.mode != null ? { mode: source.mode } : {}),
      ...(source.generatedAt != null ? { generatedAt: source.generatedAt } : {}),
      ...(source.lookbackDays != null ? { lookbackDays: source.lookbackDays } : {}),
      recentReviewSummary: selectRecentReviewSummary(
        source.recentReviewSummary,
        domainSelection,
      ),
      ...(source.recentReviewEvidence && {
        recentReviewEvidence: selectRecentReviewEvidence(
          source.recentReviewEvidence,
          domainSelection,
        ),
      }),
    };
  }
  return {
    ...Object.fromEntries(
      Object.entries(source).filter(
        ([key]) =>
          key !== "recentDailyRecords" &&
          key !== "recentReviewSummary" &&
          key !== "recentReviewEvidence",
      ),
    ),
    ...(Object.hasOwn(source, "recentMedicationAdjustments")
      ? {
          recentMedicationAdjustments: compactRecentMedicationAdjustments(
            source.recentMedicationAdjustments,
          ),
        }
      : {}),
  };
}

function buildInneraContextPayload({
  mode,
  context,
  contextSources,
  recordDraft,
  emotionDimensions,
  specialRecentReviewRequest = false,
  recentReviewDomainSelection,
}) {
  const usesStructuredExtractionInput =
    mode === "dailyRecord" || mode === "physicalHealth";
  const requestContext = mode === "recentReview"
    ? specialRecentReviewRequest
      ? Object.fromEntries(
          Object.entries(context || {}).filter(
            ([key]) =>
              key !== "recentReviewSummary" && key !== "recentReviewEvidence",
          ),
        )
      : generalRecentReviewContext(context, recentReviewDomainSelection)
    : context;
  return {
    mode,
    context: requestContext,
    contextSources,
    ...(usesStructuredExtractionInput
      ? { recordDraft, emotionDimensions }
      : {}),
  };
}

module.exports = {
  buildInneraContextPayload,
  compactRecentMedicationAdjustments,
};
