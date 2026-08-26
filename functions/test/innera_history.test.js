"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildInneraSafeHistory,
  inneraHistoryLimits,
} = require("../innera_history");

function messages(count, content = (index) => `訊息 ${index}`) {
  return Array.from({ length: count }, (_, index) => ({
    role: index % 2 === 0 ? "user" : "assistant",
    content: content(index),
  }));
}

test("short emotional support history remains intact", () => {
  const history = messages(4);
  const result = buildInneraSafeHistory(history, "emotionalSupport");
  assert.deepEqual(result.safeHistory, history);
  assert.equal(result.historyCharacters, history.reduce(
    (total, item) => total + item.content.length,
    0,
  ));
});

test("medium emotional support history keeps the latest eight messages", () => {
  const history = messages(10, (index) => index === 9
    ? "他後來又說，剛剛那件事不是我的錯。"
    : `對話 ${index}`);
  const result = buildInneraSafeHistory(history, "emotionalSupport");
  assert.deepEqual(result.safeHistory, history.slice(-8));
  assert.equal(result.safeHistory.at(-1).content, "他後來又說，剛剛那件事不是我的錯。");
});

test("long emotional support history is capped without crashing", () => {
  const history = messages(42);
  const result = buildInneraSafeHistory(history, "emotionalSupport");
  assert.equal(result.safeHistory.length, 8);
  assert.deepEqual(result.safeHistory, history.slice(-8));
  assert.ok(result.historyCharacters <= 10000);
});

test("each history message remains capped at 1600 characters", () => {
  const result = buildInneraSafeHistory([
    { role: "user", content: `  ${"甲".repeat(1700)}  ` },
  ], "emotionalSupport");
  assert.equal(result.safeHistory[0].content.length, 1600);
});

test("daily record and physical health retain the existing history limits", () => {
  for (const mode of ["dailyRecord", "physicalHealth"]) {
    assert.deepEqual(inneraHistoryLimits(mode), {
      messageLimit: 60,
      characterLimit: 48000,
    });
    const byMessageCount = buildInneraSafeHistory(messages(65), mode);
    assert.equal(byMessageCount.safeHistory.length, 60);
    assert.deepEqual(byMessageCount.safeHistory, messages(65).slice(-60));

    const byCharacterCount = buildInneraSafeHistory(
      messages(60, () => "字".repeat(1000)),
      mode,
    );
    assert.equal(byCharacterCount.safeHistory.length, 48);
    assert.equal(byCharacterCount.historyCharacters, 48000);
  }
});

test("general recent review keeps the latest eight messages", () => {
  const history = messages(24, (index) => index === 22
    ? "最近睡眠有什麼變化？"
    : index === 23
      ? "那情緒呢？"
      : `回顧對話 ${index}`);
  const result = buildInneraSafeHistory(history, "recentReview");
  assert.deepEqual(inneraHistoryLimits("recentReview"), {
    messageLimit: 8,
    characterLimit: 8000,
  });
  assert.deepEqual(result.safeHistory, history.slice(-8));
  assert.equal(result.safeHistory.at(-2).content, "最近睡眠有什麼變化？");
  assert.equal(result.safeHistory.at(-1).content, "那情緒呢？");
});

test("general recent review also enforces the 8000-character limit", () => {
  const result = buildInneraSafeHistory(
    messages(20, () => "字".repeat(1200)),
    "recentReview",
  );
  assert.equal(result.safeHistory.length, 6);
  assert.equal(result.historyCharacters, 7200);
});

test("special recent review requests retain the existing history limits", () => {
  const options = { isSpecialRecentReview: true };
  assert.deepEqual(inneraHistoryLimits("recentReview", options), {
    messageLimit: 60,
    characterLimit: 48000,
  });
  const byMessageCount = buildInneraSafeHistory(
    messages(65),
    "recentReview",
    options,
  );
  assert.equal(byMessageCount.safeHistory.length, 60);
  const byCharacterCount = buildInneraSafeHistory(
    messages(60, () => "字".repeat(1000)),
    "recentReview",
    options,
  );
  assert.equal(byCharacterCount.safeHistory.length, 48);
  assert.equal(byCharacterCount.historyCharacters, 48000);
});

test("emotional support exposes the intended limits", () => {
  assert.deepEqual(inneraHistoryLimits("emotionalSupport"), {
    messageLimit: 8,
    characterLimit: 10000,
  });
});
