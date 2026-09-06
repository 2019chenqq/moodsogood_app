"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  canonicalSymptoms,
  resolveCanonicalSymptom,
  resolveCanonicalSymptomId,
} = require("../innera_canonical_concepts");

test("canonical symptom ids are unique", () => {
  const ids = canonicalSymptoms.map((concept) => concept.id);
  assert.equal(new Set(ids).size, ids.length);
});

test("canonical symptom display names are unique", () => {
  const names = canonicalSymptoms.map((concept) => concept.displayName);
  assert.equal(new Set(names).size, names.length);
});

test("legacy canonical display name resolves without an alias matcher", () => {
  assert.equal(resolveCanonicalSymptomId("心悸"), "palpitation");
  assert.deepEqual(resolveCanonicalSymptom("palpitation"), {
    id: "palpitation",
    displayName: "心悸",
    category: "cardiovascular",
  });
});

test("unknown symptom remains unresolved without crashing", () => {
  assert.equal(resolveCanonicalSymptomId("未知症狀"), null);
  assert.equal(resolveCanonicalSymptom("未知症狀"), null);
});

test("canonical registry does not perform natural-language alias matching", () => {
  assert.equal(resolveCanonicalSymptomId("嗜睡"), null);
  assert.equal(resolveCanonicalSymptomId("很睏"), null);
});
