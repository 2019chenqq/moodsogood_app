"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { buildInneraContextPayload } = require("../innera_request_payload");

const shared = {
  context: { locale: "zh-TW" },
  contextSources: [{ label: "最近紀錄", dateRange: "近七天", count: 3 }],
  recordDraft: { eventDrafts: [{ id: "existing" }] },
  emotionDimensions: [{ id: "anxiety", displayName: "焦慮" }],
};

test("emotional support sends only mode, context, and contextSources", () => {
  const payload = buildInneraContextPayload({
    mode: "emotionalSupport",
    ...shared,
  });
  assert.deepEqual(payload, {
    mode: "emotionalSupport",
    context: shared.context,
    contextSources: shared.contextSources,
  });
  assert.equal(Object.hasOwn(payload, "recordDraft"), false);
  assert.equal(Object.hasOwn(payload, "eventDrafts"), false);
  assert.equal(Object.hasOwn(payload, "emotionDimensions"), false);
});

test("daily record retains recordDraft and emotionDimensions", () => {
  const payload = buildInneraContextPayload({ mode: "dailyRecord", ...shared });
  assert.equal(payload.recordDraft, shared.recordDraft);
  assert.equal(payload.emotionDimensions, shared.emotionDimensions);
});

test("physical health retains its existing structured extraction input", () => {
  const payload = buildInneraContextPayload({ mode: "physicalHealth", ...shared });
  assert.equal(payload.recordDraft, shared.recordDraft);
  assert.equal(payload.emotionDimensions, shared.emotionDimensions);
});

test("recent review retains its existing minimal input behavior", () => {
  const payload = buildInneraContextPayload({ mode: "recentReview", ...shared });
  assert.deepEqual(payload, {
    mode: "recentReview",
    context: shared.context,
    contextSources: shared.contextSources,
  });
});
