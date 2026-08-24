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
