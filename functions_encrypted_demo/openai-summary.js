"use strict";
const { requireThat, ShareError, validateSleep, validateHealthEvent, validateCheckIn, validateMedication, validateDailyRecord } = require("./protocol");
const { TYPES } = require("./summary-schema");
const MODEL = "gpt-4.1-mini";
const CODES = Object.freeze(["sleep_duration_minutes", "sleep_quality", "symptom_entry_count", "overall_mood", "health_status", "active_medication_count"]);
const object = (properties) => ({ type: "object", additionalProperties: false, required: Object.keys(properties), properties });
const requestSchema = object({ schemaVersion: { type: "integer", enum: [1] }, periodLabel: { type: "string" }, windowDays: { type: "integer", minimum: 1, maximum: 14 },
  domains: { type: "array", minItems: 1, maxItems: 5, items: object({ type: { type: "string", enum: TYPES },
    recordCount: { type: "integer", minimum: 0, maximum: 30 }, coverageDays: { type: "integer", minimum: 0, maximum: 14 },
    facts: { type: "array", maxItems: 10, items: object({ code: { type: "string", enum: CODES },
      value: { type: ["number", "null"] }, unit: { type: "string", enum: ["minutes", "score5", "count"] },
      sampleCount: { type: "integer", minimum: 0, maximum: 30 } }) } }) } });
