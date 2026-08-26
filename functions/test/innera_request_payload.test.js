"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildInneraContextPayload,
  compactRecentMedicationAdjustments,
} = require("../innera_request_payload");

const shared = {
  context: { locale: "zh-TW" },
  contextSources: [{ label: "最近紀錄", dateRange: "近七天", count: 3 }],
  recordDraft: { eventDrafts: [{ id: "existing" }] },
  emotionDimensions: [{ id: "anxiety", displayName: "焦慮" }],
};

test("emotional support sends only mode, context, and contextSources", () => {
  const payload = buildInneraContextPayload({
    mode: "emotionalSupport",
    ...shared,
  });
  assert.deepEqual(payload, {
    mode: "emotionalSupport",
    context: shared.context,
    contextSources: shared.contextSources,
  });
  assert.equal(Object.hasOwn(payload, "recordDraft"), false);
  assert.equal(Object.hasOwn(payload, "eventDrafts"), false);
  assert.equal(Object.hasOwn(payload, "emotionDimensions"), false);
});

test("daily record retains recordDraft and emotionDimensions", () => {
  const payload = buildInneraContextPayload({ mode: "dailyRecord", ...shared });
  assert.equal(payload.recordDraft, shared.recordDraft);
  assert.equal(payload.emotionDimensions, shared.emotionDimensions);
});

test("physical health retains its existing structured extraction input", () => {
  const payload = buildInneraContextPayload({ mode: "physicalHealth", ...shared });
  assert.equal(payload.recordDraft, shared.recordDraft);
  assert.equal(payload.emotionDimensions, shared.emotionDimensions);
});

test("general recent review omits raw records but keeps prepared statistics", () => {
  const context = {
    ...shared.context,
    recentDailyRecords: [{ date: "2026-08-23", privateRawField: "not sent" }],
    sleepTimeStats: {
      validSleepTimeDays: 1,
      bedtimeEvidence: [{ date: "2026-08-23", sleepTime: "23:00" }],
    },
    emotionStats: {
      daysWithEmotionData: 1,
      mostFrequentEmotions: ["焦慮"],
    },
    dailyRecordStats: { validRecordDays: 1 },
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context,
    specialRecentReviewRequest: false,
  });
  assert.deepEqual(payload, {
    mode: "recentReview",
    context: {
      locale: "zh-TW",
      sleepTimeStats: context.sleepTimeStats,
      emotionStats: context.emotionStats,
      dailyRecordStats: context.dailyRecordStats,
    },
    contextSources: shared.contextSources,
  });
  assert.equal(Object.hasOwn(payload.context, "recentDailyRecords"), false);
  assert.ok(JSON.stringify(payload.context).length < JSON.stringify(context).length);
});

test("general recent review V2 sends only metadata and deterministic summary", () => {
  const summary = {
    period: { startDate: "2026-08-01", endDate: "2026-08-30", lookbackDays: 30 },
    sleep: {
      recordedDays: 30,
      validNightSleepDays: 29,
      usableBedtimeDays: 13,
      typicalBedtime: "23:30",
    },
    emotions: [{ name: "焦慮", occurrenceDays: 2 }],
    symptoms: [{ name: "頭痛", occurrenceDays: 1, averageIntensity: null }],
    medications: [{ name: "藥物 A", dosePerUnit: 25, pillCount: 1, unit: "mg" }],
    medicationChanges: [{ date: "2026/08/20", name: "藥物 A", type: "doseChanged", changeSummary: "25 mg → 50 mg" }],
  };
  const context = {
    mode: "recentReview",
    generatedAt: "2026-08-30T12:00:00.000",
    lookbackDays: 30,
    recentReviewSummary: summary,
    recentDailyRecords: [{ private: true }],
    dailyHealthAggregateSummary: { private: true },
    recentQuickRecordExamples: [{ private: true }],
    recentDiaries: [{ private: true }],
    activeMedications: [{ private: true }],
    recentMedicationAdjustments: [{ private: true }],
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context,
    specialRecentReviewRequest: false,
  });

  assert.deepEqual(payload.context, {
    mode: "recentReview",
    generatedAt: "2026-08-30T12:00:00.000",
    lookbackDays: 30,
    recentReviewSummary: summary,
  });
});

