"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeInneraEventDrafts,
  sanitizeExplicitStateChangePatch,
} = require("../innera_event_drafts");

const event = (id, timeContext, symptoms) => ({
  id,
  eventTime: null,
  timeContext,
  timePrecision: "approximate",
  symptoms,
  stateChanges: {},
  rawUserEntries: [],
  note: symptoms.map((item) => item?.name || item).join("、"),
});

test("keeps existing events when a different event is added", () => {
  const result = normalizeInneraEventDrafts(
    [event("afternoon", "下午", ["疲倦"])],
    [event("morning", "早上", ["頭痛"])],
  );
  assert.equal(result.length, 2);
});

test("merges a follow-up into the same event id", () => {
  const result = normalizeInneraEventDrafts(
    [event("afternoon", "下午三點", ["頭痛"])],
    [event("afternoon", "下午三點", ["疲倦"])],
  );
  assert.equal(result.length, 1);
  assert.deepEqual(result[0].symptoms, [
    { name: "疲倦", severity: null },
    { name: "頭痛", severity: null },
  ]);
});

test("merges different ids that point to the same event minute", () => {
  const atNoon = "2026-08-24T12:00:00.000Z";
  const existing = {
    ...event("now", "now", [{ name: "心悸", severity: 4 }]),
    eventTime: atNoon,
  };
  const patch = {
    ...event("current-status", "現在", [{ name: "心悸", severity: 1 }]),
    eventTime: atNoon,
  };

  const result = normalizeInneraEventDrafts([patch], [existing]);

  assert.equal(result.length, 1);
  assert.equal(result[0].id, "now");
  assert.deepEqual(result[0].symptoms, [{ name: "心悸", severity: 1 }]);
});

test("keeps explicit symptom severity and never fabricates a missing score", () => {
  const result = normalizeInneraEventDrafts([
    event("afternoon", "下午三點", [
      { name: "心悸", severity: 4 },
      { name: "反胃", severity: null },
    ]),
  ], []);
  assert.deepEqual(result[0].symptoms, [
    { name: "心悸", severity: 4 },
    { name: "反胃", severity: null },
  ]);
});

test("rejects an AI energy score copied from explicit fatigue severity", () => {
  assert.deepEqual(
    sanitizeExplicitStateChangePatch(
      { energy_change: 4, appetite_change: 2 },
      "我疲倦 4 分",
    ),
    { appetite_change: 2 },
  );
});

test("keeps energy only when the user explicitly scores energy", () => {
  assert.deepEqual(
    sanitizeExplicitStateChangePatch(
      { energy_change: 2 },
      "我疲倦 4 分，能量 2 分",
    ),
    { energy_change: 2 },
  );
});

test("physical health merges a one-minute continuation into the latest event", () => {
  const existing = {
    ...event("palpitation", "剛剛", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T16:14:00.000Z",
  };
  const patch = {
    ...event("tremor", "現在", [{ name: "手抖", severity: null }]),
    eventTime: "2026-08-24T16:15:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "physicalHealth",
    latestMessage: "現在又有點手抖",
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].id, "palpitation");
  assert.equal(result[0].eventTime, existing.eventTime);
  assert.deepEqual(result[0].symptoms, [
    { name: "心悸", severity: null },
    { name: "手抖", severity: null },
  ]);
});

test("physical health does not merge within five minutes when a new time is explicit", () => {
  const existing = {
    ...event("first", "下午三點", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T15:00:00.000Z",
  };
  const patch = {
    ...event("second", "下午三點零五分", [{ name: "手抖", severity: null }]),
    eventTime: "2026-08-24T15:05:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "physicalHealth",
    latestMessage: "下午三點零五分開始手抖",
  });
  assert.equal(result.length, 2);
});

test("physical health does not merge incompatible time contexts", () => {
  const existing = {
    ...event("morning", "早上", [{ name: "頭痛", severity: null }]),
    eventTime: "2026-08-24T08:00:00.000Z",
  };
  const patch = {
    ...event("afternoon", "下午", [{ name: "噁心", severity: null }]),
    eventTime: "2026-08-24T08:04:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "physicalHealth",
    latestMessage: "現在又開始噁心",
  });
  assert.equal(result.length, 2);
});

test("physical health explicit continuation updates the prior exact event", () => {
  const existing = {
    ...event("at-1500", "下午三點", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T15:00:00.000Z",
    timePrecision: "exact",
  };
  const patch = {
    ...event("follow-up", "現在", [{ name: "心悸", severity: 4 }]),
    eventTime: "2026-08-24T16:00:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "physicalHealth",
    latestMessage: "剛剛那個心悸大概4分",
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].eventTime, existing.eventTime);
  assert.deepEqual(result[0].symptoms, [{ name: "心悸", severity: 4 }]);
});

test("physical health keeps a clearly separate recurrence", () => {
  const existing = {
    ...event("first-wave", "剛剛", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T16:14:00.000Z",
  };
  const patch = {
    ...event("second-wave", "現在", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T16:15:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "physicalHealth",
    latestMessage: "剛剛心悸，過了半小時又出現一次",
  });
  assert.equal(result.length, 2);
});

test("daily record does not use physical health proximity merging", () => {
  const existing = {
    ...event("first", "現在", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T16:14:00.000Z",
  };
  const patch = {
    ...event("second", "現在", [{ name: "手抖", severity: null }]),
    eventTime: "2026-08-24T16:15:00.000Z",
  };
  const result = normalizeInneraEventDrafts([patch], [existing], {
    mode: "dailyRecord",
    latestMessage: "現在又有點手抖",
  });
  assert.equal(result.length, 2);
});
