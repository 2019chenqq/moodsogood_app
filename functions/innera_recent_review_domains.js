"use strict";

const DOMAIN_ORDER = Object.freeze([
  "sleep",
  "emotion",
  "symptom",
  "medication",
  "period",
]);

const DOMAIN_PATTERNS = Object.freeze({
  sleep: /睡眠|睡覺|入睡|夜眠|失眠|早醒|睡醒|小睡|睡眠品質/u,
  emotion: /情緒|心情|焦慮|緊張|低落|憂鬱|煩躁|興奮|平靜|難過|害怕/u,
  symptom: /症狀|身體|不舒服|心悸|頭痛|噁心|反胃|疲倦|疲憊|手抖|胃痛|嗜睡/u,
  medication: /用藥|服藥|調藥|劑量|停藥|新增藥物|服用時間|藥物|吃藥|藥/u,
  period: /經期|生理期|月經/u,
});

const EXPLICIT_OVERALL_PATTERN = /近況|整體|全部|總結|回顧(?:近期|近況)/u;
const GENERAL_CHANGE_PATTERN = /最近(?:有什麼|有哪些|是否有).{0,6}變化/u;

function selectRecentReviewDomains(latestUserMessage) {
  const message = String(latestUserMessage || "").trim();
  if (EXPLICIT_OVERALL_PATTERN.test(message)) {
    return { selectedDomains: ["overall"], usedDomainFallback: false };
  }
  const selectedDomains = DOMAIN_ORDER.filter((domain) =>
    DOMAIN_PATTERNS[domain].test(message),
  );
  if (selectedDomains.length > 0) {
    return { selectedDomains, usedDomainFallback: false };
  }
  if (GENERAL_CHANGE_PATTERN.test(message)) {
    return { selectedDomains: ["overall"], usedDomainFallback: false };
  }
  return { selectedDomains: ["overall"], usedDomainFallback: true };
}

function selectRecentReviewSummary(summary, selection) {
  if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
    return summary;
  }
  const domains = selection?.selectedDomains || ["overall"];
  if (domains.includes("overall")) return summary;
  const selected = { period: summary.period };
  if (domains.includes("sleep")) selected.sleep = summary.sleep;
  if (domains.includes("emotion")) selected.emotions = summary.emotions;
  if (domains.includes("symptom")) selected.symptoms = summary.symptoms;
  if (domains.includes("medication")) {
    selected.medications = summary.medications;
    selected.medicationChanges = summary.medicationChanges;
  }
  if (domains.includes("period")) selected.periodCycles = summary.periodCycles;
  return selected;
}

function selectRecentReviewEvidence(evidence, selection) {
  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    return evidence;
  }
  const domains = selection?.selectedDomains || ["overall"];
  if (domains.includes("overall")) return evidence;
  const selected = {};
  for (const domain of domains) {
    if (Object.hasOwn(evidence, domain)) selected[domain] = evidence[domain];
  }
  return selected;
}

module.exports = {
  selectRecentReviewDomains,
  selectRecentReviewEvidence,
  selectRecentReviewSummary,
};
