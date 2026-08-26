"use strict";

function normalizeInneraEventDrafts(rawDrafts, existingDrafts, options = {}) {
  const result = new Map();
  const upsert = (value, allowPhysicalContinuation = false) => {
    const normalized = normalizeEventDraft(value);
    if (!normalized) return;
    const exactEquivalent = [...result.values()].find(
      (item) => sameEventTime(item, normalized),
    );
    const physicalEquivalent = !exactEquivalent && allowPhysicalContinuation
      ? findPhysicalHealthEquivalent(
          [...result.values()],
          normalized,
          options.latestMessage,
        )
      : null;
    const equivalent = exactEquivalent || physicalEquivalent;
    const key = equivalent?.id || normalized.id;
    const previous = result.get(key);
    const patch = physicalEquivalent
      ? {
          ...normalized,
          eventTime: previous.eventTime,
          timeContext: previous.timeContext,
          timePrecision: previous.timePrecision,
        }
      : normalized;
    result.set(
      key,
      previous ? mergeEventDraft(previous, patch) : normalized,
    );
  };
  for (const item of Array.isArray(existingDrafts) ? existingDrafts : []) {
    upsert(item);
  }
  let latestPhysicalTargetKey = null;
  for (const item of Array.isArray(rawDrafts) ? rawDrafts : []) {
    upsert(item, options.mode === "physicalHealth");
    if (options.mode === "physicalHealth") {
      const normalized = normalizeEventDraft(item);
      if (!normalized) continue;
      const target = [...result.values()].find(
        (candidate) => sameEventTime(candidate, normalized),
      ) || findPhysicalHealthEquivalent(
        [...result.values()],
        normalized,
        options.latestMessage,
      );
      latestPhysicalTargetKey = target?.id || normalized.id;
    }
  }
  if (options.mode === "physicalHealth" && latestPhysicalTargetKey) {
    const target = result.get(latestPhysicalTargetKey);
    if (target) {
      result.set(
        latestPhysicalTargetKey,
        ensurePhysicalSymptomCompleteness(
          target,
          options.latestMessage,
          [...result.values()],
        ),
      );
    }
  }
  return [...result.values()].slice(0, 20);
}

const HIGH_CONFIDENCE_PHYSICAL_SYMPTOMS = [
  ["心悸", /心悸|心跳很快/u],
  ["手抖", /手抖|手發抖/u],
  ["頭痛", /頭痛|頭疼/u],
  ["噁心反胃", /噁心|反胃|想吐/u],
  ["疲倦", /疲倦|疲憊|很累|好累|很倦|倦怠/u],
  ["胃痛", /胃痛|胃不舒服/u],
  ["食慾降低", /食慾下降|食慾降低|食慾不振|沒有食慾|沒胃口|吃不下/u],
  ["一直想吃東西", /食慾增加|食慾變大|食量增加|吃得比平常多|一直想吃/u],
  ["白天嗜睡", /白天嗜睡|白天(?:一直)?想睡|白天很睏/u],
];

function explicitSeverityAfterMatch(message, match) {
  const tail = message.slice(match.index + match[0].length);
  const scoreMatch = tail.match(
    /^\s*(?:程度\s*)?(?:大概|約|是|有)?\s*([1-5１-５])\s*分/u,
  );
  if (!scoreMatch) return null;
  const normalizedDigit = "１２３４５".indexOf(scoreMatch[1]) + 1;
  return normalizedDigit || Number(scoreMatch[1]);
}

function highConfidencePhysicalSymptoms(latestMessage) {
  const message = String(latestMessage || "");
  return HIGH_CONFIDENCE_PHYSICAL_SYMPTOMS.flatMap(([name, pattern]) => {
    const match = pattern.exec(message);
    return match
      ? [{ name, pattern, severity: explicitSeverityAfterMatch(message, match) }]
      : [];
  });
}

