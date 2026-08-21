"use strict";

function normalizeInneraEventDrafts(rawDrafts, existingDrafts) {
  const result = new Map();
  for (const item of Array.isArray(existingDrafts) ? existingDrafts : []) {
    const normalized = normalizeEventDraft(item);
    if (normalized) result.set(normalized.id, normalized);
  }
  for (const item of Array.isArray(rawDrafts) ? rawDrafts : []) {
    const normalized = normalizeEventDraft(item);
    if (!normalized) continue;
    const previous = result.get(normalized.id);
    result.set(normalized.id, previous ? mergeEventDraft(previous, normalized) : normalized);
  }
  return [...result.values()].slice(0, 20);
}

function normalizeEventDraft(value) {
  if (!value || typeof value !== "object") return null;
  const text = (input, max = 500) => String(input || "").trim().slice(0, max);
  const id = text(value.id, 100);
  if (!id) return null;
  const eventTimeText = text(value.eventTime, 40);
  const eventTime = Number.isNaN(Date.parse(eventTimeText)) ? null : eventTimeText;
  const timePrecision = ["exact", "approximate", "unspecified"].includes(value.timePrecision)
    ? value.timePrecision
    : "unspecified";
  const symptoms = [...new Set((Array.isArray(value.symptoms) ? value.symptoms : [])
    .map((item) => text(item && typeof item === "object" ? item.name : item, 100))
    .filter(Boolean))].slice(0, 20);
  const stateChanges = {};
  for (const key of ["energy_change", "appetite_change", "activity_change"]) {
    const score = Number(value.stateChanges?.[key]);
    if (Number.isInteger(score) && score >= 1 && score <= 5) {
      stateChanges[key] = score;
    }
  }
  const rawUserEntries = [...new Set(
    (Array.isArray(value.rawUserEntries) ? value.rawUserEntries : [])
      .map((item) => text(item, 1000))
      .filter(Boolean),
  )].slice(0, 20);
  const note = text(value.note, 2000);
  if (symptoms.length === 0 && Object.keys(stateChanges).length === 0 && !note) {
    return null;
  }
  return {
    id,
    eventTime,
    timeContext: text(value.timeContext, 100) || null,
    timePrecision,
    symptoms,
    stateChanges,
    rawUserEntries,
    note,
  };
}

function mergeEventDraft(previous, patch) {
  return {
    id: previous.id,
    eventTime: patch.eventTime || previous.eventTime,
    timeContext: patch.timeContext || previous.timeContext,
    timePrecision: patch.timePrecision === "unspecified"
      ? previous.timePrecision
      : patch.timePrecision,
    symptoms: [...new Set([...previous.symptoms, ...patch.symptoms])],
    stateChanges: { ...previous.stateChanges, ...patch.stateChanges },
    rawUserEntries: [
      ...new Set([...previous.rawUserEntries, ...patch.rawUserEntries]),
    ],
    note: patch.note || previous.note,
  };
}

module.exports = { normalizeInneraEventDrafts };
