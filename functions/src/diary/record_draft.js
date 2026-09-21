const { sanitizeExplicitStateChangePatch } = require("../health_events/innera_event_drafts");

function extractExplicitSleepTimes(rawText) {
  const result = { wakeTime: null, finalWakeTime: null };
  const clauses = String(rawText || "").split(/[，。！？\n]+/).filter(Boolean);
  const clockBeforeAction = (clause, actionPattern) => {
    const match = clause.match(new RegExp(
      "(凌晨|清晨|早上|上午|下午|晚上)?\\s*" +
      "(\\d{1,2})(?:[:：]([0-5]\\d)|點(?:(半)|([0-5]?\\d)\\s*分?)?)" +
      "\\s*(?:多|左右)?" +
      `[^0-9０-９，。！？\\n]{0,12}(?:${actionPattern})`,
    ));
    if (!match) return null;
    let hour = Number(match[2]);
    if (!Number.isInteger(hour) || hour > 23) return null;
    if ((match[1] === "下午" || match[1] === "晚上") && hour < 12) hour += 12;
    if (match[1] === "凌晨" && hour === 12) hour = 0;
    const minute = match[4] ? 30 : Number(match[3] || match[5] || 0);
    return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
  };
  for (const clause of clauses) {
    if (/昨天|前天|昨晚/.test(clause)) continue;
    result.wakeTime ||= clockBeforeAction(clause, "起床|離床|下床|開始活動");
    const awakening = clockBeforeAction(
      clause,
      "醒來|醒了|醒著|清醒|睜眼|睜開眼",
    );
    const returnedToSleep =
      /(?:醒來|醒了|醒著|清醒|睜眼|睜開眼)[^，。！？\n]{0,16}(?:又睡|再睡|睡回去|繼續睡)/.test(clause);
    if (!returnedToSleep) result.finalWakeTime ||= awakening;
  }
  return result;
}

