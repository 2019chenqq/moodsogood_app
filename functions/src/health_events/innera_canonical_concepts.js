"use strict";

const canonicalSymptoms = Object.freeze([
  Object.freeze({ id: "palpitation", displayName: "心悸", category: "cardiovascular" }),
  Object.freeze({ id: "tremor", displayName: "手抖", category: "neuromuscular" }),
  Object.freeze({ id: "nausea", displayName: "噁心反胃", category: "digestive" }),
  Object.freeze({ id: "abdominal_pain", displayName: "胃痛", category: "digestive" }),
  Object.freeze({ id: "headache", displayName: "頭痛", category: "head" }),
  Object.freeze({ id: "dizziness", displayName: "頭暈", category: "head" }),
  Object.freeze({ id: "chest_tightness", displayName: "胸悶", category: "cardiovascular" }),
  Object.freeze({ id: "fatigue", displayName: "疲倦", category: "general" }),
  Object.freeze({ id: "daytime_sleepiness", displayName: "白天嗜睡", category: "general" }),
]);

const canonicalSymptomsById = new Map(
  canonicalSymptoms.map((concept) => [concept.id, concept]),
);
const canonicalSymptomsByDisplayName = new Map(
  canonicalSymptoms.map((concept) => [concept.displayName, concept]),
);

function resolveCanonicalSymptom(value) {
  const text = String(value || "").trim();
  return canonicalSymptomsById.get(text) ||
    canonicalSymptomsByDisplayName.get(text) ||
    null;
}

function resolveCanonicalSymptomId(value) {
  return resolveCanonicalSymptom(value)?.id || null;
}

module.exports = {
  canonicalSymptoms,
  resolveCanonicalSymptom,
  resolveCanonicalSymptomId,
};
