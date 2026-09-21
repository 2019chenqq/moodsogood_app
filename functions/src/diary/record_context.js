const {
  toNumber,
  clamp,
  toCleanString,
  normalizeMoodScore,
} = require("../shared/normalization");

const CRISIS_KEYWORDS = [
  "想死",
  "不想活",
  "自殺",
  "傷害自己",
  "結束生命",
  "活不下去",
  "去死",
  "消失掉",
  "了結",
];

const DIARY_FIELD_KEYS = [
  "title",
  "content",
  "themeSong",
  "highlight",
  "metaphor",
  "conceited",
  "proudOf",
  "selfCare",
  "gratitude",
];

const NEGATIVE_WORDS = [
  "痛苦",
  "崩潰",
  "焦慮",
  "害怕",
  "低落",
  "沮喪",
  "疲憊",
  "絕望",
  "無助",
];

const POSITIVE_WORDS = [
  "感謝",
  "開心",
  "平靜",
  "放鬆",
  "完成",
  "進步",
  "溫暖",
  "期待",
  "希望",
];

function detectCrisis(text) {
  const source = String(text || "");
  return CRISIS_KEYWORDS.some((keyword) => source.includes(keyword));
}

function normalizeDiaryFields(rawDiaryFields) {
  const raw =
    rawDiaryFields && typeof rawDiaryFields === "object" && !Array.isArray(rawDiaryFields)
      ? rawDiaryFields
      : {};

  const result = {};
  for (const key of DIARY_FIELD_KEYS) {
    result[key] = String(raw[key] || "").trim().slice(0, 1200);
  }

  // 也帶上三個分數欄位，方便模型補充判讀
  result.overallMood = toNumber(raw.overallMood, null);
  result.overallHealth = toNumber(raw.overallHealth, null);

  return result;
}

function buildDiaryTextFromFields(fields) {
  const sections = [
    ["標題", fields.title],
    ["內容", fields.content],
    ["今日主題曲", fields.themeSong],
    ["最想記錄的瞬間", fields.highlight],
    ["今天情緒像", fields.metaphor],
    ["為自己感到驕傲", fields.conceited],
    ["做得不錯的地方", fields.proudOf],
    ["可多照顧自己的地方", fields.selfCare],
    ["今日感恩事項", fields.gratitude],
  ]
    .filter(([, value]) => Boolean(value))
    .map(([label, value]) => `${label}: ${value}`);

  return sections.join("\n");
}

function countHits(source, words) {
  return words.reduce((acc, w) => acc + (source.includes(w) ? 1 : 0), 0);
}

function extractEmotionEntries(dailyRecord) {
  const raw = dailyRecord?.emotions;
  const entries = [];

  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (!item || typeof item !== "object") continue;
      const name = String(item.name || "").trim();
      const value = toNumber(item.value, null);
      if (!name || value == null) continue;
      entries.push({ name, score: clamp(Number(value), 0, 10) });
    }
  } else if (raw && typeof raw === "object") {
    for (const [name, value] of Object.entries(raw)) {
      const score = toNumber(value, null);
      if (!name || score == null) continue;
      entries.push({ name: String(name).trim(), score: clamp(Number(score), 0, 10) });
    }
  }

  return entries;
}

function pickEmotionScore(entries, keywords) {
  const found = entries.find((e) => keywords.some((k) => e.name.includes(k)));
  return found ? found.score : null;
}

function collectMedicationNames(source, bucket) {
  if (!source) return;

  if (typeof source === "string") {
    const s = toCleanString(source);
    if (s) bucket.add(s);
    return;
  }

  if (Array.isArray(source)) {
    source.forEach((item) => collectMedicationNames(item, bucket));
    return;
  }

  if (typeof source === "object") {
    const name =
      toCleanString(source.name) ||
      toCleanString(source.label) ||
      toCleanString(source.title) ||
      toCleanString(source.medicationName) ||
      toCleanString(source.drugName);

    if (name) {
      bucket.add(name);
      return;
    }

    Object.values(source).forEach((value) => collectMedicationNames(value, bucket));
  }
}

