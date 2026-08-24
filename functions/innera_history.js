"use strict";

function inneraHistoryLimits(mode) {
  return mode === "emotionalSupport"
    ? { messageLimit: 8, characterLimit: 10000 }
    : { messageLimit: 60, characterLimit: 48000 };
}

function buildInneraSafeHistory(history, mode) {
  const normalizedHistory = (Array.isArray(history) ? history : [])
    .map((item) => {
      const role = item && item.role === "user" ? "user" : "assistant";
      const content = String((item && item.content) || "").trim().slice(0, 1600);
      return content ? { role, content } : null;
    })
    .filter(Boolean);
  const { messageLimit, characterLimit } = inneraHistoryLimits(mode);
  const safeHistory = [];
  let historyCharacters = 0;
  for (const item of normalizedHistory.slice(-messageLimit).reverse()) {
    if (safeHistory.length > 0 &&
        historyCharacters + item.content.length > characterLimit) {
      break;
    }
    safeHistory.unshift(item);
    historyCharacters += item.content.length;
  }
  return { safeHistory, historyCharacters };
}

module.exports = { buildInneraSafeHistory, inneraHistoryLimits };
