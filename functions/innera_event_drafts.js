"use strict";

function normalizeInneraEventDrafts(rawDrafts, existingDrafts) {
  const result = new Map();
  const upsert = (value) => {
    const normalized = normalizeEventDraft(value);
    if (!normalized) return;
    const equivalent = [...result.values()].find(
      (item) => sameEventTime(item, normalized),
    );
    const key = equivalent?.id || normalized.id;
    const previous = result.get(key);
    result.set(
      key,
      previous ? mergeEventDraft(previous, normalized) : normalized,
    );
  };
  for (const item of Array.isArray(existingDrafts) ? existingDrafts : []) {
    upsert(item);
  }
  for (const item of Array.isArray(rawDrafts) ? rawDrafts : []) {
    upsert(item);
  }
  return [...result.values()].slice(0, 20);
}

function sameEventTime(left, right) {
  if (left.id === right.id) return true;
  if (!left.eventTime || !right.eventTime) return false;
  const leftTime = new Date(left.eventTime);
  const rightTime = new Date(right.eventTime);
  return !Number.isNaN(leftTime.valueOf()) &&
    !Number.isNaN(rightTime.valueOf()) &&
    leftTime.getUTCFullYear() === rightTime.getUTCFullYear() &&
    leftTime.getUTCMonth() === rightTime.getUTCMonth() &&
    leftTime.getUTCDate() === rightTime.getUTCDate() &&
    leftTime.getUTCHours() === rightTime.getUTCHours() &&
    leftTime.getUTCMinutes() === rightTime.getUTCMinutes();
}

function sanitizeExplicitStateChangePatch(rawStateChanges, latestMessage) {
  const stateChanges = rawStateChanges && typeof rawStateChanges === "object"
    ? { ...rawStateChanges }
    : {};
  const message = String(latestMessage || "").replace(/\s+/g, "");
  const scoredFatigue = /(?:疲倦|疲懊|很累|好累|累)(?:程度)?(?:大概|約|是|有)?[1-5１-５]分/.test(message);
  const scoredEnergy = /(?:能量|精力|體力)(?:程度)?(?:大概|約|是|有)?[1-5１-５]分/.test(message);
  if (scoredFatigue && !scoredEnergy) {
    delete stateChanges.energy_change;
  }
  return stateChanges;
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
  const emotionMentions = (Array.isArray(value.emotionMentions) ? value.emotionMentions : [])
    .map((item) => {
      const rawText = text(item?.rawText ?? item?.name, 100);
      if (!rawText) return null;
      const rawValue = Number(item?.value ?? item?.score);
      return {
        rawText,
        normalizedDimensionId: text(item?.normalizedDimensionId, 80) || null,
        normalizedDimensionName: text(item?.normalizedDimensionName, 80) || null,
        value: Number.isInteger(rawValue) && rawValue >= 1 && rawValue <= 5
          ? rawValue
          : null,
      };
    })
    .filter(Boolean)
    .slice(0, 20);
  const symptomMap = new Map();
  for (const item of Array.isArray(value.symptoms) ? value.symptoms : []) {
    const name = text(item && typeof item === "object" ? item.name : item, 100);
    if (!name) continue;
    const rawSeverity = item && typeof item === "object" ? Number(item.severity) : NaN;
    const severity = Number.isInteger(rawSeverity) && rawSeverity >= 1 && rawSeverity <= 5
      ? rawSeverity
      : null;
    const previous = symptomMap.get(name);
    symptomMap.set(name, {
      name,
      severity: severity ?? previous?.severity ?? null,
    });
  }
  const symptoms = [...symptomMap.values()].slice(0, 20);
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
  if (emotionMentions.length === 0 && symptoms.length === 0 && Object.keys(stateChanges).length === 0 && !note) {
    return null;
  }
  return {
    id,
    eventTime,
    timeContext: text(value.timeContext, 100) || null,
    timePrecision,
    emotionMentions,
    symptoms,
    stateChanges,
    rawUserEntries,
    note,
  };
}

function mergeEventDraft(previous, patch) {
  const emotionMap = new Map(previous.emotionMentions.map((item) => [
    item.normalizedDimensionId || `raw:${item.rawText}`,
    item,
  ]));
  for (const item of patch.emotionMentions) {
    const key = item.normalizedDimensionId || `raw:${item.rawText}`;
    const old = emotionMap.get(key);
    emotionMap.set(key, {
      ...old,
      ...item,
      value: item.value ?? old?.value ?? null,
    });
  }
  const symptomMap = new Map(previous.symptoms.map((item) => [item.name, item]));
  for (const item of patch.symptoms) {
    const old = symptomMap.get(item.name);
    symptomMap.set(item.name, {
      name: item.name,
      severity: item.severity ?? old?.severity ?? null,
    });
  }
  return {
    id: previous.id,
    eventTime: patch.eventTime || previous.eventTime,
    timeContext: patch.timeContext || previous.timeContext,
    timePrecision: patch.timePrecision === "unspecified"
      ? previous.timePrecision
      : patch.timePrecision,
    emotionMentions: [...emotionMap.values()],
    symptoms: [...symptomMap.values()],
    stateChanges: { ...previous.stateChanges, ...patch.stateChanges },
    rawUserEntries: [
      ...new Set([...previous.rawUserEntries, ...patch.rawUserEntries]),
    ],
    note: patch.note || previous.note,
  };
}

module.exports = {
  normalizeInneraEventDrafts,
  sanitizeExplicitStateChangePatch,
};