function extractMedicationInfo(dailyRecord) {
  const names = new Set();

  collectMedicationNames(dailyRecord.medication, names);
  collectMedicationNames(dailyRecord.medications, names);
  collectMedicationNames(dailyRecord.medicines, names);

  const sleep =
    dailyRecord.sleep && typeof dailyRecord.sleep === "object" ? dailyRecord.sleep : {};
  const hypnoticName = toCleanString(sleep.hypnoticName || dailyRecord.hypnoticName);
  const hypnoticDose = toCleanString(sleep.hypnoticDose || dailyRecord.hypnoticDose);
  const tookHypnotic = sleep.tookHypnotic === true || dailyRecord.tookHypnotic === true;

  if (hypnoticName) {
    names.add(hypnoticDose ? `安眠藥:${hypnoticName}(${hypnoticDose})` : `安眠藥:${hypnoticName}`);
  } else if (tookHypnotic) {
    names.add("安眠藥");
  }

  const medicationNames = Array.from(names);
  const hasMedicationData =
    medicationNames.length > 0 ||
    Boolean(dailyRecord.medication) ||
    Boolean(dailyRecord.medications) ||
    Boolean(dailyRecord.medicines);

  return {
    hasMedicationData,
    medicationNames,
    medicationCount: medicationNames.length,
    tookHypnotic,
  };
}

function buildEmotionModel(dailyRecord, diaryFields, diaryText) {
  const emotionEntries = extractEmotionEntries(dailyRecord);
  const medication = extractMedicationInfo(dailyRecord);
  const moodScale = toNumber(
    dailyRecord.moodScale ?? diaryFields.moodScale ?? dailyRecord.diaryMoodScale,
    10,
  );
  const useFivePointScale = moodScale === 5;
  const mood = normalizeMoodScore(
    dailyRecord.overallMood ?? diaryFields.overallMood ?? dailyRecord.mood,
    moodScale,
    useFivePointScale ? 3 : 5,
  );
  const health = normalizeMoodScore(
    dailyRecord.overallHealth ?? diaryFields.overallHealth ?? dailyRecord.health,
    moodScale,
    useFivePointScale ? 3 : 5,
  );
  const anxiety = toNumber(dailyRecord.anxiety, null) ?? pickEmotionScore(emotionEntries, ["焦慮", "緊張", "擔心"]);
  const energy = toNumber(dailyRecord.energy, null) ?? pickEmotionScore(emotionEntries, ["能量", "活力", "精力"]);

  const text = String(diaryText || "");
  const negativeHits = countHits(text, NEGATIVE_WORDS);
  const positiveHits = countHits(text, POSITIVE_WORDS);
  const symptomsCount = Array.isArray(dailyRecord.symptoms) ? dailyRecord.symptoms.length : 0;

  let compositeScore = mood * 0.55 + health * 0.25;
  if (energy != null) {
    compositeScore += energy * 0.2;
  }
  if (anxiety != null) {
    // 焦慮越高，綜合情緒分數略微下修
    compositeScore -= (anxiety - 5) * 0.22;
  }

  const emotionAvg =
    emotionEntries.length > 0
      ? emotionEntries.reduce((acc, e) => acc + e.score, 0) / emotionEntries.length
      : null;

  if (emotionAvg != null) {
    compositeScore = compositeScore * 0.75 + emotionAvg * 0.25;
  }

  compositeScore += (positiveHits - negativeHits) * 0.2;
  compositeScore -= symptomsCount * 0.08;
  compositeScore = clamp(Number(compositeScore.toFixed(2)), 1, moodScale === 5 ? 5 : 10);

  let moodBand = "平穩";
  if (compositeScore >= 4.2) moodBand = "積極穩定";
  else if (compositeScore < 2.8) moodBand = "低潮偏高";

  let anxietyRisk = "未知";
  if (anxiety != null) {
    if (anxiety >= 7) anxietyRisk = "高";
    else if (anxiety >= 5) anxietyRisk = "中";
    else anxietyRisk = "低";
  }

  const topHighEmotions = [...emotionEntries]
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);
  const topLowEmotions = [...emotionEntries]
    .sort((a, b) => a.score - b.score)
    .slice(0, 2);

  return {
    compositeScore,
    moodBand,
    emotionEntries,
    topHighEmotions,
    topLowEmotions,
    drivers: {
      mood,
      health,
      anxiety,
      energy,
      emotionAvg,
      symptomsCount,
      positiveHits,
      negativeHits,
      medicationCount: medication.medicationCount,
      tookHypnotic: medication.tookHypnotic,
    },
    risks: {
      anxietyRisk,
      symptomBurden: symptomsCount >= 5 ? "高" : symptomsCount >= 3 ? "中" : "低",
    },
    medication,
  };
}

module.exports = {
  normalizeDiaryFields,
  buildDiaryTextFromFields,
  detectCrisis,
  buildEmotionModel,
};
