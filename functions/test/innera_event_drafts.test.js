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

test("physical health continuity keeps one stable active event without duplicate propagation", () => {
  const at1515 = {
    ...event("active", "現在", [{ name: "心悸", severity: null }]),
    eventTime: "2026-08-24T15:15:00.000Z",
  };
  const withTremor = normalizeInneraEventDrafts([
    {
      ...event("model-tremor", "現在", [{ name: "手抖", severity: null }]),
      eventTime: "2026-08-24T15:16:00.000Z",
    },
  ], [at1515], {
    mode: "physicalHealth",
    latestMessage: "而且有點手抖",
  });
  const withNausea = normalizeInneraEventDrafts([
    withTremor[0],
    {
      ...event("duplicate-nausea", "剛剛", [{ name: "噁心反胃", severity: null }]),
      eventTime: "2026-08-24T15:17:00.000Z",
    },
  ], withTremor, {
    mode: "physicalHealth",
    latestMessage: "剛剛也有點噁心",
  });

  assert.equal(withNausea.length, 1);
  assert.equal(withNausea[0].id, "active");
  assert.equal(withNausea[0].eventTime, at1515.eventTime);
  assert.deepEqual(withNausea[0].symptoms.map((item) => item.name), [
    "心悸", "手抖", "噁心反胃",
  ]);
});

test("reused id with a different explicit time creates a new event", () => {
  const active = {
    ...event("active", "現在", ["心悸", "手抖", "噁心反胃"]),
    eventTime: "2026-08-24T15:15:00.000Z",
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("active", "早上8點", [
        { name: "心悸", severity: 3 },
        { name: "手抖", severity: 3 },
        { name: "噁心反胃", severity: 3 },
      ]),
      eventTime: "2026-08-24T08:00:00.000Z",
      timePrecision: "exact",
    },
  ], [active], {
    mode: "physicalHealth",
    latestMessage: "早上8點心悸，程度3分",
  });

  assert.equal(result.length, 2);
  assert.equal(result[0].id, "active");
  assert.equal(result[0].eventTime, active.eventTime);
  assert.deepEqual(result[0].symptoms.map((item) => item.name), [
    "心悸", "手抖", "噁心反胃",
  ]);
  const morning = result.find((item) => item.id !== "active");
  assert.equal(morning.eventTime, "2026-08-24T08:00:00.000Z");
  assert.deepEqual(morning.symptoms, [{ name: "心悸", severity: 3 }]);
});

test("current-time symptom never moves into a historical exact event", () => {
  const current = {
    ...event("current", "現在", ["手抖"]),
    eventTime: "2026-08-24T15:15:00.000Z",
  };
  const morning = {
    ...event("morning", "早上8點", [{ name: "心悸", severity: 3 }]),
    eventTime: "2026-08-24T08:00:00.000Z",
    timePrecision: "exact",
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("morning", "剛剛", ["頭痛"]),
      eventTime: "2026-08-24T15:18:00.000Z",
    },
  ], [current, morning], {
    mode: "physicalHealth",
    latestMessage: "剛剛頭痛",
  });

  assert.equal(result.find((item) => item.id === "morning").eventTime, morning.eventTime);
  assert.equal(
    result.find((item) => item.id === "morning").symptoms.some((item) => item.name === "頭痛"),
    false,
  );
  assert.equal(result.some((item) =>
    item.id !== "morning" && item.symptoms.some((symptom) => symptom.name === "頭痛")
  ), true);
});

test("same symptom at explicit morning and afternoon times stays separate", () => {
  const morning = {
    ...event("palpitation", "早上8點", ["心悸"]),
    eventTime: "2026-08-24T08:00:00.000Z",
    timePrecision: "exact",
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("palpitation", "下午2點", ["心悸"]),
      eventTime: "2026-08-24T14:00:00.000Z",
      timePrecision: "exact",
    },
  ], [morning], {
    mode: "physicalHealth",
    latestMessage: "下午2點又心悸",
  });

  assert.equal(result.length, 2);
  assert.deepEqual(result.map((item) => item.eventTime), [
    "2026-08-24T08:00:00.000Z",
    "2026-08-24T14:00:00.000Z",
  ]);
});

