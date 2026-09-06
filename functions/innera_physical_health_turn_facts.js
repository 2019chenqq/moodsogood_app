"use strict";

const {
  extractExplicitPhysicalSymptoms,
} = require("./innera_event_drafts");
const {
  resolveCanonicalSymptom,
} = require("./innera_canonical_concepts");

const physicalHealthTurnFactsSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "time",
    "symptoms",
    "stateChanges",
    "bodyMeasurements",
    "recurrence",
    "correction",
    "symptomReferenceUnresolved",
  ],
  properties: {
    time: {
      type: "object",
      additionalProperties: false,
      required: ["date", "time", "timeContext", "precision"],
      properties: {
        date: { type: ["string", "null"] },
        time: { type: ["string", "null"] },
        timeContext: { type: ["string", "null"] },
        precision: {
          type: ["string", "null"],
          enum: ["exact", "approximate", "unspecified", null],
        },
      },
    },
    symptoms: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "canonicalId",
          "displayName",
          "rawPhrase",
          "name",
          "severity",
        ],
        properties: {
          canonicalId: { type: ["string", "null"] },
          displayName: { type: ["string", "null"] },
          rawPhrase: { type: ["string", "null"] },
          name: { type: "string" },
          severity: { type: ["integer", "null"], minimum: 1, maximum: 5 },
        },
      },
    },
    stateChanges: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "value"],
        properties: {
          name: {
            type: "string",
            enum: ["energy_change", "appetite_change", "activity_change"],
          },
          value: { type: "integer", minimum: 1, maximum: 5 },
        },
      },
    },
    bodyMeasurements: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "value", "unit"],
        properties: {
          type: { type: "string", enum: ["weight", "bodyFat", "waist"] },
          value: { type: "number" },
          unit: { type: "string" },
        },
      },
    },
    recurrence: { type: "boolean" },
    correction: { type: "boolean" },
    symptomReferenceUnresolved: { type: "boolean" },
  },
};

const recurrencePattern = /(?:又|再|再次|又一次|再一次)[^，。！？]{0,16}(?:痛|發作|出現|不舒服)/u;
const correctionPattern = /(?:剛剛那筆|剛才那筆|前面那筆|上一筆|前一筆|那筆)[^，。！？]{0,24}(?:其實|不是|改成|應該是)|(?:時間|時段)[^，。！？]{0,12}(?:說錯|修正|改成)/u;

function extractPhysicalHealthTurnFacts(message, options = {}) {
  const text = String(message || "").trim();
  const symptoms = dedupeSymptoms(extractExplicitPhysicalSymptoms(text));
  const recurrence = recurrencePattern.test(text);
  const correction = correctionPattern.test(text);
  const time = extractTurnTime(text, options.now);
  const facts = {
    time,
    symptoms,
    stateChanges: extractStateChanges(text),
    bodyMeasurements: extractBodyMeasurements(text),
    recurrence,
    correction,
    symptomReferenceUnresolved: recurrence && symptoms.length === 0,
  };
  if (options.debug === true) {
    console.log("Innera physicalHealth turn facts", {
      factCount: countFacts(facts),
      symptomCount: facts.symptoms.length,
      hasExplicitTime: facts.time.time !== null,
      recurrence: facts.recurrence,
      correction: facts.correction,
    });
  }
  return facts;
}

function extractStateChanges(message) {
  const rules = [
    ["energy_change", /(?:能量|精力|體力)[^，。！？\n]{0,10}?([1-5１-５])\s*分/u],
    ["appetite_change", /(?:食慾|胃口)[^，。！？\n]{0,10}?([1-5１-５])\s*分/u],
    ["activity_change", /(?:活動量|活動程度)[^，。！？\n]{0,10}?([1-5１-５])\s*分/u],
  ];
  return rules.flatMap(([name, pattern]) => {
    const match = message.match(pattern);
    const value = score(match?.[1]);
    return value === null ? [] : [{ name, value }];
  });
}

function extractBodyMeasurements(message) {
  const rules = [
    ["weight", /體重\s*(\d+(?:\.\d+)?)\s*(公斤|kg|KG)/u, "kg"],
    ["bodyFat", /(?:體脂|體脂率)\s*(\d+(?:\.\d+)?)\s*(%|％)/u, "%"],
    ["waist", /腰圍\s*(\d+(?:\.\d+)?)\s*(公分|cm|CM)/u, "cm"],
  ];
  return rules.flatMap(([type, pattern, unit]) => {
    const match = message.match(pattern);
    const value = Number(match?.[1]);
    return Number.isFinite(value) ? [{ type, value, unit }] : [];
  });
}