const responseSchema = object({ schemaVersion: { type: "integer", enum: [2] }, periodText: { type: "string" }, domains: { type: "array", maxItems: 5, items: object({
  type: { type: "string", enum: TYPES }, status: { type: "string", enum: ["observed", "insufficient_data"] },
  factCodes: { type: "array", maxItems: 10, items: { type: "string", enum: CODES } }
}) } });
const periodLabel = days => `本摘要依目前授權之合成資料整理；資料日期跨度為${days}天，不代表完整連續紀錄。`;
const exact = (v, names) => v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === names.length && names.every(k => Object.hasOwn(v, k));
const FACT_TYPES = { sleepRecords: { sleep_duration_minutes: "minutes", sleep_quality: "score5" }, healthEvents: { symptom_entry_count: "count" }, checkIns: { overall_mood: "score5", health_status: "score5" }, medications: { active_medication_count: "count" }, dailyRecords: { overall_mood: "score5" } };
function normalizeExternal(sources) {
  requireThat(sources && Object.keys(sources).every(t => TYPES.includes(t)), "data-loss");
  const validators = { sleepRecords: validateSleep, healthEvents: validateHealthEvent, checkIns: validateCheckIn, medications: validateMedication, dailyRecords: validateDailyRecord };
  const dates = [];
  let total = 0;
  for (const [type, records] of Object.entries(sources)) {
    requireThat(Array.isArray(records) && records.length <= 30, "resource-exhausted"); total += records.length;
    for (const r of records) { validators[type](r); dates.push(Math.floor(Date.parse(r.date || r.timestamp || r.startDate) / 86400000)); }
  }
  requireThat(total <= 30 && Object.keys(sources).length > 0, "resource-exhausted");
  // Synthetic fixture dates can be historical. Anchor the window to the latest supplied day;
  // never describe it as the real current fortnight or silently truncate older records.
  const end = dates.length ? Math.max(...dates) : 0;
  requireThat(dates.every(d => Number.isSafeInteger(d) && end - d < 14), "failed-precondition");
  const facts = (code, unit, values) => ({ code, unit, sampleCount: values.length,
    value: values.length ? Math.round(values.reduce((a, b) => a + b, 0) / values.length * 100) / 100 : null });
  const domains = TYPES.filter(t => Object.hasOwn(sources, t)).map(type => {
    const records = sources[type], metrics = [];
    if (type === "sleepRecords") {
      metrics.push(facts("sleep_duration_minutes", "minutes", records.map(r => r.durationMinutes)));
      metrics.push(facts("sleep_quality", "score5", records.map(r => r.quality).filter(Number.isFinite)));
    }
    if (type === "healthEvents") metrics.push({ code: "symptom_entry_count", unit: "count", sampleCount: records.length, value: records.reduce((n, r) => n + r.symptoms.length, 0) });
    if (type === "checkIns" || type === "dailyRecords") metrics.push(facts("overall_mood", "score5", records.map(r => r.overallMood).filter(Number.isFinite)));
    if (type === "checkIns") metrics.push(facts("health_status", "score5", records.map(r => r.healthStatus)));
    if (type === "medications") metrics.push({ code: "active_medication_count", unit: "count", sampleCount: records.length, value: records.filter(r => r.isActive === true).length });
    return { type, recordCount: records.length, coverageDays: new Set(records.map(r => Math.floor(Date.parse(r.date || r.timestamp || r.startDate) / 86400000))).size, facts: metrics };
  });
  const windowDays = dates.length ? end - Math.min(...dates) + 1 : 1;
  return validateRequest({ schemaVersion: 1, periodLabel: periodLabel(windowDays), windowDays, domains });
}
function validateRequest(p) {
  requireThat(exact(p, ["schemaVersion", "periodLabel", "windowDays", "domains"]) && p.schemaVersion === 1 && Number.isInteger(p.windowDays) && p.windowDays >= 1 && p.windowDays <= 14 && p.periodLabel === periodLabel(p.windowDays) && Array.isArray(p.domains) && p.domains.length >= 1 && p.domains.length <= 5, "data-loss");
  const seen = new Set();
  for (const d of p.domains) {
    requireThat(exact(d, ["type", "recordCount", "coverageDays", "facts"]) && TYPES.includes(d.type) && !seen.has(d.type) && Number.isInteger(d.recordCount) && d.recordCount >= 0 && d.recordCount <= 30 && Number.isInteger(d.coverageDays) && d.coverageDays >= 0 && d.coverageDays <= p.windowDays && Array.isArray(d.facts) && d.facts.length <= 10, "data-loss"); seen.add(d.type);
    requireThat(new Set(d.facts.map(f => f.code)).size === d.facts.length, "data-loss");
    for (const f of d.facts) requireThat(exact(f, ["code", "unit", "sampleCount", "value"]) && CODES.includes(f.code) && FACT_TYPES[d.type][f.code] === f.unit && Number.isInteger(f.sampleCount) && f.sampleCount >= 0 && f.sampleCount <= d.recordCount && (f.value === null || (Number.isFinite(f.value) && f.value >= 0 && (f.unit !== "score5" || f.value <= 5) && (f.unit !== "count" || Number.isSafeInteger(f.value)))), "data-loss");
  }
  requireThat(p.domains.reduce((n, d) => n + d.recordCount, 0) <= 30 && Buffer.byteLength(JSON.stringify(p)) <= 32768, "resource-exhausted");
  return p;
}
// No provider prose is accepted or rendered. Only references to supplied facts survive.
function validateOutput(v, input) {
  validateRequest(input);
  requireThat(exact(v, ["schemaVersion", "periodText", "domains"]) && v.schemaVersion === 2 && v.periodText === input.periodLabel && Array.isArray(v.domains) && v.domains.length === input.domains.length, "data-loss");
  const seen = new Set();
  const labels = { sleep_duration_minutes: "睡眠紀錄平均時長（分鐘）", sleep_quality: "睡眠品質自評平均（滿分5）", symptom_entry_count: "症狀項目數（不代表嚴重程度）", overall_mood: "心情自評平均（滿分5）", health_status: "健康狀態自評平均（滿分5）", active_medication_count: "目前紀錄為使用中的用藥紀錄數（不代表實際服用）" };
  const domains = v.domains.map(d => {
    const source = input.domains.find(s => s.type === d.type);
    requireThat(source && !seen.has(d.type) && exact(d, ["type", "status", "factCodes"]) && Array.isArray(d.factCodes), "data-loss"); seen.add(d.type);
    const available = source.facts.filter(f => f.value !== null && f.sampleCount > 0);
    requireThat(d.status === (available.length ? "observed" : "insufficient_data") && d.factCodes.length === available.length && new Set(d.factCodes).size === d.factCodes.length && available.every(f => d.factCodes.includes(f.code)), "data-loss");
    const limitations = [source.type === "medications" ? `起始日期涵蓋${source.coverageDays}天，不能據此判斷服藥期間、依從性或實際服用。` : `紀錄日期涵蓋${source.coverageDays}天，不代表每天均有完整資料。`];
    if (source.type === "healthEvents") limitations.push("insufficient_data：未提供可描述的症狀嚴重程度。");
    return { type: d.type, status: d.status, summary: [`資料紀錄數：${source.recordCount}`, ...available.map(f => `${labels[f.code]}：${f.value}`)].join("；"), limitations };
  });
  return { domains, patternSummary: input.periodLabel };
}
const INSTRUCTIONS = "Select only the explicitly supplied fact codes. Return the exact server periodLabel as periodText. No prose fields are allowed. Do not infer severity from counts, behavior from records, actual administration or adherence from medication records or schedules, temporal descriptions, causality, diagnosis, or medication changes. Never reinterpret statistics as clinical concepts. Use observed only when at least one fact has a non-null value and positive sampleCount, otherwise insufficient_data. Include exactly all available fact codes once per input domain. Return each input domain exactly once. Do not echo raw payload.";
function createOpenAiAdapter({ apiKey, Client, emit = () => {} }) {
  // Explicit off overrides OPENAI_LOG; the SDK logger cannot emit input/error bodies.
  const client = new Client({ apiKey, timeout: 15000, maxRetries: 0, logLevel: "off", logger: { debug() {}, info() {}, warn() {}, error() {} } });
  return async input => {
    validateRequest(input); const start = Date.now();
    let response;
    try {
      response = await client.responses.create({ model: MODEL, store: false, background: false, stream: false, tools: [],
        max_output_tokens: 1500, instructions: INSTRUCTIONS,
        input: [{ role: "user", content: [{ type: "input_text", text: JSON.stringify(input) }] }],
        text: { format: { type: "json_schema", name: "synthetic_clinical_summary", strict: true, schema: responseSchema } } });
      requireThat(response.status === "completed", "unavailable");
      const content = (response.output || []).flatMap(x => x.content || []);
      requireThat(!content.some(x => x.type === "refusal"), "failed-precondition");
      const texts = content.filter(x => x.type === "output_text");
      requireThat(texts.length === 1 && typeof texts[0].text === "string" && Buffer.byteLength(texts[0].text) <= 16384, "data-loss");
      let parsed; try { parsed = JSON.parse(texts[0].text); } catch { throw new ShareError("data-loss"); }
      const usage = response.usage || {};
      emit({ latencyMs: Date.now() - start, inputTokens: Number.isSafeInteger(usage.input_tokens) ? usage.input_tokens : 0, outputTokens: Number.isSafeInteger(usage.output_tokens) ? usage.output_tokens : 0 });
      // The service rechecks authorization before validating this untrusted JSON.
      return parsed;
    } catch (e) {
      // Never preserve an SDK error's message, cause, headers or response body.
      throw new ShareError(e instanceof ShareError ? e.code : e?.name === "APIConnectionTimeoutError" ? "deadline-exceeded" : "unavailable");
    } finally { response = null; }
  };
}
module.exports = { MODEL, CODES, requestSchema, responseSchema, normalizeExternal, validateRequest, validateOutput, createOpenAiAdapter };