test("explicit correction may update only its targeted event time", () => {
  const corrected = {
    ...event("latest", "下午3點", ["心悸"]),
    eventTime: "2026-08-24T15:00:00.000Z",
    timePrecision: "exact",
  };
  const unrelated = {
    ...event("morning", "早上8點", ["頭痛"]),
    eventTime: "2026-08-24T08:00:00.000Z",
    timePrecision: "exact",
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("latest", "下午2點", ["心悸"]),
      eventTime: "2026-08-24T14:00:00.000Z",
      timePrecision: "exact",
    },
  ], [unrelated, corrected], {
    mode: "physicalHealth",
    latestMessage: "剛剛那筆其實是下午2點，不是3點",
  });

  assert.equal(result.find((item) => item.id === "latest").eventTime,
    "2026-08-24T14:00:00.000Z");
  assert.equal(result.find((item) => item.id === "morning").eventTime,
    unrelated.eventTime);
});

test("physical health canonicalizes symptom aliases within one event", () => {
  const existing = {
    ...event("active", null, [{ name: "噁心", severity: null }]),
    eventTime: "2026-08-26T17:30:00.000Z",
    rawUserEntries: ["我有點噁心"],
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("active", null, [{ name: "反胃", severity: null }]),
      eventTime: "2026-08-26T17:30:00.000Z",
      rawUserEntries: ["還是有點反胃"],
    },
  ], [existing], {
    mode: "physicalHealth",
    latestMessage: "還是有點反胃",
  });

  assert.equal(result.length, 1);
  assert.deepEqual(result[0].symptoms, [
    { name: "噁心反胃", severity: null },
  ]);
});

test("physical health completeness restores every explicit symptom", () => {
  const result = normalizeInneraEventDrafts([
    event("now", "現在", [{ name: "心悸", severity: null }]),
  ], [], {
    mode: "physicalHealth",
    latestMessage: "我現在心悸、手抖，胃有點痛，還有點反胃",
  });

  assert.deepEqual(result[0].symptoms, [
    { name: "心悸", severity: null },
    { name: "手抖", severity: null },
    { name: "噁心反胃", severity: null },
    { name: "胃痛", severity: null },
  ]);
});

test("physical health binds an explicit score only to its symptom", () => {
  const result = normalizeInneraEventDrafts([
    event("now", "現在", [{ name: "心悸", severity: 4 }]),
  ], [], {
    mode: "physicalHealth",
    latestMessage: "心悸4分，手抖，胃有點痛",
  });
  const severities = Object.fromEntries(
    result[0].symptoms.map((item) => [item.name, item.severity]),
  );

  assert.deepEqual(severities, {
    "心悸": 4,
    "手抖": null,
    "胃痛": null,
  });
});

test("explicit recurrence inherits one unambiguous prior symptom", () => {
  const prior = {
    ...event("recent", "剛剛", [{ name: "頭痛", severity: null }]),
    eventTime: "2026-08-26T17:30:00.000Z",
    rawUserEntries: ["剛剛頭痛"],
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("night", "晚上9點", []),
      eventTime: "2026-08-26T21:00:00.000Z",
      timePrecision: "exact",
      note: "晚上9點又痛了一次",
    },
  ], [prior], {
    mode: "physicalHealth",
    latestMessage: "晚上9點又痛了一次",
  });

  assert.equal(result.length, 2);
  assert.deepEqual(result[0].symptoms, prior.symptoms);
  assert.deepEqual(result[1].symptoms, [
    { name: "頭痛", severity: null },
  ]);
});

test("ambiguous recurrence does not inherit multiple prior symptoms", () => {
  const prior = {
    ...event("recent", "剛剛", ["頭痛", "心悸"]),
    eventTime: "2026-08-26T17:30:00.000Z",
    rawUserEntries: ["剛剛頭痛又心悸"],
  };
  const result = normalizeInneraEventDrafts([
    {
      ...event("night", "晚上9點", []),
      eventTime: "2026-08-26T21:00:00.000Z",
      timePrecision: "exact",
      note: "晚上9點又不舒服",
    },
  ], [prior], {
    mode: "physicalHealth",
    latestMessage: "晚上9點又不舒服",
  });
  const night = result.find((item) => item.id === "night");

  assert.deepEqual(night.symptoms, []);
  assert.deepEqual(result[0].symptoms.map((item) => item.name), ["頭痛", "心悸"]);
});
