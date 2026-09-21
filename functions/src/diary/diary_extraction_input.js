"use strict";

function prepareDiaryMessages(input) {
  const messages = (Array.isArray(input) ? input : [])
    .filter((item) => item?.role === "user" || item?.role === "assistant")
    .map((item) => ({ role: item.role, content: String(item.content || "").trim() }))
    .filter((item) => item.content);
  // Reject oversized input explicitly instead of silently losing diary events.
  if (messages.length > 1000 ||
      messages.reduce((total, item) => total + item.content.length, 0) > 120000) {
    throw new RangeError("今日對話內容過長，請分段整理日記；原文未被截短。");
  }
  return messages;
}

module.exports = { prepareDiaryMessages };
