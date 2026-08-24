"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  sanitizeEmotionalSupportQuestions,
  sanitizeInneraModeQuestions,
} = require("../innera_ai_response");

test("emotionalSupport reply keeps only its first question", () => {
  const reply = "這種害怕確實很不舒服。什麼最能幫助你減緩害怕？你平常有沒有讓自己放鬆的方法？";

  assert.equal(
    sanitizeEmotionalSupportQuestions(reply, ""),
    "這種害怕確實很不舒服。什麼最能幫助你減緩害怕？",
  );
});

test("followUpQuestion removes every question from emotionalSupport reply", () => {
  const reply = "害怕已經影響你想不想繼續外送。你現在最擔心什麼？";

  assert.equal(
    sanitizeEmotionalSupportQuestions(reply, "你覺得什麼最能幫助你減緩害怕？"),
    "害怕已經影響你想不想繼續外送。",
  );
});

test("reply without a question is unchanged", () => {
  const reply = "害怕到影響外送意願，確實會讓人抗拒那種情境。";
  assert.equal(sanitizeEmotionalSupportQuestions(reply, ""), reply);
});

test("statement containing 嗎 or 呢 inside the sentence is not removed", () => {
  const reply = "你提到嗎啡時很謹慎，也記得走廊傳來的呢喃聲。";
  assert.equal(
    sanitizeEmotionalSupportQuestions(reply, "接下來你最想先談哪一部分？"),
    reply,
  );
});

test("terminal Chinese question forms are recognized conservatively", () => {
  assert.equal(
    sanitizeEmotionalSupportQuestions("這讓你感到不舒服嗎。前面發生了什麼呢。", ""),
    "這讓你感到不舒服嗎。",
  );
});

test("dailyRecord, physicalHealth, and recentReview replies are unchanged", () => {
  const reply = "第一個問題？第二個問題？";
  for (const mode of ["dailyRecord", "physicalHealth", "recentReview"]) {
    assert.equal(sanitizeInneraModeQuestions(mode, reply, "另一個問題？"), reply);
  }
});
