"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  createPhysicalHealthApiResponse,
  createPhysicalHealthChatSchema,
} = require("../innera_physical_health");
const { normalizeInneraEventDrafts } = require("../innera_event_drafts");
const { inneraModePrompt } = require("../innera_mode_prompt");

const eventDraftsSchema = { type: "array", marker: "existing-definition" };

test("physical health schema contains only reply, followUpQuestion, and eventDrafts", () => {
  const schema = createPhysicalHealthChatSchema(eventDraftsSchema);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ["reply", "followUpQuestion", "eventDrafts"]);
  assert.deepEqual(Object.keys(schema.properties), [
    "reply", "followUpQuestion", "eventDrafts",
  ]);
  assert.equal(schema.properties.eventDrafts, eventDraftsSchema);
});

test("physical health API response keeps the existing outer contract", () => {
  const eventDrafts = [{ id: "afternoon" }];
  const result = createPhysicalHealthApiResponse({
    reply: "我先把下午三點開始的心悸與反胃整理成同一筆待確認紀錄。",
    followUpQuestion: null,
    eventDrafts,
    model: "test-model",
    promptVersion: "test-version",
    completion: { usage: { prompt_tokens: 200, completion_tokens: 50 } },
  });
  assert.equal(result.recordDraft, null);
  assert.equal(result.eventDrafts, eventDrafts);
  assert.deepEqual(result.sources, []);
  assert.deepEqual(result.suggestedActions, []);
  assert.equal(result.safetyLevel, "normal");
  assert.equal(result.requiresFixedSafetyUi, false);
});

test("same-time symptoms preserve explicit and missing severity", () => {
  const result = normalizeInneraEventDrafts([{
    id: "afternoon",
    eventTime: "2026-08-24T15:00:00.000Z",
    timeContext: "下午三點",
    timePrecision: "exact",
    emotionMentions: [],
    symptoms: [
      { name: "心悸", severity: 4 },
      { name: "反胃", severity: null },
    ],
    stateChanges: {},
    rawUserEntries: [],
    note: "",
  }], []);
  assert.equal(result.length, 1);
  assert.deepEqual(result[0].symptoms, [
    { name: "心悸", severity: 4 },
    { name: "反胃", severity: null },
  ]);
});

test("different times remain separate physical health events", () => {
  const result = normalizeInneraEventDrafts([
    {
      id: "morning",
      eventTime: null,
      timeContext: "早上",
      timePrecision: "approximate",
      emotionMentions: [],
      symptoms: [{ name: "頭痛", severity: null }],
      stateChanges: {}, rawUserEntries: [], note: "",
    },
    {
      id: "now",
      eventTime: null,
      timeContext: "現在",
      timePrecision: "approximate",
      emotionMentions: [],
      symptoms: [{ name: "噁心", severity: null }],
      stateChanges: {}, rawUserEntries: [], note: "",
    },
  ], []);
  assert.equal(result.length, 2);
});

test("unknown headache severity remains null and mode forbids diagnosis", () => {
  const result = normalizeInneraEventDrafts([{
    id: "now",
    eventTime: null,
    timeContext: "現在",
    timePrecision: "approximate",
    emotionMentions: [],
    symptoms: [{ name: "頭痛", severity: null }],
    stateChanges: {}, rawUserEntries: [], note: "",
  }], []);
  assert.equal(result[0].symptoms[0].severity, null);
  assert.match(inneraModePrompt("physicalHealth"), /不得診斷|不得診斷或從症狀推測疾病/);
  assert.match(inneraModePrompt("physicalHealth"), /不得因症狀推測情緒/);
});

const physicalEvent = (symptoms = []) => ({
  id: "current",
  eventTime: "2026-08-24T16:15:00.000Z",
  timeContext: "現在",
  timePrecision: "approximate",
  emotionMentions: [],
  symptoms,
  stateChanges: {},
  rawUserEntries: [],
  note: "身體不適",
});

test("physical health restores a hand tremor omitted by the model without a duplicate event", () => {
  const result = normalizeInneraEventDrafts(
    [physicalEvent([{ name: "心悸", severity: null }])],
    [],
    { mode: "physicalHealth", latestMessage: "剛剛有心悸，現在又有點手抖" },
  );
  assert.equal(result.length, 1);
  assert.deepEqual(result[0].symptoms, [
    { name: "心悸", severity: null },
    { name: "手抖", severity: null },
  ]);
});

test("physical health restores multiple omitted symptoms with null severity", () => {
  const result = normalizeInneraEventDrafts(
    [physicalEvent([])],
    [],
    { mode: "physicalHealth", latestMessage: "現在頭痛，而且有點反胃" },
  );
  assert.deepEqual(result[0].symptoms, [
    { name: "頭痛", severity: null },
    { name: "噁心反胃", severity: null },
  ]);
});

test("physical health does not copy an already captured symptom into another event", () => {
  const morning = {
    ...physicalEvent([{ name: "頭痛", severity: null }]),
    id: "morning",
    eventTime: "2026-08-24T08:00:00.000Z",
    timeContext: "早上",
  };
  const now = {
    ...physicalEvent([{ name: "噁心反胃", severity: null }]),
    id: "now",
  };
  const result = normalizeInneraEventDrafts([morning, now], [], {
    mode: "physicalHealth",
    latestMessage: "早上頭痛，現在有點反胃",
  });
  assert.equal(result.length, 2);
  assert.deepEqual(result[0].symptoms, [{ name: "頭痛", severity: null }]);
  assert.deepEqual(result[1].symptoms, [{ name: "噁心反胃", severity: null }]);
});

test("physical health binds each explicit score only to its symptom", () => {
  const result = normalizeInneraEventDrafts(
    [physicalEvent([{ name: "手抖", severity: null }])],
    [],
    { mode: "physicalHealth", latestMessage: "手抖4分，心悸2分" },
  );
  assert.deepEqual(result[0].symptoms, [
    { name: "手抖", severity: 4 },
    { name: "心悸", severity: 2 },
  ]);
});

test("physical health does not infer symptoms from emotion-only text", () => {
  const result = normalizeInneraEventDrafts(
    [physicalEvent([{ name: "心悸", severity: null }])],
    [],
    { mode: "physicalHealth", latestMessage: "我覺得很害怕" },
  );
  assert.deepEqual(result[0].symptoms, [{ name: "心悸", severity: null }]);
});

test("symptom completeness guard is disabled for other modes", () => {
  const result = normalizeInneraEventDrafts(
    [physicalEvent([{ name: "心悸", severity: null }])],
    [],
    { mode: "dailyRecord", latestMessage: "現在又有點手抖" },
  );
  assert.deepEqual(result[0].symptoms, [{ name: "心悸", severity: null }]);
});

test("medical urgency still bypasses the general OpenAI flow", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const urgencyCheck = source.indexOf("const hasMedicalUrgency");
  const urgencyReturn = source.indexOf(
    "if (safetySignal.detected || hasImminentDanger || hasMedicalUrgency)",
  );
  const openAiCall = source.indexOf("client.chat.completions.create", urgencyReturn);
  assert.match(source, /"胸痛"/);
  assert.match(source, /"呼吸困難"/);
  assert.ok(urgencyCheck >= 0);
  assert.ok(urgencyReturn > urgencyCheck);
  assert.ok(openAiCall > urgencyReturn);
});
