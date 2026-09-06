"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  extractPhysicalHealthTurnFacts,
  physicalHealthTurnFactsSchema,
} = require("../innera_physical_health_turn_facts");

const symptom = (canonicalId, displayName, severity = null) => ({
  canonicalId,
  displayName,
  rawPhrase: null,
  name: displayName,
  severity,
});

test("turn fact schema is strict and independent from event drafts", () => {
  assert.equal(physicalHealthTurnFactsSchema.additionalProperties, false);
  assert.equal(Object.hasOwn(physicalHealthTurnFactsSchema.properties, "eventDrafts"), false);
  assert.equal(Object.hasOwn(physicalHealthTurnFactsSchema.properties, "id"), false);
});

test("A extracts only the current heart palpitation", () => {
  const facts = extractPhysicalHealthTurnFacts("我現在有點心悸");
  assert.deepEqual(facts.symptoms, [symptom("palpitation", "心悸")]);
  assert.equal(facts.time.timeContext, "現在");
});

test("B a follow-up turn contains only the newly stated hand tremor", () => {
  const facts = extractPhysicalHealthTurnFacts("而且有點手抖");
  assert.deepEqual(facts.symptoms, [symptom("tremor", "手抖")]);
});

test("C explicit morning turn cannot contain prior symptoms", () => {
  const facts = extractPhysicalHealthTurnFacts("早上8點心悸3分");
  assert.equal(facts.time.time, "08:00");
  assert.deepEqual(facts.symptoms, [symptom("palpitation", "心悸", 3)]);
});

test("D severity binds only to the adjacent explicit symptom", () => {
  const facts = extractPhysicalHealthTurnFacts("心悸4分，手抖");
  assert.deepEqual(facts.symptoms, [
    symptom("palpitation", "心悸", 4),
    symptom("tremor", "手抖"),
  ]);
});

test("E recurrence remains unresolved without an explicit symptom", () => {
  const facts = extractPhysicalHealthTurnFacts("晚上9點又痛了一次");
  assert.equal(facts.time.time, "21:00");
  assert.equal(facts.recurrence, true);
  assert.equal(facts.symptomReferenceUnresolved, true);
  assert.deepEqual(facts.symptoms, []);
});

test("F correction extracts a time but does not contain an event identity", () => {
  const facts = extractPhysicalHealthTurnFacts("剛剛那筆其實是下午2點");
  assert.equal(facts.correction, true);
  assert.equal(facts.time.time, "14:00");
  assert.equal(Object.hasOwn(facts, "eventId"), false);
});

test("G stomach aliases are canonical and unique", () => {
  const facts = extractPhysicalHealthTurnFacts("胃有點痛，還有點反胃");
  assert.deepEqual(facts.symptoms, [
    symptom("nausea", "噁心反胃"),
    symptom("abdominal_pain", "胃痛"),
  ]);
});

test("debug output contains metadata only", () => {
  const original = console.log;
  const entries = [];
  console.log = (...args) => entries.push(args);
  try {
    extractPhysicalHealthTurnFacts("心悸4分，手抖", { debug: true });
  } finally {
    console.log = original;
  }
  assert.equal(entries.length, 1);
  assert.deepEqual(Object.keys(entries[0][1]), [
    "factCount",
    "symptomCount",
    "hasExplicitTime",
    "recurrence",
    "correction",
  ]);
  assert.doesNotMatch(JSON.stringify(entries), /心悸|手抖/u);
});

test("extracts only explicit state changes and body measurements", () => {
  const facts = extractPhysicalHealthTurnFacts(
    "能量3分，體重62.5公斤，體脂25%",
  );
  assert.deepEqual(facts.stateChanges, [
    { name: "energy_change", value: 3 },
  ]);
  assert.deepEqual(facts.bodyMeasurements, [
    { type: "weight", value: 62.5, unit: "kg" },
    { type: "bodyFat", value: 25, unit: "%" },
  ]);
});

test("bare sleepiness alias is extracted with its explicit score", () => {
  const facts = extractPhysicalHealthTurnFacts("早上8點嗜睡3分");
  assert.equal(facts.time.time, "08:00");
  assert.deepEqual(facts.symptoms, [
    symptom("daytime_sleepiness", "白天嗜睡", 3),
  ]);
});
