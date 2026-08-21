"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeInneraEventDrafts } = require("../innera_event_drafts");

const event = (id, timeContext, symptoms) => ({
  id,
  eventTime: null,
  timeContext,
  timePrecision: "approximate",
  symptoms,
  stateChanges: {},
  rawUserEntries: [],
  note: symptoms.join("、"),
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
  assert.deepEqual(result[0].symptoms, ["疲倦", "頭痛"]);
});