function normalizeInneraRecordDraft(rawDraft, existingDraft, emotionDimensions, latestMessage) {
  const raw = rawDraft && typeof rawDraft === "object" ? rawDraft : {};
  const existing = existingDraft && typeof existingDraft === "object" ? existingDraft : {};
  const safeText = (value, max = 1200) => String(value || "").trim().slice(0, max);
  const validTime = (value) => {
    const text = safeText(value, 5);
    return /^([01]?\d|2[0-3]):[0-5]\d$/.test(text) ? text.padStart(5, "0") : null;
  };
  const validScore = (value) => {
    if (value == null || value === "") return null;
    const score = Number(value);
    return Number.isInteger(score) && score >= 1 && score <= 5 ? score : null;
  };
  const itemName = (item) =>
    safeText(item && typeof item === "object" ? item.name : item, 100);
  const symptomPatterns = [
    ["疲倦", /疲倦|疲憊|很累|好累|很倦|倦怠/],
    ["動力不足", /動力不足|沒有動力|沒動力|缺乏動力|提不起勁/],
    ["一直想吃東西", /食慾增加|食慾變大|食量增加|吃得比平常多|一直想吃/],
    ["食慾降低", /食慾下降|食慾降低|食慾不振|沒有食慾|沒胃口|吃不下/],
    ["噁心反胃", /想吐|噁心|反胃/],
    ["頭痛", /頭痛|頭疼/],
    ["心悸", /心悸|心跳很快/],
    ["胃痛", /胃痛|胃不舒服/],
  ];
  const symptomNamesFromText = (value) => {
    const text = safeText(value, 500);
    return symptomPatterns
      .filter(([, pattern]) => pattern.test(text))
      .map(([name]) => name);
  };
  const dimensions = Array.isArray(emotionDimensions) ? emotionDimensions : [];
  const dimensionById = new Map(dimensions.map((item) => [item.id, item]));
  const dimensionByTerm = new Map();
  for (const dimension of dimensions) {
    dimensionByTerm.set(dimension.displayName, dimension);
    for (const alias of dimension.aliases) dimensionByTerm.set(alias, dimension);
  }
  const resolveDimension = (item, rawText) => {
    const requestedId = safeText(item?.normalizedDimensionId, 80);
    const requestedName = safeText(item?.normalizedDimensionName, 80);
    const byId = dimensionById.get(requestedId);
    if (byId && (!requestedName || requestedName === byId.displayName)) return byId;
    return dimensionByTerm.get(requestedName) || dimensionByTerm.get(rawText) || null;
  };
  const stateIds = ["energy_change", "appetite_change", "activity_change"];
  const rawStateChanges = sanitizeExplicitStateChangePatch(
    raw.stateChanges,
    latestMessage,
  );
  const stateChanges = {};
  for (const id of stateIds) {
    const next = validScore(rawStateChanges[id]);
    const old = validScore(existing.stateChanges?.[id]);
    if (next != null || old != null) stateChanges[id] = next ?? old;
  }
  const validMeasurement = (value, min, max) => {
    if (value == null || value === "") return null;
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed < min || parsed > max) return null;
    const scaled = parsed * 10;
    if (Math.abs(scaled - Math.round(scaled)) > 1e-9) return null;
    return Math.round(scaled) / 10;
  };
  const nextBody = raw.bodyMeasurement && typeof raw.bodyMeasurement === "object"
    ? raw.bodyMeasurement
    : {};
  const oldBody = existing.bodyMeasurement && typeof existing.bodyMeasurement === "object"
    ? existing.bodyMeasurement
    : {};
  const timingValues = new Set(["afterWaking", "afterBreakfast", "afterLunch", "afterDinner", "beforeSleep", "other"]);
  const measurementTimingTerms = "(?:起床(?:後)?|早餐後|午餐後|晚餐後|吃飯後|飯後|睡前|運動後)";
  const measurementTerms = "(?:量|測|體重|體脂|腰圍)";
  const measurementTimingWasExplicit = new RegExp(
    `${measurementTimingTerms}[^，。！？；\\n]{0,12}${measurementTerms}|` +
    `${measurementTerms}[^，。！？；\\n]{0,12}${measurementTimingTerms}`,
  ).test(safeText(latestMessage, 4000));
  const requestedTiming = measurementTimingWasExplicit
    ? nextBody.measurementTiming ?? oldBody.measurementTiming
    : oldBody.measurementTiming;
  let measurementTiming = timingValues.has(requestedTiming) ? requestedTiming : null;
  const customMeasurementTime = measurementTiming === "other"
    ? safeText(nextBody.customMeasurementTime, 100) ||
      (oldBody.measurementTiming === "other"
        ? safeText(oldBody.customMeasurementTime, 100)
        : "")
    : "";
  if (measurementTiming === "other" && !customMeasurementTime) {
    measurementTiming = null;
  }
  const weightKg = validMeasurement(nextBody.weightKg, 20, 300) ?? validMeasurement(oldBody.weightKg, 20, 300);
  const bodyFatPercent = validMeasurement(nextBody.bodyFatPercent, 1, 70) ?? validMeasurement(oldBody.bodyFatPercent, 1, 70);
  const waistCm = validMeasurement(nextBody.waistCm, 30, 250) ?? validMeasurement(oldBody.waistCm, 30, 250);
  const hasBodyMeasurementValue = weightKg != null || bodyFatPercent != null || waistCm != null;
  if (!hasBodyMeasurementValue) measurementTiming = null;
  const bodyMeasurement = {
    weightKg,
    bodyFatPercent,
    waistCm,
    measurementTiming,
    customMeasurementTime:
      hasBodyMeasurementValue && measurementTiming === "other"
        ? customMeasurementTime
        : null,
  };
  const otherSubjectPattern = /(爸爸|爸媽|媽媽|母親|父親|弟弟|妹妹|哥哥|姊姊|姐姐|家人|朋友|同事|同學|老師|醫師|醫生|護理師|伴侶|男友|女友|先生|太太|孩子|兒子|女兒|對方|他們|她們|他|她)/;
  const explicitUserPattern = /(我(?:自己|本人|也|還|真的|其實|現在|今天|當下|開始|感到|感覺|覺得|變得|很|好|超|有點|有些|有一點|心裡|心情)?|讓我|害我|使我|令我|我的)/;
  const sharedUserPattern = /(我們(?:都|一起)?|我也(?:一樣|開始|覺得|感到)?|我和[^，。！？；\n]{0,12}(?:都|一樣))/;
  const speechOrMediaPattern = /(說|表示|告訴|問|寫著|提到|看起來|覺得我|歌詞|歌曲|電影|影集|文章|貼文|新聞|小說)/;
  const quotePattern = /[「『\"“].+[」』\"”]/;
  const subjectTextFromEvidence = (text) =>
    (safeText(text, 500).match(otherSubjectPattern) || [null])[0];
  const emotionInsideQuote = (text, rawText) => {
    const evidence = safeText(text, 500);
    const term = safeText(rawText, 100);
    if (!term) return false;
    const quotedParts = evidence.match(/[「『\"“][^」』\"”]+[」』\"”]/g) || [];
    return quotedParts.some((part) => part.includes(term));
  };
  const matchingEvidence = (item, rawText) => {
    const evidence = safeText(item?.evidence, 300);
    if (evidence) return evidence;
    return latestClauses.find((clause) => clause.includes(rawText)) || "";
  };
  const classifyEmotionSubject = (item, rawText, isExisting = false) => {
    const evidence = matchingEvidence(item, rawText);
    const requested = ["user", "other", "shared", "unknown"].includes(item?.subjectType)
      ? item.subjectType
      : null;
    const explicitUser = explicitUserPattern.test(evidence);
    const sharedUser = sharedUserPattern.test(evidence);
    const otherSubject = otherSubjectPattern.test(evidence);
    const emotionIndex = evidence.indexOf(rawText);
    const evidenceBeforeEmotion = emotionIndex >= 0
      ? evidence.slice(0, emotionIndex)
      : evidence;
    const lastUserBeforeEmotion = Math.max(
      evidenceBeforeEmotion.lastIndexOf("我"),
      evidenceBeforeEmotion.lastIndexOf("自己"),
    );
    let lastOtherBeforeEmotion = -1;
    for (const match of evidenceBeforeEmotion.matchAll(new RegExp(otherSubjectPattern.source, "g"))) {
      lastOtherBeforeEmotion = Math.max(lastOtherBeforeEmotion, match.index ?? -1);
    }
    const otherOwnsEmotion =
      lastOtherBeforeEmotion >= 0 && lastOtherBeforeEmotion > lastUserBeforeEmotion;
    const quoted = item?.isQuotedSpeech === true ||
      emotionInsideQuote(evidence, rawText) ||
      (otherSubject && speechOrMediaPattern.test(evidence));
    let subjectType = requested;
    if (isExisting && item?.source === "existingRecord") {
      subjectType = "user";
    } else if (quoted && !sharedUser) {
      subjectType = "other";
    } else if ((otherOwnsEmotion || (otherSubject && !explicitUser)) && !sharedUser) {
      subjectType = "other";
    } else if (sharedUser) {
      subjectType = "shared";
    } else if (!subjectType) {
      // Old drafts are migrated conservatively: never assume an unspecified
      // subject is the user without explicit first-person evidence.
      subjectType = explicitUser ? "user" : "unknown";
    }
    const source = safeText(item?.source, 40);
    const inferred = source === "inferred";
    return {
      subjectType,
      subjectText: subjectType === "other"
        ? safeText(item?.subjectText, 80) || subjectTextFromEvidence(evidence)
        : (safeText(item?.subjectText, 80) || (explicitUser ? "我" : null)),
      isQuotedSpeech: quoted,
      evidence,
      source,
      inferred,
      explicitUser,
      keep: (subjectType === "user" ||
        (subjectType === "shared" && explicitUser && !quoted)) &&
        !(quoted && subjectType !== "shared"),
    };
  };
  const latestClauses = safeText(latestMessage, 4000)
    .replace(/但|可是|不過|然而/g, "，")
    .split(/[，。！？；\n]+/)
    .map((clause) => clause.trim())
    .filter(Boolean);
  const timeContextFromClause = (clause) => {
    if (/昨天|昨晚/.test(clause)) return "昨天";
    if (/前天/.test(clause)) return "前天";
    if (/今天|今日/.test(clause)) return null;
    if (/早上|早晨/.test(clause)) return "早上";
    if (/中午/.test(clause)) return "中午";
    if (/下午/.test(clause)) return "下午";
    if (/晚上|今晚/.test(clause)) return "晚上";
    if (/剛剛|現在/.test(clause)) return "當下";
    return null;
  };
  const temporalScopeForMention = (item, dimension, rawText) => {
    const comparable = (value) =>
      safeText(value, 500).replace(/\s+|也|有點|還是|仍然|還|很|真的/g, "");
    const terms = [
      rawText,
      safeText(item?.evidence, 300),
      dimension?.displayName,
      ...(Array.isArray(dimension?.aliases) ? dimension.aliases : []),
    ]
      .map((term) => safeText(term, 300))
      .filter(Boolean)
      .sort((left, right) => right.length - left.length);
    for (let index = latestClauses.length - 1; index >= 0; index -= 1) {
      const clause = latestClauses[index];
      const comparableClause = comparable(clause);
      const matched = terms.some(
        (term) =>
          clause.includes(term) ||
          (comparable(term) &&
            comparableClause.includes(comparable(term))) ||
          (term.length >= 4 && term.includes(clause)),
      );
      if (matched) {
        return { matched: true, timeContext: timeContextFromClause(clause) };
      }
    }
    return { matched: false, timeContext: null };
  };
  const sleepFlagAliases = new Map([
    ["maintInsomnia", "interrupted"],
    ["earlyWake", "earlyWake"],
    ["light", "lightSleep"],
    ["lightSleep", "lightSleep"],
    ["dreams", "dreams"],
    ["lack", "insufficient"],
    ["insufficient", "insufficient"],
    ["fragile", "fragmented"],
    ["fragmented", "fragmented"],
    ["initInsomnia", "initInsomnia"],
    ["interrupted", "interrupted"],
    ["nocturia", "nocturia"],
    ["good", "good"],
    ["ok", "ok"],
  ]);
  const sleepFlagFromText = (value) => {
    const text = safeText(value, 120);
    if (/睡不著|難入睡|入睡困難|躺很久|翻來覆去|無法進入睡眠|闔眼.*張開/.test(text)) {
      return "initInsomnia";
    }
    if (/半夜.*醒|夜裡.*醒|反覆醒|睡眠中斷|維持睡眠/.test(text)) return "interrupted";
    if (/太早醒|提早醒|早醒/.test(text)) return "earlyWake";
    if (/淺眠|睡很淺/.test(text)) return "lightSleep";
    if (/多夢|惡夢|噩夢/.test(text)) return "dreams";
    if (/睡眠不足|沒睡飽|睡不夠/.test(text)) return "insufficient";
    if (/斷斷續續|睡睡醒醒/.test(text)) return "fragmented";
    if (/夜尿|半夜.*上廁所/.test(text)) return "nocturia";
    return null;
  };
  const mergeNames = (first, second, max) =>
    [...new Set([...(Array.isArray(first) ? first : []), ...(Array.isArray(second) ? second : [])]
      .map(itemName)
      .filter(Boolean))].slice(0, max);
  const emotionMap = new Map();
  const migratedEmotionSymptoms = new Set();
  const excludedEmotionEvents = new Set();
  const excludedEmotionTerms = new Set();
  const existingMentions = Array.isArray(existing.emotionMentions)
    ? existing.emotionMentions
    : (Array.isArray(existing.emotions) ? existing.emotions : []);
  for (const item of existingMentions) {
    const rawText = safeText(item?.rawText || itemName(item), 100);
    const symptomNames = symptomNamesFromText(
      `${rawText} ${safeText(item?.evidence, 300)}`,
    );
    if (symptomNames.length > 0) {
      for (const name of symptomNames) migratedEmotionSymptoms.add(name);
      continue;
    }
    const dimension = resolveDimension(item, rawText);
    const score = validScore(item?.value ?? item?.score);
    if (!rawText) continue;
    const subject = classifyEmotionSubject(item, rawText, true);
    if (!subject.keep) {
      excludedEmotionTerms.add(rawText);
      if (dimension?.displayName) excludedEmotionTerms.add(dimension.displayName);
      if (subject.subjectType === "other" && subject.evidence) {
        excludedEmotionEvents.add(subject.evidence);
      }
      continue;
    }
    const key = dimension?.id || `raw:${rawText}`;
    const inferredConfidence = subject.inferred
      ? Math.min(0.75, Number(item?.confidence) || 0)
      : Math.max(0, Math.min(1, Number(item?.confidence) || 0));
    emotionMap.set(key, {
      rawText,
      normalizedDimensionId: dimension?.id || null,
      normalizedDimensionName: dimension?.displayName || null,
      value: score,
      mentioned: item?.mentioned !== false,
      needsFollowUp: score == null,
      needsConfirmation: !dimension || subject.inferred || item?.needsConfirmation === true,
      confidence: inferredConfidence,
      source: item?.source || "existingRecord",
      timeContext: safeText(item?.timeContext, 40) || null,
      evidence: subject.evidence,
      subjectType: subject.subjectType,
      subjectText: subject.subjectText,
      isQuotedSpeech: subject.isQuotedSpeech,
    });
  }
  const rawMentions = Array.isArray(raw.emotionMentions)
    ? raw.emotionMentions
    : (Array.isArray(raw.emotions) ? raw.emotions : []);
  for (const item of rawMentions) {
    const rawText = safeText(item?.rawText || itemName(item), 100);
    if (!rawText) continue;
    const symptomNames = symptomNamesFromText(
      `${rawText} ${safeText(item?.evidence, 300)}`,
    );
    if (symptomNames.length > 0) {
      for (const name of symptomNames) migratedEmotionSymptoms.add(name);
      continue;
    }
    const dimension = resolveDimension(item, rawText);
    const score = validScore(item?.value ?? item?.score);
    const subject = classifyEmotionSubject(item, rawText);
    if (!subject.keep) {
      excludedEmotionTerms.add(rawText);
      if (dimension?.displayName) excludedEmotionTerms.add(dimension.displayName);
      if (subject.subjectType === "other" && subject.evidence) {
        excludedEmotionEvents.add(subject.evidence);
      }
      continue;
    }
    const key = dimension?.id || `raw:${rawText}`;
    const previousEmotion = emotionMap.get(key);
    const resolvedScore = score ?? previousEmotion?.value ?? null;
    const temporalScope = temporalScopeForMention(item, dimension, rawText);
    emotionMap.set(key, {
      rawText,
      normalizedDimensionId: dimension?.id || null,
      normalizedDimensionName: dimension?.displayName || null,
      value: resolvedScore,
      mentioned: item?.mentioned !== false,
      needsFollowUp: resolvedScore == null,
      needsConfirmation: !dimension || subject.inferred || item?.needsConfirmation === true,
      confidence: subject.inferred
        ? Math.min(0.75, Number(item?.confidence) || 0)
        : Math.max(0, Math.min(1, Number(item?.confidence) || 0)),
      source:
        item?.source === "explicit" || item?.source === "explicitUserInput"
          ? "explicitUserInput"
          : item?.source || "aiExtracted",
      timeContext: temporalScope.matched
        ? temporalScope.timeContext
        : previousEmotion?.timeContext || null,
      evidence: subject.evidence || previousEmotion?.evidence || "",
      subjectType: subject.subjectType,
      subjectText: subject.subjectText,
      isQuotedSpeech: subject.isQuotedSpeech,
    });
  }
  const oldSleep = existing.sleep && typeof existing.sleep === "object" ? existing.sleep : {};
  const nextSleep = raw.sleep && typeof raw.sleep === "object" ? raw.sleep : {};
  const sleepFlags = new Set();
  for (const flag of [...(Array.isArray(oldSleep.flags) ? oldSleep.flags : []), ...(Array.isArray(nextSleep.flags) ? nextSleep.flags : [])]) {
    const normalized = sleepFlagAliases.get(safeText(flag, 40)) || sleepFlagFromText(flag);
    if (normalized) sleepFlags.add(normalized);
  }
  const symptoms = [...migratedEmotionSymptoms];
  for (const item of [...(Array.isArray(existing.symptoms) ? existing.symptoms : []), ...(Array.isArray(raw.symptoms) ? raw.symptoms : [])]) {
    const name = itemName(item);
    if (!name) continue;
    const sleepFlag = sleepFlagFromText(name);
    if (sleepFlag) {
      sleepFlags.add(sleepFlag);
    } else {
      const canonicalNames = symptomNamesFromText(name);
      if (canonicalNames.length > 0) {
        for (const canonicalName of canonicalNames) {
          if (!symptoms.includes(canonicalName)) symptoms.push(canonicalName);
        }
      } else if (!symptoms.includes(name)) {
        symptoms.push(name);
      }
    }
  }
  const explicitSleepTimes = extractExplicitSleepTimes(latestMessage);
  const sleep = {
    sleepTime: validTime(nextSleep.sleepTime) || validTime(oldSleep.sleepTime),
    wakeTime: explicitSleepTimes.wakeTime || validTime(nextSleep.wakeTime) || validTime(oldSleep.wakeTime),
    finalWakeTime: explicitSleepTimes.finalWakeTime || validTime(nextSleep.finalWakeTime) || validTime(oldSleep.finalWakeTime),
    quality: validScore(nextSleep.quality) || validScore(oldSleep.quality),
    midWakeList: safeText(nextSleep.midWakeList, 300) || safeText(oldSleep.midWakeList, 300),
    flags: [...sleepFlags].slice(0, 12),
    naps: Array.isArray(nextSleep.naps) ? nextSleep.naps.slice(0, 6) : (Array.isArray(oldSleep.naps) ? oldSleep.naps.slice(0, 6) : []),
  };
  const overallMood = validScore(raw.overallMood) ?? validScore(existing.overallMood);
  const pendingEmotionFields = [...emotionMap.values()]
    .filter((item) => item.value == null || item.normalizedDimensionId == null)
    .map((item) => `${item.rawText}的正式情緒與強度`);
  const result = {
    date: safeText(raw.date || existing.date, 10),
    moodScale: 5,
    overallMood: overallMood,
    emotionMentions: [...emotionMap.values()].slice(0, 20),
    symptoms: symptoms.slice(0, 30),
    stateChanges,
    bodyMeasurement,
    sleep,
    events: mergeNames(
      mergeNames(existing.events, raw.events, 12),
      [...excludedEmotionEvents],
      12,
    ),
    diaryText: safeText(raw.diaryText ?? raw.diaryTextDraft, 8000) ||
      safeText(existing.diaryText ?? existing.diaryTextDraft, 8000),
    missingFields: mergeNames([], [
      ...(Array.isArray(raw.missingFields)
        ? raw.missingFields.filter((field) =>
          ![...excludedEmotionTerms].some((term) => safeText(field, 200).includes(term)))
        : []),
      ...pendingEmotionFields,
    ], 20),
  };
  Object.defineProperty(result, "excludedEmotionTerms", {
    value: [...excludedEmotionTerms],
    enumerable: false,
  });
  return result;
}

module.exports = {
  normalizeInneraRecordDraft,
};
