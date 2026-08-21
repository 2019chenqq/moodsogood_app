const test = require("node:test");
const assert = require("node:assert/strict");
const { inneraModePrompt, sanitizeModeFollowUp } = require("../innera_mode_prompt");

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

test("chat mode drops structured scale follow-ups but keeps natural questions", () => {
  assert.equal(sanitizeModeFollowUp("emotionalSupport", "你的能量 1 到 5 分是幾分？"), "");
  assert.equal(
    sanitizeModeFollowUp("emotionalSupport", "今天是事情特別多，還是有哪件事特別消耗你？"),
    "今天是事情特別多，還是有哪件事特別消耗你？",
  );
});
