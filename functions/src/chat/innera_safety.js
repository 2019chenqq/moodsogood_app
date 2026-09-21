"use strict";

const safetyKeywords = Object.freeze([
  "不想活了",
  "不想活",
  "好想死",
  "想死",
  "去死",
  "不想醒來",
  "希望不要醒來",
  "活不下去",
  "想消失",
  "想結束生命",
  "結束自己",
  "想自殺",
  "傷害自己",
  "自殺",
  "想自s",
  "自s",
  "自傷",
  "自殘",
  "割自己",
  "輕生",
  "割腕",
  "跳樓",
  "吞藥",
]);

const generalDiscussionTerms = [
  "防治專線",
  "專線是多少",
  "電話是多少",
  "新聞",
  "報導",
  "文章",
  "研究",
  "討論",
  "議題",
  "什麼是",
  "是什麼意思",
];

const otherSubjectTerms = [
  "朋友",
  "同學",
  "同事",
  "家人",
  "爸爸",
  "媽媽",
  "弟弟",
  "妹妹",
  "哥哥",
  "姐姐",
  "姊姊",
  "男友",
  "女友",
  "伴侶",
  "他說",
  "她說",
  "他想",
  "她想",
];

const userIntentTerms = [
  "我也",
  "我自己",
  "我有想",
  "我想死",
  "我想自殺",
  "我想自s",
  "我不想活",
  "我想傷害自己",
];

const methodTerms = ["割腕", "跳樓", "吞藥", "上吊", "刀", "藥", "工具"];
const timingTerms = ["等一下", "現在就", "今晚", "今天就", "馬上"];
const preparationTerms = ["準備好工具", "工具在身邊", "藥在身邊", "刀在身邊"];
const unsafeTerms = ["不能保證安全", "無法保證安全", "控制不了"];

function normalizeSafetyText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[\s\u200B-\u200D\uFEFF_－—-]+/gu, "")
    .replace(/ｓ/gu, "s");
}

function isNegatedAt(source, index) {
  const prefix = source.slice(Math.max(0, index - 12), index);
  return [
    "沒有",
    "沒想",
    "沒要",
    "並沒有",
    "並不",
    "不會",
    "不是",
    "未曾",
    "沒有打算",
    "不想要",
  ].some((term) => prefix.includes(term));
}

function hasNonNegatedTerm(source, term) {
  let index = source.indexOf(term);
  while (index >= 0) {
    if (!isNegatedAt(source, index)) return true;
    index = source.indexOf(term, index + term.length);
  }
  return false;
}

function isGeneralDiscussion(clause) {
  return generalDiscussionTerms.some((term) => clause.includes(term));
}

function isClearlyAboutAnotherPerson(clause) {
  const hasOtherSubject = otherSubjectTerms.some((term) => clause.includes(term));
  const hasUserIntent = userIntentTerms.some((term) => clause.includes(term));
  return hasOtherSubject && !hasUserIntent;
}

function detectInneraSelfHarm(text) {
  const source = normalizeSafetyText(text);
  if (!source) {
    return { detected: false, level: "none", matchedKeywords: [] };
  }

  const matchedKeywords = new Set();
  for (const clause of source.split(/[，。！？!?；;\n]/u)) {
    if (isGeneralDiscussion(clause) || isClearlyAboutAnotherPerson(clause)) {
      continue;
    }
    for (const keyword of safetyKeywords) {
      if (hasNonNegatedTerm(clause, keyword)) matchedKeywords.add(keyword);
    }
  }

  if (matchedKeywords.size === 0) {
    return { detected: false, level: "none", matchedKeywords: [] };
  }

  const urgent = [methodTerms, timingTerms, preparationTerms, unsafeTerms]
    .some((terms) => terms.some((term) => source.includes(term)));
  return {
    detected: true,
    level: urgent ? "urgent" : "concern",
    matchedKeywords: [...matchedKeywords],
  };
}

function createInneraSafetyResponse({ existingRecordDraft, safetyLevel }) {
  const recordDraft = existingRecordDraft &&
    typeof existingRecordDraft === "object" &&
    !Array.isArray(existingRecordDraft) &&
    Object.keys(existingRecordDraft).length > 0
    ? existingRecordDraft
    : null;
  const eventDrafts = Array.isArray(recordDraft?.eventDrafts)
    ? recordDraft.eventDrafts
    : [];
  return {
    reply: "",
    followUpQuestion: null,
    sources: [],
    suggestedActions: [],
    recordDraft,
    eventDrafts,
    safetyLevel,
    requiresFixedSafetyUi: true,
    model: null,
  };
}

module.exports = {
  createInneraSafetyResponse,
  detectInneraSelfHarm,
  normalizeSafetyText,
  safetyKeywords,
};
