"use strict";

const { HttpsError } = require("firebase-functions/v2/https");
const DAY = 86400000;
const DURATION = 84;
const TIME_ZONE = "Asia/Taipei";

function dateMillis(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return NaN;
  const ms = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 10) === value &&
    value >= "2000-01-01" && value <= "9998-12-31" ? ms : NaN;
}

function taipeiDate(now) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(now));
  const part = type => parts.find(item => item.type === type).value;
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function evaluateTrial(trial, now) {
  if (trial === undefined) return {
    status: "not_configured", endDateExclusive: null, lastTrialDate: null,
    expiresAtMillis: null, remainingDays: null,
  };
  if (!trial || trial.schemaVersion !== 1 || trial.durationDays !== DURATION ||
      trial.timeZone !== TIME_ZONE || !Number.isFinite(dateMillis(trial.startDate)) ||
      ![null, "converted", "terminated"].includes(trial.resolution)) {
    throw new HttpsError("failed-precondition", "試用資料格式不支援。", { reason: "invalid-trial" });
  }
  const end = dateMillis(trial.startDate) + DURATION * DAY;
  const endDateExclusive = new Date(end).toISOString().slice(0, 10);
  const today = taipeiDate(now);
  const status = trial.resolution || (today < trial.startDate ? "scheduled" :
    today >= endDateExclusive ? "expired" : "active");
  return {
    status, endDateExclusive,
    lastTrialDate: new Date(end - DAY).toISOString().slice(0, 10),
    expiresAtMillis: Date.parse(`${endDateExclusive}T00:00:00+08:00`),
    remainingDays: status === "active" ? Math.round((end - dateMillis(today)) / DAY) :
      status === "expired" ? 0 : null,
  };
}

function trialInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "試用請求格式不正確。");
  }
  const { action, expectedRevision } = data;
  const keys = ["clinicId", "expectedRevision", "action", action === "setStart" ? "startDate" : "reason"];
  if (!["setStart", "convert", "terminate"].includes(action) ||
      Object.keys(data).length !== keys.length || Object.keys(data).some(key => !keys.includes(key)) ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision < 0 || expectedRevision >= Number.MAX_SAFE_INTEGER) {
    throw new HttpsError("invalid-argument", "試用操作或版本格式不正確。");
  }
  if (action === "setStart") {
    if (!Number.isFinite(dateMillis(data.startDate))) throw new HttpsError("invalid-argument", "開始日期不合法。");
    return { ...data };
  }
  if (typeof data.reason !== "string" || data.reason.trim().length < 1 || data.reason.trim().length > 500) {
    throw new HttpsError("invalid-argument", "結案原因須為 1～500 字元。");
  }
  return { ...data, reason: data.reason.trim() };
}

function transitionTrial(previous, input, now) {
  const state = evaluateTrial(previous, now).status;
  const fail = reason => { throw new HttpsError("failed-precondition", "目前試用狀態不允許此操作。", { reason }); };
  if (["converted", "terminated"].includes(state)) fail("trial-terminal");
  if (input.action === "setStart") {
    if (!["not_configured", "scheduled"].includes(state)) fail("trial-already-started");
    if (input.startDate < taipeiDate(now)) fail("trial-start-in-past");
    if (previous?.startDate === input.startDate) fail("trial-no-change");
    return { schemaVersion: 1, startDate: input.startDate, durationDays: DURATION,
      timeZone: TIME_ZONE, resolution: null, resolvedAt: null, resolvedBy: null, resolutionReason: null };
  }
  if (state === "not_configured") fail("trial-not-configured");
  return { ...previous, resolution: input.action === "convert" ? "converted" : "terminated",
    resolutionReason: input.reason };
}

module.exports = { evaluateTrial, trialInput, transitionTrial };
