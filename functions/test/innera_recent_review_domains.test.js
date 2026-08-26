"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  selectRecentReviewDomains,
  selectRecentReviewSummary,
} = require("../innera_recent_review_domains");

const cases = [
  ["最近睡眠有什麼變化？", ["sleep"], false],
  ["最近最常出現什麼情緒？", ["emotion"], false],
  ["最近身體症狀如何？", ["symptom"], false],
  ["我最近有沒有調藥？", ["medication"], false],
  ["最近經期有什麼紀錄？", ["period"], false],
  ["最近睡眠和情緒如何？", ["sleep", "emotion"], false],
  ["最近整體有什麼變化？", ["overall"], false],
  ["最近怎麼樣？", ["overall"], true],
  ["那情緒呢？", ["emotion"], false],
  ["藥物呢？", ["medication"], false],
];

for (const [message, selectedDomains, usedDomainFallback] of cases) {
  test(`selects ${selectedDomains.join(",")} for ${message}`, () => {
    assert.deepEqual(selectRecentReviewDomains(message), {
      selectedDomains,
      usedDomainFallback,
    });
  });
}

test("single and multiple domains retain only period plus mapped summary data", () => {
  const full = {
    period: { lookbackDays: 30 },
    sleep: { recordedDays: 30 },
    emotions: [{ name: "private" }],
    symptoms: [{ name: "private" }],
    states: { energy: 3 },
    medications: [{ name: "private" }],
    medicationChanges: [{ name: "private" }],
    periodCycles: [{ startDate: "private" }],
  };
  assert.deepEqual(
    selectRecentReviewSummary(full, selectRecentReviewDomains("睡眠如何？")),
    { period: full.period, sleep: full.sleep },
  );
  assert.deepEqual(
    selectRecentReviewSummary(
      full,
      selectRecentReviewDomains("睡眠和情緒如何？"),
    ),
    { period: full.period, sleep: full.sleep, emotions: full.emotions },
  );
  assert.deepEqual(
    selectRecentReviewSummary(full, selectRecentReviewDomains("有沒有調藥？")),
    {
      period: full.period,
      medications: full.medications,
      medicationChanges: full.medicationChanges,
    },
  );
});

test("overall and uncertain messages retain the complete summary", () => {
  const full = { period: {}, sleep: {}, emotions: [], symptoms: [] };
  assert.equal(
    selectRecentReviewSummary(full, selectRecentReviewDomains("整體如何？")),
    full,
  );
  assert.equal(
    selectRecentReviewSummary(full, selectRecentReviewDomains("最近怎麼樣？")),
    full,
  );
});
