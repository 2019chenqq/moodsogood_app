"use strict";

function normalizeInneraEventDrafts(rawDrafts, existingDrafts, options = {}) {
  const result = new Map();
  const isPhysicalHealth = options.mode === "physicalHealth";
  const latestMessage = String(options.latestMessage || "");
  const upsert = (value, fromModel = false) => {
    const normalized = normalizeEventDraft(value);
    if (!normalized) return null;
    const values = [...result.values()];
    const sameId = result.get(normalized.id);
    const correctionTarget = isPhysicalHealth && fromModel &&
        explicitEventTimeCorrection.test(latestMessage)
      ? sameId || findExplicitCorrectionTarget(values, latestMessage)
      : null;
    if (correctionTarget) {
      const patch = { ...normalized, id: correctionTarget.id };
      result.set(
        correctionTarget.id,
        mergeEventDraft(correctionTarget, patch, {
          allowEventTimeUpdate: true,
          canonicalizeSymptoms: isPhysicalHealth,
        }),
      );
      return { key: correctionTarget.id, priority: 5 };
    }
    if (sameId) {
      if (isPhysicalHealth && fromModel &&
          shouldForkReusedPhysicalId(sameId, normalized, latestMessage)) {
        const forked = {
          ...physicalForkFactsFromLatestMessage(normalized, latestMessage),
          id: stablePhysicalEventId(normalized, result),
        };
        const existingFork = result.get(forked.id);
        result.set(
          forked.id,
          existingFork
            ? mergeEventDraft(existingFork, forked, {
                canonicalizeSymptoms: isPhysicalHealth,
              })
            : forked,
        );
        return { key: forked.id, priority: 5 };
      }
      result.set(
        sameId.id,
        mergeEventDraft(sameId, normalized, {
          allowEventTimeUpdate: !isPhysicalHealth,
          canonicalizeSymptoms: isPhysicalHealth,
        }),
      );
      return { key: sameId.id, priority: 1 };
    }
    const exactEquivalent = [...result.values()].find(
      (item) => sameEventMinute(item, normalized),
    );
    const physicalEquivalent = !exactEquivalent && isPhysicalHealth && fromModel
      ? findPhysicalHealthEquivalent(
          [...result.values()],
          normalized,
          latestMessage,
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
      previous
        ? mergeEventDraft(previous, patch, {
            canonicalizeSymptoms: isPhysicalHealth,
          })
        : normalized,
    );
    return {
      key,
      priority: physicalEquivalent
        ? 4
        : isPhysicalHealth && fromModel &&
            explicitClockOrDayPart.test(latestMessage) &&
            normalized.timePrecision === "exact"
          ? 3
          : 2,
    };
  };
  for (const item of Array.isArray(existingDrafts) ? existingDrafts : []) {
    upsert(item);
  }
  let latestPhysicalTargetKey = null;
  let latestPhysicalTargetPriority = 0;
  for (const item of Array.isArray(rawDrafts) ? rawDrafts : []) {
    const target = upsert(item, true);
    if (isPhysicalHealth && target &&
        target.priority > latestPhysicalTargetPriority) {
      latestPhysicalTargetKey = target.key;
      latestPhysicalTargetPriority = target.priority;
    }
  }
  if (isPhysicalHealth && latestPhysicalTargetKey) {
    const target = result.get(latestPhysicalTargetKey);
    if (target) {
      const recurrenceAntecedent = recurrenceSymptomAntecedent(
        latestMessage,
        [...result.values()].filter((item) => item.id !== target.id),
      );
      result.set(
        latestPhysicalTargetKey,
        canonicalizeEventSymptoms(
          ensurePhysicalSymptomCompleteness(
            recurrenceAntecedent && target.symptoms.length === 0
              ? {
                  ...target,
                  symptoms: [{ name: recurrenceAntecedent, severity: null }],
                }
              : target,
            options.latestMessage,
            [...result.values()],
          ),
        ),
      );
    }
  }
  const values = [...result.values()];
  return (isPhysicalHealth ? values.map(canonicalizeEventSymptoms) : values)
    .slice(0, 20);
}

const HIGH_CONFIDENCE_PHYSICAL_SYMPTOMS = [
  ["心悸", /心悸|心跳很快/u],
  ["手抖", /手抖|手發抖|手部顫抖/u],
  ["頭痛", /頭痛|頭疼/u],
  ["噁心反胃", /噁心|反胃|想吐/u],
  ["頭暈", /頭暈|暈眩/u],
  ["胸悶", /胸悶|胸口悶/u],
  ["疲倦", /疲倦|疲憊|很累|好累|很倦|倦怠/u],
  ["胃痛", /胃痛|胃有點痛|胃部疼痛|胃部痛|胃不舒服/u],
  ["食慾降低", /食慾下降|食慾降低|食慾不振|沒有食慾|沒胃口|吃不下/u],
  ["一直想吃東西", /食慾增加|食慾變大|食量增加|吃得比平常多|一直想吃/u],
  ["白天嗜睡", /白天嗜睡|嗜睡|睏倦|白天(?:一直)?想睡|白天很睏/u],
];

