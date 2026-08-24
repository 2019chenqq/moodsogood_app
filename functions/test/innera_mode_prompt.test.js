const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildInneraPrompt,
  inneraModePrompt,
  sanitizeModeFollowUp,
} = require("../innera_mode_prompt");

test("chat mode forbids form-style completeness questions", () => {
  const prompt = inneraModePrompt("emotionalSupport");
  assert.match(prompt, /唯一真實模式/);
  assert.match(prompt, /60～140/);
  assert.match(prompt, /一至兩句整理或展開/);
  assert.match(prompt, /至多提出一個容易回答的問題/);
  assert.match(prompt, /不得因.*缺少.*而補問/);
  assert.match(prompt, /不得把聊天改成逐欄量表流程/);
});

test("record mode limits follow-up to one important gap", () => {
  const prompt = inneraModePrompt("dailyRecord");
  assert.match(prompt, /一次最多詢問一個/);
  assert.match(prompt, /其餘欄位保留 null/);
  assert.match(prompt, /不得依序追問能量、食慾、活動量/);
});

test("builds only core plus the active mode", () => {
  const emotional = buildInneraPrompt("emotionalSupport");
  assert.match(emotional, /Innera AI 共用 Core/);
  assert.match(emotional, /activeMode: emotionalSupport/);
  assert.doesNotMatch(emotional, /activeMode: dailyRecord/);
  assert.doesNotMatch(emotional, /sleepTimeStats/);

  const review = buildInneraPrompt("recentReview");
  assert.match(review, /sleepTimeStats/);
  assert.match(review, /emotionStats/);
  assert.doesNotMatch(review, /bodyMeasurement 只有/);
  assert.doesNotMatch(review, /activeMode: physicalHealth/);
});

test("physical health mode extracts arbitrary symptoms into confirmable events", () => {
  const prompt = inneraModePrompt("physicalHealth");
  assert.match(prompt, /每一個身體症狀/);
  assert.match(prompt, /不限預設症狀名稱/);
  assert.match(prompt, /不同時間.*不同 eventDraft/);
  assert.match(prompt, /確認後才正式儲存 HealthEvent/);
});

test("daily record keeps detailed extraction rules out of other modes", () => {
  const daily = inneraModePrompt("dailyRecord");
  assert.match(daily, /emotionDimensions/);
  assert.match(daily, /不同時間.*不同 eventDraft/);
  assert.match(daily, /bodyMeasurement/);
  assert.match(daily, /diaryText/);
  assert.match(daily, /確認後才能正式儲存/);

  const physical = inneraModePrompt("physicalHealth");
  assert.doesNotMatch(physical, /diaryText/);
  assert.doesNotMatch(physical, /sleepTimeStats/);
});

test("fatigue severity is never reused or inverted as energy", () => {
  const prompt = inneraModePrompt("dailyRecord");
  assert.match(prompt, /疲倦 2 分.*severity:2.*energy_change 保持 null/);
  assert.match(prompt, /疲倦 4 分.*不得填 energy_change:4/);
  assert.match(prompt, /不得反向換算能量/);
  assert.match(prompt, /能量 N 分.*才填 energy_change=N/);
  assert.match(prompt, /每個分數只能綁定它明確修飾的對象/);
});

test("chat mode drops structured scale follow-ups but keeps natural questions", () => {
  assert.equal(sanitizeModeFollowUp("emotionalSupport", "你的能量 1 到 5 分是幾分？"), "");
  assert.equal(
    sanitizeModeFollowUp("emotionalSupport", "今天是事情特別多，還是有哪件事特別消耗你？"),
    "今天是事情特別多，還是有哪件事特別消耗你？",
  );
});
