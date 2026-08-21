const test = require("node:test");
const assert = require("node:assert/strict");
const { alignEventSummaries, normalizeSummaryInput } = require("../innera_event_summaries");

test("summary input keeps valid conversation and all event drafts", () => {
  const input = normalizeSummaryInput({
    messages: [
      { role: "user", content: "下午三點很累" },
      { role: "assistant", content: "有其他不舒服嗎？" },
      { role: "user", content: "還有一點頭痛" },
      { role: "user", content: "也不太想吃東西" },
    ],
    eventDrafts: [{ id: "a" }, { id: "b" }, { id: "c" }],
  });
  assert.equal(input.messages.length, 4);
  assert.deepEqual(input.eventDrafts.map((item) => item.id), ["a", "b", "c"]);
});

test("safety user messages are excluded from ordinary summaries", () => {
  const input = normalizeSummaryInput({
    messages: [{ role: "user", content: "我不想活了" }, { role: "user", content: "晚上有點頭痛" }],
    eventDrafts: [{ id: "evening" }],
    detectSafety: (text) => ({ detected: text.includes("不想活") }),
  });
  assert.deepEqual(input.messages.map((item) => item.content), ["晚上有點頭痛"]);
});

test("summaries align by stable event id instead of response order", () => {
  const drafts = [
    { id: "morning", note: "早上原文", rawUserEntries: [] },
    { id: "noon", note: "中午原文", rawUserEntries: [] },
    { id: "evening", note: "晚上原文", rawUserEntries: [] },
  ];
  const result = alignEventSummaries([
    { eventId: "evening", summary: "晚上開始頭痛。" },
    { eventId: "morning", summary: "早上感到疲累。" },
    { eventId: "noon", summary: "中午精神不錯。" },
  ], drafts);
  assert.deepEqual(result.map((item) => item.eventId), ["morning", "noon", "evening"]);
  assert.equal(result[2].summary, "晚上開始頭痛。");
});

test("missing output falls back only to its matching draft", () => {
  const result = alignEventSummaries([{ eventId: "b", summary: "下午感到疲累。" }], [
    { id: "a", note: "早上頭痛。", rawUserEntries: [] },
    { id: "b", note: "", rawUserEntries: ["下午很累"] },
  ]);
  assert.equal(result[0].summary, "早上頭痛。");
  assert.equal(result[1].summary, "下午感到疲累。");
});