test("general recent review V2 applies the supplied domain selection", () => {
  const summary = {
    period: { lookbackDays: 30 },
    sleep: { recordedDays: 30 },
    emotions: [{ name: "焦慮" }],
    symptoms: [{ name: "頭痛" }],
  };
  const evidence = {
    sleep: [{ date: "2026-08-25", nightSleepHours: 8 }],
    emotion: [{ date: "2026-08-24", name: "焦慮", intensity: 4 }],
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context: { recentReviewSummary: summary, recentReviewEvidence: evidence },
    specialRecentReviewRequest: false,
    recentReviewDomainSelection: {
      selectedDomains: ["sleep"],
      usedDomainFallback: false,
    },
  });
  assert.deepEqual(payload.context.recentReviewSummary, {
    period: summary.period,
    sleep: summary.sleep,
  });
  assert.deepEqual(payload.context.recentReviewEvidence, {
    sleep: evidence.sleep,
  });
});

test("follow-up questions and summaries retain raw recent review records", () => {
  const context = {
    ...shared.context,
    recentDailyRecords: [{ date: "2026-08-23", symptoms: ["頭痛"] }],
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context,
    specialRecentReviewRequest: true,
  });
  assert.deepEqual(payload.context, context);
  assert.equal(payload.context.recentDailyRecords.length, 1);
});

test("special recent review removes V2 summary and retains the legacy context", () => {
  const context = {
    locale: "zh-TW",
    recentDailyRecords: [{ date: "2026-08-23" }],
    recentReviewSummary: { period: { lookbackDays: 30 } },
    recentReviewEvidence: { sleep: [{ date: "2026-08-23" }] },
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context,
    specialRecentReviewRequest: true,
  });
  assert.deepEqual(payload.context, {
    locale: "zh-TW",
    recentDailyRecords: context.recentDailyRecords,
  });
});

test("general recent review strips legacy adjustment fields at the final payload", () => {
  const context = {
    recentMedicationAdjustments: [{
      date: "2026-08-25",
      itemsCount: 2,
      source: "legacy-client",
      note: "備註",
      items: [{
        name: "藥物 A",
        type: "doseChanged",
        oldDose: 25,
        newDose: 100,
        oldDosePerUnit: 25,
        newDosePerUnit: 50,
        oldPillCount: 1,
        newPillCount: 2,
        oldTimes: ["睡前"],
        newTimes: ["早餐後", "睡前"],
        oldUnit: "mg",
        newUnit: "mg",
        medDocId: "private-id",
        source: "legacy-item",
      }],
    }],
  };
  const payload = buildInneraContextPayload({
    mode: "recentReview",
    ...shared,
    context,
    specialRecentReviewRequest: false,
  });

  assert.deepEqual(payload.context.recentMedicationAdjustments, [{
    date: "2026-08-25",
    items: [{
      name: "藥物 A",
      type: "doseChanged",
      changeSummary: "25 mg → 100 mg",
    }],
    note: "備註",
  }]);
  const finalJson = JSON.stringify(payload.context.recentMedicationAdjustments);
  for (const forbidden of [
    "oldDose", "newDose", "oldDosePerUnit", "newDosePerUnit",
    "oldPillCount", "newPillCount", "oldTimes", "newTimes",
    "oldUnit", "newUnit", "medDocId", "source", "itemsCount",
  ]) {
    assert.equal(finalJson.includes(forbidden), false, forbidden);
  }
});

test("adjustment compaction supports schedule, lifecycle, and injection types", () => {
  const compact = compactRecentMedicationAdjustments([{
    date: "2026-08-26",
    items: [
      {
        name: "藥物 B",
        type: "scheduleChanged",
        oldTimes: ["早上"],
        newTimes: ["睡前"],
      },
      { name: "藥物 C", type: "added", newDosePerUnit: 25, newPillCount: 1, newUnit: "mg" },
      { name: "藥物 D", type: "stopped" },
      { name: "藥物 E", type: "resumed" },
      { name: "藥物 F", type: "injected" },
      { name: "藥物 H", type: "added" },
    ],
  }]);

  assert.deepEqual(compact[0].items.map((item) => item.changeSummary), [
    "早上 → 睡前",
    "25 mg × 1 顆",
    "停藥",
    "恢復使用",
    "已施打",
    "新增藥物",
  ]);
});

test("final payload preserves a client-provided deterministic summary", () => {
  const compact = compactRecentMedicationAdjustments([{
    date: "2026/08/26",
    items: [{
      name: "藥物 G",
      type: "doseChanged",
      changeSummary: "50 mg × 1 顆 → 100 mg × 1 顆",
      oldDose: 50,
      newDose: 100,
    }],
  }]);

  assert.deepEqual(compact, [{
    date: "2026/08/26",
    items: [{
      name: "藥物 G",
      type: "doseChanged",
      changeSummary: "50 mg × 1 顆 → 100 mg × 1 顆",
    }],
  }]);
});