function score(value) {
  if (!value) return null;
  const fullWidth = "１２３４５";
  const normalized = fullWidth.includes(value)
    ? fullWidth.indexOf(value) + 1
    : Number(value);
  return Number.isInteger(normalized) && normalized >= 1 && normalized <= 5
    ? normalized
    : null;
}

function dedupeSymptoms(symptoms) {
  const result = new Map();
  for (const symptom of symptoms) {
    const concept = resolveCanonicalSymptom(symptom.name);
    const key = concept?.id || `raw:${symptom.name}`;
    const previous = result.get(key);
    result.set(key, {
      canonicalId: concept?.id || null,
      displayName: concept?.displayName || null,
      rawPhrase: null,
      name: symptom.name,
      severity: symptom.severity ?? previous?.severity ?? null,
    });
  }
  return [...result.values()];
}

function extractTurnTime(message, referenceNow) {
  const clock = extractClock(message);
  const date = extractDate(message, referenceNow);
  const timeContext = extractTimeContext(message);
  return {
    date,
    time: clock,
    timeContext,
    precision: clock
      ? "exact"
      : timeContext
        ? "approximate"
        : null,
  };
}

function extractClock(message) {
  const colon = message.match(/(?:^|\D)([01]?\d|2[0-3])[:：]([0-5]\d)(?:\D|$)/u);
  if (colon) return `${colon[1].padStart(2, "0")}:${colon[2]}`;
  const match = message.match(
    /(早上|上午|中午|下午|傍晚|晚上|凌晨)?\s*([零〇一二兩三四五六七八九十\d]{1,3})\s*點(?:\s*([零〇一二兩三四五六七八九十\d]{1,2})\s*分|半)?/u,
  );
  if (!match) return null;
  let hour = chineseNumber(match[2]);
  if (hour === null || hour > 23) return null;
  const context = match[1] || "";
  if (/下午|傍晚|晚上/u.test(context) && hour < 12) hour += 12;
  if (context === "中午" && hour < 11) hour += 12;
  if (context === "凌晨" && hour === 12) hour = 0;
  const minute = message.slice(match.index, match.index + match[0].length).includes("半")
    ? 30
    : chineseNumber(match[3]) ?? 0;
  if (minute > 59) return null;
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function extractTimeContext(message) {
  const match = message.match(/昨天晚上|昨晚|昨天|早上|上午|中午|下午|傍晚|晚上|凌晨/u);
  if (match) return match[0];
  if (/剛剛/u.test(message)) return "剛剛";
  if (/剛才/u.test(message)) return "剛才";
  if (/現在/u.test(message)) return "現在";
  return match?.[0] || null;
}

function extractDate(message, referenceNow) {
  if (!/昨天|昨晚/u.test(message)) return null;
  const now = validDate(referenceNow) || new Date();
  const previous = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  return [
    previous.getFullYear(),
    String(previous.getMonth() + 1).padStart(2, "0"),
    String(previous.getDate()).padStart(2, "0"),
  ].join("-");
}

function validDate(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}

function chineseNumber(value) {
  if (value == null || value === "") return null;
  if (/^\d+$/u.test(value)) return Number(value);
  const digits = { 零: 0, 〇: 0, 一: 1, 二: 2, 兩: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  if (value === "十") return 10;
  const ten = value.indexOf("十");
  if (ten >= 0) {
    const tens = ten === 0 ? 1 : digits[value.slice(0, ten)];
    const ones = ten === value.length - 1 ? 0 : digits[value.slice(ten + 1)];
    return tens == null || ones == null ? null : tens * 10 + ones;
  }
  return digits[value] ?? null;
}

function countFacts(facts) {
  return facts.symptoms.length +
    facts.stateChanges.length +
    facts.bodyMeasurements.length +
    (facts.time.date || facts.time.time || facts.time.timeContext ? 1 : 0) +
    (facts.recurrence ? 1 : 0) +
    (facts.correction ? 1 : 0);
}

module.exports = {
  extractPhysicalHealthTurnFacts,
  physicalHealthTurnFactsSchema,
};
