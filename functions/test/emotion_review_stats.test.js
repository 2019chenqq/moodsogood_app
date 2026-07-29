"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { buildEmotionStats } = require("../emotion_review_stats");

test("frequency is based on occurrence days rather than intensity", () => {
  const stats = buildEmotionStats([
    {
      date: "2026-07-16",
      emotions: [
        { name: "興奮", value: 3 },
        { name: "煩躁", value: 5 },
      ],
    },
    { date: "2026-07-17", emotions: [{ name: "興奮", value: 4 }] },
    { date: "2026-07-18", emotions: [{ name: "興奮", value: 5 }] },
    { date: "2026-07-19", emotions: [{ name: "憤怒", value: 5 }] },
    { date: "2026-07-20", emotions: [{ name: "興奮", value: 4 }] },
  ]);

  assert.equal(stats.daysWithEmotionData, 5);
  assert.deepEqual(stats.mostFrequentEmotions, ["興奮"]);
  assert.equal(stats.emotions[0].name, "興奮");
  assert.equal(stats.emotions[0].occurrenceDays, 4);
  assert.equal(stats.emotions[0].frequent, true);
  assert.equal(
    stats.emotions.find((item) => item.name === "煩躁").occurrenceDays,
    1,
  );
  assert.equal(
    stats.emotions.find((item) => item.name === "煩躁").frequent,
    false,
  );
});

test("duplicate emotions on one date count as one occurrence day", () => {
  const stats = buildEmotionStats([
    {
      date: "2026-07-16",
      emotions: [
        { name: "興奮", value: 3 },
        { name: "興奮", value: 5 },
      ],
    },
    { date: "2026-07-17", emotions: [{ name: "平靜", value: 4 }] },
  ]);

  const excited = stats.emotions.find((item) => item.name === "興奮");
  assert.equal(excited.occurrenceDays, 1);
  assert.deepEqual(excited.intensitySamples, [5]);
});
