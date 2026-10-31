"use strict";
const { requireThat } = require("./protocol");
const TYPES = Object.freeze(["sleepRecords", "healthEvents", "checkIns", "medications", "dailyRecords"]);
const FLAGS = Object.freeze({ sleepRecords: "sleepSharingEnabled", healthEvents: "healthEventSharingEnabled", checkIns: "checkInSharingEnabled", medications: "medicationSharingEnabled", dailyRecords: "dailyRecordSharingEnabled" });
function validateLegacySummary(value) {
  const exact = (v, fields) => v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === fields.length && fields.every(k => Object.hasOwn(v, k));
  const date = v => typeof v === "string" && Number.isFinite(Date.parse(v)) && new Date(v).toISOString() === v;
  requireThat(exact(value, ["schemaVersion", "synthetic", "model", "generatedAt", "sourcePeriod", "sourceVersions", "domains"])
    && value.schemaVersion === 1 && value.synthetic === true && value.model === "deterministic-demo-v1" && date(value.generatedAt), "data-loss");
  requireThat(exact(value.sourcePeriod, ["start", "end"]) && [value.sourcePeriod.start, value.sourcePeriod.end].every(v => v === null || date(v)), "data-loss");
  requireThat(exact(value.sourceVersions, TYPES) && exact(value.domains, TYPES), "data-loss");
  for (const type of TYPES) {
    const ref = value.sourceVersions[type], domain = value.domains[type];
    requireThat(exact(ref, ["active", "epoch", "consentVersion"]) && typeof ref.active === "boolean" && Number.isSafeInteger(ref.epoch) && ref.epoch >= 0 &&
      [0, 1].includes(ref.consentVersion) && (!ref.active || (ref.epoch > 0 && ref.consentVersion === 1)), "data-loss");
    requireThat(ref.active ? exact(domain, ["recordCount", "summary"]) && Number.isInteger(domain.recordCount) && domain.recordCount >= 0 && domain.recordCount <= 30 &&
      typeof domain.summary === "string" && domain.summary.length <= 1000 : domain === null, "data-loss");
  }
  return value;
}
function validateSummary(value) {
  if ([3, 4].includes(value?.schemaVersion)) {
    requireThat(value.model === "gpt-4.1-mini" && typeof value.patternSummary === "string" && value.patternSummary.length <= 600, "data-loss");
    const { patternSummary, ...base } = value;
    validateSummary({ ...base, schemaVersion: 2, model: "deterministic-demo-v1" });
    return value;
  }
  if (value?.schemaVersion === 1) return validateLegacySummary(value);
  const exact = (v, fields) => v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === fields.length && fields.every(k => Object.hasOwn(v, k));
  const date = v => typeof v === "string" && Number.isFinite(Date.parse(v)) && new Date(v).toISOString() === v;
  requireThat(exact(value, ["schemaVersion", "synthetic", "model", "generatedAt", "sourcePeriod", "sources", "domains"]) && value.schemaVersion === 2 && value.synthetic === true && value.model === "deterministic-demo-v1" && date(value.generatedAt), "data-loss");
  requireThat(exact(value.sourcePeriod, ["start", "end"]) && [value.sourcePeriod.start, value.sourcePeriod.end].every(v => v === null || date(v)), "data-loss");
  const used = Object.keys(value.sources || {});
  requireThat(used.length > 0 && used.every(t => TYPES.includes(t)) && exact(value.sources, used) && exact(value.domains, used), "data-loss");
  for (const type of used) {
    const ref = value.sources[type], domain = value.domains[type];
    requireThat(exact(ref, ["epoch", "consentVersion"]) && Number.isSafeInteger(ref.epoch) && ref.epoch > 0 && ref.consentVersion === 1, "data-loss");
    requireThat(exact(domain, ["recordCount", "summary"]) && Number.isInteger(domain.recordCount) && domain.recordCount >= 0 && domain.recordCount <= 30 && typeof domain.summary === "string" && domain.summary.length <= 1000, "data-loss");
  }
  return value;
}
// No network, prompt, analytics, input/output logging or free-text quotation.
// Only normalized quantities are consumed. Dates/version references stay encrypted.
function normalize(sources) {
  const average = values => values.length ? Math.round(values.reduce((a, b) => a + b, 0) / values.length * 100) / 100 : null;
  const normalized = {}, dates = [];
  for (const type of TYPES) {
    if (!Object.hasOwn(sources, type)) continue;
    const records = sources[type];
    for (const record of records) {
      const date = record.date || record.timestamp || record.startDate;
      if (date) dates.push(new Date(date).toISOString());
    }
    const count = records.length;
    normalized[type] = { count };
    if (type === "sleepRecords") normalized[type].meanMinutes = average(records.map(r => r.durationMinutes));
    if (type === "checkIns") {
      normalized[type].meanMood = average(records.map(r => r.overallMood));
      normalized[type].meanHealth = average(records.map(r => r.healthStatus));
    }
    if (type === "healthEvents") normalized[type].symptomEntries = records.reduce((n, r) => n + r.symptoms.length, 0);
    if (type === "medications") normalized[type].activeCount = records.filter(r => r.isActive).length;
    if (type === "dailyRecords") normalized[type].meanMood = average(records.map(r => r.overallMood).filter(Number.isFinite));
  }
  dates.sort();
  return { normalized, sourcePeriod: { start: dates[0] || null, end: dates.at(-1) || null } };
}
function summarize({ normalized, sourcePeriod }, sourceVersions, generatedAt) {
  const domains = {};
  for (const type of TYPES) {
    const n = normalized[type];
    if (!n) continue;
    const details = { sleepRecords: `平均睡眠分鐘：${n.meanMinutes ?? "無資料"}`, healthEvents: `症狀項目數：${n.symptomEntries}`,
      checkIns: `平均情緒：${n.meanMood ?? "無資料"}；平均健康狀態：${n.meanHealth ?? "無資料"}`,
      medications: `使用中假藥物：${n.activeCount}`, dailyRecords: `平均整體情緒：${n.meanMood ?? "無資料"}` };
    domains[type] = { recordCount: n.count, summary: `合成測試紀錄 ${n.count} 筆。${details[type]}。僅為固定規則整理，不是 AI 臨床判斷。` };
  }
  const sources = Object.fromEntries(TYPES.filter(t => sourceVersions[t].active).map(t => [t, { epoch: sourceVersions[t].epoch, consentVersion: sourceVersions[t].consentVersion }]));
  return validateSummary({ schemaVersion: 2, synthetic: true, model: "deterministic-demo-v1", generatedAt, sourcePeriod, sources, domains });
}
module.exports = { TYPES, FLAGS, validateSummary, normalize, summarize };
