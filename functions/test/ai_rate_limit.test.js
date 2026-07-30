"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  DEFAULT_LIMITS,
  evaluateAiRateLimit,
} = require("../ai_rate_limit");

test("allows requests and increments both fixed windows", () => {
  const now = Date.UTC(2026, 6, 30, 10, 15, 20);
  const first = evaluateAiRateLimit({}, now);
  const second = evaluateAiRateLimit(first, now + 1000);

  assert.equal(first.allowed, true);
  assert.equal(first.minute.count, 1);
  assert.equal(first.hour.count, 1);
  assert.equal(second.allowed, true);
  assert.equal(second.minute.count, 2);
  assert.equal(second.hour.count, 2);
});

test("rejects the next request after the minute burst limit", () => {
  const now = Date.UTC(2026, 6, 30, 10, 15, 20);
  let state = {};

  for (let index = 0; index < DEFAULT_LIMITS.perMinute; index += 1) {
    const result = evaluateAiRateLimit(state, now + index);
    assert.equal(result.allowed, true);
    state = result;
  }

  const rejected = evaluateAiRateLimit(state, now + 1000);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.limitType, "minute");
  assert.ok(rejected.retryAfterSeconds >= 1);
  assert.ok(rejected.retryAfterSeconds <= 60);
});

test("resets the minute count while preserving the hourly count", () => {
  const firstMinute = Date.UTC(2026, 6, 30, 10, 15, 20);
  const initial = evaluateAiRateLimit({}, firstMinute);
  const nextMinute = evaluateAiRateLimit(initial, firstMinute + 60 * 1000);

  assert.equal(nextMinute.allowed, true);
  assert.equal(nextMinute.minute.count, 1);
  assert.equal(nextMinute.hour.count, 2);
});

test("rejects requests over a custom hourly ceiling", () => {
  const now = Date.UTC(2026, 6, 30, 10, 15, 20);
  const previous = {
    minute: { key: Math.floor(now / 60000), count: 0 },
    hour: { key: Math.floor(now / 3600000), count: 2 },
  };
  const rejected = evaluateAiRateLimit(previous, now, {
    perMinute: 10,
    perHour: 2,
  });

  assert.equal(rejected.allowed, false);
  assert.equal(rejected.limitType, "hour");
  assert.ok(rejected.retryAfterSeconds >= 1);
  assert.ok(rejected.retryAfterSeconds <= 3600);
});
