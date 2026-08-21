"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { detectInneraSelfHarm } = require("../innera_safety");

const cases = [
  ["我今天真的不想活了", true, "concern"],
  ["最近一直有想死的念頭", true, "concern"],
  ["我想自S", true, "concern"],
  ["我沒有想死，只是今天很累", false, "none"],
  ["我朋友最近一直說他想自殺", false, "none"],
  ["自殺防治專線是多少？", false, "none"],
];

for (const [message, detected, level] of cases) {
  test(message, () => {
    const result = detectInneraSelfHarm(message);
    assert.equal(result.detected, detected);
    assert.equal(result.level, level);
  });
}

test("normalizes spaces and full-width letter evasion", () => {
  assert.equal(detectInneraSelfHarm("我 想 自 s").detected, true);
  assert.equal(detectInneraSelfHarm("我想自Ｓ").detected, true);
});

test("marks immediate self-harm language urgent", () => {
  const result = detectInneraSelfHarm("我現在就想傷害自己");
  assert.equal(result.detected, true);
  assert.equal(result.level, "urgent");
});

test("does not let one negated occurrence hide a later direct statement", () => {
  const result = detectInneraSelfHarm("我原本沒有想死，但我現在想死");
  assert.equal(result.detected, true);
});
