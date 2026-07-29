"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { buildSleepTimeStats } = require("../sleep_review_stats");

test("22:00 and 23:00 bedtimes are not classified as frequent late sleep", () => {
  const stats = buildSleepTimeStats([
    { date: "2026-07-26", sleep: { sleepTime: "22:00" } },
    { date: "2026-07-27", sleep: { sleepTime: "23:00" } },
    { date: "2026-07-28", sleep: { sleepTime: "22:30" } },
    { date: "2026-07-29", sleep: { sleepTime: "23:30" } },
  ]);

  assert.equal(stats.validSleepTimeDays, 4);
  assert.equal(stats.typicalSleepTime, "22:45");
  assert.equal(stats.afterMidnightSleepDays, 0);
  assert.equal(stats.frequentAfterMidnightSleep, false);
  assert.deepEqual(stats.afterMidnightSleepDates, []);
});

test("after-midnight sleep is frequent only when at least half of valid days", () => {
  const stats = buildSleepTimeStats([
    { date: "2026-07-26", sleep: { sleepTime: "23:00" } },
    { date: "2026-07-27", sleep: { sleepTime: "01:00" } },
    { date: "2026-07-28", sleep: { sleepTime: "00:30" } },
    { date: "2026-07-29", sleep: { sleepTime: "22:30" } },
  ]);

  assert.equal(stats.validSleepTimeDays, 4);
  assert.equal(stats.afterMidnightSleepDays, 2);
  assert.equal(stats.frequentAfterMidnightSleep, true);
  assert.deepEqual(stats.afterMidnightSleepDates, [
    "2026-07-27",
    "2026-07-28",
  ]);
});

test("invalid or missing sleep times are excluded from the denominator", () => {
  const stats = buildSleepTimeStats([
    { date: "2026-07-26", sleep: { sleepTime: "22:00" } },
    { date: "2026-07-27", sleep: { sleepTime: null } },
    { date: "2026-07-28", sleep: { sleepTime: "25:00" } },
  ]);

  assert.equal(stats.validSleepTimeDays, 1);
  assert.equal(stats.frequentAfterMidnightSleep, false);
  assert.deepEqual(stats.bedtimeEvidence, [
    { date: "2026-07-26", sleepTime: "22:00" },
  ]);
});