function ensurePhysicalSymptomCompleteness(event, latestMessage, allEvents) {
  const detected = highConfidencePhysicalSymptoms(latestMessage);
  if (detected.length === 0) return event;
  const symptomMap = new Map(event.symptoms.map((item) => [item.name, item]));
  for (const symptom of detected) {
    const existingEvent = allEvents.find((candidate) =>
      candidate.symptoms.some((item) => symptom.pattern.test(item.name))
    );
    if (existingEvent && existingEvent.id !== event.id) continue;
    const existingName = existingEvent?.symptoms.find((item) =>
      symptom.pattern.test(item.name)
    )?.name;
    const name = existingName || symptom.name;
    const previous = symptomMap.get(name);
    symptomMap.set(name, {
      name,
      severity: symptom.severity ?? previous?.severity ?? null,
    });
  }
  return { ...event, symptoms: [...symptomMap.values()].slice(0, 20) };
}

const PHYSICAL_CONTINUATION_WINDOW_MS = 5 * 60 * 1000;
const explicitClockOrDayPart = /(?:早上|上午|中午|下午|傍晚|晚上|凌晨)(?:[零〇一二兩三四五六七八九十\d]{1,3}點(?:半|[零〇一二兩三四五六七八九十\d]{1,2}分?)?)?|(?:[01]?\d|2[0-3])[:：][0-5]\d|[零〇一二兩三四五六七八九十\d]{1,3}點(?:半|[零〇一二兩三四五六七八九十\d]{1,2}分?)/u;
const explicitNewPhysicalEvent = /後來(?:又)?(?:發作|出現)|隔了?(?:一陣子|一段時間)|過了[^，。！？]{0,12}(?:又|再|出現|發作)|又一波|另一波|再次發作|又出現一次|重新發作/u;
const explicitPhysicalContinuation = /剛剛那個|剛才那個|剛剛的|剛才的|前面那個|上一筆|同一筆|補充(?:一下)?/u;

function currentishTimeContext(value) {
  return /^(?:now|current|現在|剛剛|剛才)$/iu.test(String(value || "").trim());
}

function compatiblePhysicalTimeContext(left, right) {
  if (!left || !right || left === right) return true;
  return currentishTimeContext(left) && currentishTimeContext(right);
}

function validEventDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}

function sameUtcDate(left, right) {
  return left.getUTCFullYear() === right.getUTCFullYear() &&
    left.getUTCMonth() === right.getUTCMonth() &&
    left.getUTCDate() === right.getUTCDate();
}

function hasPhysicalSupplementContent(event) {
  return event.symptoms.length > 0 ||
    event.emotionMentions.length > 0 ||
    Object.keys(event.stateChanges).length > 0 ||
    Boolean(event.note);
}

function findPhysicalHealthEquivalent(existingEvents, patch, latestMessage) {
  const message = String(latestMessage || "").replace(/\s+/g, "");
  if (!hasPhysicalSupplementContent(patch) || explicitNewPhysicalEvent.test(message)) {
    return null;
  }

  const eventsByRecency = [...existingEvents].reverse();
  if (explicitPhysicalContinuation.test(message) && !explicitClockOrDayPart.test(message)) {
    return eventsByRecency[0] || null;
  }
  if (explicitClockOrDayPart.test(message) || patch.timePrecision === "exact") {
    return null;
  }

  const patchTime = validEventDate(patch.eventTime);
  if (!patchTime || !["approximate", "unspecified"].includes(patch.timePrecision)) {
    return null;
  }
  return eventsByRecency.find((candidate) => {
    const candidateTime = validEventDate(candidate.eventTime);
    return candidateTime &&
      sameUtcDate(candidateTime, patchTime) &&
      Math.abs(candidateTime.valueOf() - patchTime.valueOf()) <=
        PHYSICAL_CONTINUATION_WINDOW_MS &&
      compatiblePhysicalTimeContext(candidate.timeContext, patch.timeContext);
  }) || null;
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
