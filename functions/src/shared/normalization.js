

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

module.exports = {
  stripMarkdownFence,
  toNumber,
  clamp,
  toCleanString,
  normalizeMoodScore,
};