function explicitSeverityAfterMatch(message, match) {
  const tail = message.slice(match.index + match[0].length);
  const scoreMatch = tail.match(
    /^\s*(?:(?:，|,)\s*程度\s*|程度\s*)?(?:大概|約|是|有)?\s*([1-5１-５])\s*分/u,
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
  const symptomMap = new Map(event.symptoms.map((item) => [
    canonicalSymptomName(item.name),
    {
      name: canonicalSymptomName(item.name),
      severity: item.severity,
    },
  ]));
  for (const symptom of detected) {
    const name = canonicalSymptomName(symptom.name);
    const capturedElsewhere = allEvents.some((candidate) =>
      candidate.id !== event.id && candidate.symptoms.some((item) =>
        canonicalSymptomName(item.name) === name
      )
    );
    if (capturedElsewhere && hasMultiplePhysicalTimeContexts(latestMessage)) {
      continue;
    }
    const previous = symptomMap.get(name);
    symptomMap.set(name, {
      name,
      severity: symptom.severity ?? previous?.severity ?? null,
    });
  }
  return { ...event, symptoms: [...symptomMap.values()].slice(0, 20) };
}

function extractExplicitPhysicalSymptoms(latestMessage) {
  return highConfidencePhysicalSymptoms(latestMessage).map((item) => ({
    name: canonicalSymptomName(item.name),
    severity: item.severity,
  }));
}

function hasMultiplePhysicalTimeContexts(message) {
  const contexts = String(message || "").match(
    /早上|上午|中午|下午|傍晚|晚上|凌晨|現在|剛剛|剛才/gu,
  ) || [];
  return new Set(contexts).size > 1;
}

function canonicalSymptomName(value) {
  const name = String(value || "").trim();
  if (/^(?:噁心|反胃|噁心反胃)$/u.test(name)) return "噁心反胃";
  if (/^(?:胃痛|胃有點痛|胃部疼痛|胃部痛)$/u.test(name)) return "胃痛";
  if (/^(?:手抖|手發抖|手部顫抖)$/u.test(name)) return "手抖";
  if (/^(?:心悸|心跳很快(?:且有心悸)?)$/u.test(name)) return "心悸";
  if (/^(?:白天嗜睡|嗜睡|睏倦)$/u.test(name)) return "白天嗜睡";
  return name;
}

function canonicalizeEventSymptoms(event) {
  const symptomMap = new Map();
  for (const item of event.symptoms) {
    const name = canonicalSymptomName(item.name);
    if (!name) continue;
    const previous = symptomMap.get(name);
    symptomMap.set(name, {
      name,
      severity: item.severity ?? previous?.severity ?? null,
    });
  }
  return { ...event, symptoms: [...symptomMap.values()].slice(0, 20) };
}

const omittedSymptomRecurrence = /(?:又|再|再次)[^，。！？]{0,10}(?:痛(?:了)?(?:一次)?|發作(?:了)?(?:一次)?)/u;

function recurrenceSymptomAntecedent(latestMessage, previousEvents) {
  const message = String(latestMessage || "");
  if (!explicitClockOrDayPart.test(message) ||
      !omittedSymptomRecurrence.test(message) ||
      highConfidencePhysicalSymptoms(message).length > 0) {
    return null;
  }
  const previousEntries = physicalEventsByRecency(previousEvents)
    .flatMap((event) => [...event.rawUserEntries].reverse())
    .filter(Boolean);
  for (const entry of previousEntries) {
    const symptoms = highConfidencePhysicalSymptoms(entry)
      .map((item) => canonicalSymptomName(item.name));
    const unique = [...new Set(symptoms)];
    if (unique.length > 0) return unique.length === 1 ? unique[0] : null;
  }
  return null;
}

const PHYSICAL_CONTINUATION_WINDOW_MS = 5 * 60 * 1000;
const explicitClockOrDayPart = /(?:早上|上午|中午|下午|傍晚|晚上|凌晨)(?:[零〇一二兩三四五六七八九十\d]{1,3}點(?:半|[零〇一二兩三四五六七八九十\d]{1,2}分?)?)?|(?:[01]?\d|2[0-3])[:：][0-5]\d|[零〇一二兩三四五六七八九十\d]{1,3}點(?:半|[零〇一二兩三四五六七八九十\d]{1,2}分?)/u;
const explicitNewPhysicalEvent = /後來(?:又)?(?:發作|出現)|隔了?(?:一陣子|一段時間)|過了[^，。！？]{0,12}(?:又|再|出現|發作)|又一波|另一波|再次發作|又出現一次|重新發作/u;
const explicitPriorPhysicalEventReference = /剛剛那個|剛才那個|剛剛的|剛才的|前面那個|上一筆|同一筆|補充(?:一下)?/u;
const explicitPhysicalContinuation = /剛剛那個|剛才那個|剛剛的|剛才的|前面那個|上一筆|同一筆|補充(?:一下)?|^(?:而且|還有|也|另外)|^剛(?:剛|才)(?:也|還|又)?/u;
const explicitEventTimeCorrection = /(?:剛剛那筆|剛才那筆|前面那筆|上一筆|前一筆|那筆)[^，。！？]{0,24}(?:其實|不是|改成|應該是)|(?:時間|時段)[^，。！？]{0,12}(?:說錯|修正|改成)/u;
const currentPhysicalReference = /剛剛|剛才|現在/u;

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

  const eventsByRecency = physicalEventsByRecency(existingEvents);
  if (explicitPhysicalContinuation.test(message) && !explicitClockOrDayPart.test(message)) {
    if (explicitPriorPhysicalEventReference.test(message)) {
      return eventsByRecency[0] || null;
    }
    return findActivePhysicalEvent(eventsByRecency) || null;
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

function physicalEventsByRecency(events) {
  return [...events].sort((left, right) => {
    const leftTime = validEventDate(left.eventTime)?.valueOf() || 0;
    const rightTime = validEventDate(right.eventTime)?.valueOf() || 0;
    return rightTime - leftTime;
  });
}

function findActivePhysicalEvent(events) {
  return physicalEventsByRecency(events).find((event) =>
    currentishTimeContext(event.timeContext) ||
    event.timePrecision === "approximate"
  ) || null;
}

function findExplicitCorrectionTarget(events, latestMessage) {
  if (!explicitEventTimeCorrection.test(String(latestMessage || ""))) return null;
  return [...events].reverse()[0] || null;
}

function shouldForkReusedPhysicalId(previous, patch, latestMessage) {
  const previousTime = validEventDate(previous.eventTime);
  const patchTime = validEventDate(patch.eventTime);
  if (!previousTime || !patchTime || sameEventMinute(previous, patch)) {
    return false;
  }
  const message = String(latestMessage || "");
  if (explicitClockOrDayPart.test(message)) return true;
  return currentPhysicalReference.test(message) &&
    !currentishTimeContext(previous.timeContext) &&
    Math.abs(previousTime.valueOf() - patchTime.valueOf()) >
      PHYSICAL_CONTINUATION_WINDOW_MS;
}

function stablePhysicalEventId(event, result) {
  const eventTime = validEventDate(event.eventTime);
  const base = eventTime
    ? `physical-${eventTime.valueOf()}`
    : `${event.id}-separate`;
  if (!result.has(base)) return base;
  const existing = result.get(base);
  if (existing && sameEventMinute(existing, event)) return base;
  let suffix = 2;
  while (result.has(`${base}-${suffix}`)) suffix += 1;
  return `${base}-${suffix}`;
}

function physicalForkFactsFromLatestMessage(event, latestMessage) {
  const message = String(latestMessage || "");
  const detected = highConfidencePhysicalSymptoms(message);
  const symptoms = event.symptoms.flatMap((symptom) => {
    const known = detected.find((candidate) =>
      candidate.pattern.test(symptom.name)
    );
    if (known) {
      return [{
        name: symptom.name,
        severity: known.severity ?? symptom.severity,
      }];
    }
    return message.includes(symptom.name) ? [symptom] : [];
  });
  return {
    ...event,
    symptoms,
    rawUserEntries: message.trim() ? [message.trim().slice(0, 1000)] : [],
  };
}

function sameEventMinute(left, right) {
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

function mergeEventDraft(previous, patch, options = {}) {
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
  const symptomName = options.canonicalizeSymptoms
    ? canonicalSymptomName
    : (name) => name;
  const symptomMap = new Map(previous.symptoms.map((item) => {
    const name = symptomName(item.name);
    return [name, {
      name,
      severity: item.severity,
    }];
  }));
  for (const item of patch.symptoms) {
    const name = symptomName(item.name);
    const old = symptomMap.get(name);
    symptomMap.set(name, {
      name,
      severity: item.severity ?? old?.severity ?? null,
    });
  }
  return {
    id: previous.id,
    eventTime: options.allowEventTimeUpdate
      ? patch.eventTime || previous.eventTime
      : previous.eventTime || patch.eventTime,
    timeContext: options.allowEventTimeUpdate
      ? patch.timeContext || previous.timeContext
      : previous.timeContext || patch.timeContext,
    timePrecision: options.allowEventTimeUpdate
      ? patch.timePrecision === "unspecified"
        ? previous.timePrecision
        : patch.timePrecision
      : previous.timePrecision === "unspecified"
        ? patch.timePrecision
        : previous.timePrecision,
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
  canonicalSymptomName,
  extractExplicitPhysicalSymptoms,
  normalizeInneraEventDrafts,
  sanitizeExplicitStateChangePatch,
};
