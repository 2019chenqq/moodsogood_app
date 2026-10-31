"use strict";
const crypto = require("node:crypto");
const PROJECT = "innera-demo";
const ALGORITHM = "AES-256-GCM";
const WRAPPING = "RSA-OAEP-3072-SHA256";
class ShareError extends Error {
  constructor(code = "permission-denied") { super(code); this.code = code; }
}
function requireThat(condition, code) { if (!condition) throw new ShareError(code); }
function identifier(value) {
  requireThat(typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value), "invalid-argument");
  return value;
}
function versionName(value) {
  requireThat(typeof value === "string" && /^projects\/innera-demo\/locations\/[a-z0-9-]+\/keyRings\/[a-zA-Z0-9_-]+\/cryptoKeys\/[a-zA-Z0-9_-]+\/cryptoKeyVersions\/[1-9][0-9]*$/.test(value), "failed-precondition");
  return value;
}
function aad(uid, clinicId, documentId, envelope, type = "sleepRecords") {
  requireThat(["sleepRecords", "healthEvents", "checkIns", "medications", "dailyRecords", "aiSummaries"].includes(type), "invalid-argument");
  return Buffer.from(JSON.stringify([PROJECT, identifier(uid), identifier(clinicId),
    type, identifier(documentId), 1, envelope.epoch, envelope.keyVersion,
    ALGORITHM, WRAPPING]), "utf8");
}
function decode(value, length, max = length) {
  requireThat(typeof value === "string" && value.length <= Math.ceil(max / 3) * 4 &&
    /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value), "invalid-argument");
  const bytes = Buffer.from(value, "base64");
  requireThat(bytes.length >= length && bytes.length <= max && bytes.toString("base64") === value, "invalid-argument");
  return bytes;
}
function validateEnvelope(value) {
  const fields = ["schemaVersion", "algorithm", "wrappingAlgorithm", "keyVersion", "epoch", "nonce", "ciphertext", "authenticationTag", "wrappedDataKey"];
  requireThat(value && Object.keys(value).length === fields.length && fields.every(k => Object.hasOwn(value, k)), "invalid-argument");
  requireThat(value.schemaVersion === 1 && value.algorithm === ALGORITHM && value.wrappingAlgorithm === WRAPPING &&
    Number.isSafeInteger(value.epoch) && value.epoch > 0, "invalid-argument");
  versionName(value.keyVersion);
  decode(value.nonce, 12); decode(value.authenticationTag, 16);
  decode(value.wrappedDataKey, 384); decode(value.ciphertext, 1, 8192);
  return value;
}
function validateSleep(value) {
  const fields = ["date", "bedTime", "sleepStart", "wakeTime", "activityWakeTime", "durationMinutes", "quality", "sleepConditions"];
  requireThat(value && Object.keys(value).length === fields.length && fields.every(k => Object.hasOwn(value, k)), "data-loss");
  requireThat(typeof value.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.date) &&
    !Number.isNaN(Date.parse(value.date)) && new Date(value.date).toISOString().slice(0, 10) === value.date, "data-loss");
  for (const k of ["bedTime", "sleepStart", "wakeTime", "activityWakeTime"]) {
    requireThat(value[k] === null || (typeof value[k] === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value[k])), "data-loss");
  }
  requireThat(Number.isFinite(value.durationMinutes) && value.durationMinutes >= 0 && value.durationMinutes <= 1440 &&
    (value.quality === null || (Number.isFinite(value.quality) && value.quality >= 0 && value.quality <= 5)) &&
    Array.isArray(value.sleepConditions) && value.sleepConditions.length <= 20 &&
    value.sleepConditions.every(x => typeof x === "string" && x.length <= 100), "data-loss");
  return value;
}
function validateHealthEvent(value) {
  const fields = ["timestamp", "symptoms", "emotions", "stateChanges", "timePrecision", "context", "note", "createdAt", "updatedAt"];
  requireThat(value && Object.keys(value).length === fields.length && fields.every(k => Object.hasOwn(value, k)), "data-loss");
  const date = x => typeof x === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString() === x;
  const text = (x, max) => x === null || (typeof x === "string" && x.length <= max);
  const level = x => Number.isInteger(x) && x >= 1 && x <= 5;
  requireThat(date(value.timestamp) && [value.createdAt, value.updatedAt].every(x => x === null || date(x)), "data-loss");
  requireThat(Array.isArray(value.symptoms) && value.symptoms.length <= 20 && value.symptoms.every(x =>
    x && Object.keys(x).every(k => ["name", "severity"].includes(k)) && typeof x.name === "string" && x.name.trim().length > 0 && x.name.length <= 100 &&
    (x.severity === undefined || x.severity === null || level(x.severity))), "data-loss");
  requireThat(Array.isArray(value.emotions) && value.emotions.length <= 20 && value.emotions.every(x =>
    x && Object.keys(x).length === 2 && typeof x.name === "string" && x.name.trim().length > 0 && x.name.length <= 100 && level(x.intensity)), "data-loss");
  requireThat(value.stateChanges && typeof value.stateChanges === "object" && !Array.isArray(value.stateChanges) &&
    Object.keys(value.stateChanges).length <= 20 && Object.entries(value.stateChanges).every(([k, v]) => k.trim().length > 0 && k.length <= 100 && level(v)), "data-loss");
  requireThat(text(value.timePrecision, 50) && text(value.context, 500) && text(value.note, 2000), "data-loss");
  return value;
}
function validateCheckIn(value) {
  const fields = ["date", "overallMood", "healthStatus", "noSpecialEvent", "createdAt", "updatedAt"];
  requireThat(value && Object.keys(value).length === fields.length && fields.every(k => Object.hasOwn(value, k)), "data-loss");
  const date = x => typeof x === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString() === x;
  const score = x => Number.isInteger(x) && x >= 1 && x <= 5;
  requireThat(date(value.date) && score(value.overallMood) && score(value.healthStatus) && typeof value.noSpecialEvent === "boolean" &&
    [value.createdAt, value.updatedAt].every(x => x === null || date(x)), "data-loss");
  return value;
}
function validateMedication(value) {
  // Fields come from add/edit medication maps, not the old reduced clinical projection.
  const required = ["name", "dose", "dosePerUnit", "pillCount", "concentrationMg", "concentrationMl", "intakeMl",
    "unit", "type", "drugForm", "compoundType", "drugConcentration", "packageAmount", "packageUnit", "ingredientLines",
    "intervalDays", "scheduleType", "scheduleIntervalDays", "scheduleAnchorDate", "weekdays", "times", "purposes", "note",
    "startDate", "isActive", "bodySymptoms", "purposeOther", "createdAt", "updatedAt", "lastChangeAt"];
  const optional = ["nameEn", "resumedAt"];
  requireThat(value && required.every(k => Object.hasOwn(value, k)) && Object.keys(value).every(k => [...required, ...optional].includes(k)), "data-loss");
  const text = (x, max = 500) => typeof x === "string" && x.length <= max;
  const number = x => Number.isFinite(x) && x >= 0 && x <= 100000;
  const days = x => Number.isInteger(x) && x > 0 && x <= 3660;
  const date = x => typeof x === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString() === x;
  const list = x => Array.isArray(x) && x.length <= 30 && x.every(v => text(v, 200));
  for (const k of ["name", "unit", "drugForm", "compoundType", "drugConcentration", "packageAmount", "packageUnit"]) requireThat(text(value[k]), "data-loss");
  requireThat(value.name.trim().length > 0 && (!Object.hasOwn(value, "nameEn") || text(value.nameEn)), "data-loss");
  for (const k of ["dose", "dosePerUnit", "pillCount"]) requireThat(number(value[k]), "data-loss");
  for (const k of ["concentrationMg", "concentrationMl", "intakeMl"]) requireThat(value[k] === null || number(value[k]), "data-loss");
  requireThat(["tablet", "injection", "drops"].includes(value.type) && ["daily", "intervalDays", "weekdays"].includes(value.scheduleType) &&
    (value.intervalDays === null || days(value.intervalDays)) && (value.scheduleIntervalDays === null || days(value.scheduleIntervalDays)), "data-loss");
  requireThat(value.type !== "injection" || days(value.intervalDays), "data-loss");
  requireThat(value.scheduleType !== "intervalDays" || (days(value.scheduleIntervalDays) && date(value.scheduleAnchorDate)), "data-loss");
  requireThat(Array.isArray(value.weekdays) && value.weekdays.length <= 7 && value.weekdays.every(x => Number.isInteger(x) && x >= 1 && x <= 7), "data-loss");
  for (const k of ["ingredientLines", "times", "purposes", "bodySymptoms"]) requireThat(list(value[k]), "data-loss");
  requireThat(text(value.note, 2000) && (value.purposeOther === null || text(value.purposeOther)) && typeof value.isActive === "boolean" && date(value.startDate), "data-loss");
  for (const k of ["scheduleAnchorDate", "createdAt", "updatedAt", "lastChangeAt", "resumedAt"]) {
    if (Object.hasOwn(value, k)) requireThat(value[k] === null || date(value[k]), "data-loss");
  }
  return value;
}
function validateDailyRecord(value) {
  // Only new synthetic five-point writer shapes; never normalize legacy records.
  const allowed = ["date", "emotions", "symptoms", "bodySymptoms", "stateChanges", "symptomSectionCompleted", "emotionSectionCompleted",
    "stateSectionCompleted", "overallMood", "moodScale", "savedAt", "createdAt", "updatedAt", "isPeriod", "periodStartId", "periodEndId",
    "periodCycleLength", "periodNextExpectedStart", "periodArrivalDeltaDays", "periodData", "dailyActivities", "medicines", "bodyMeasurement", "sleep"];
  const map = x => x && typeof x === "object" && !Array.isArray(x);
  const fields = (x, keys) => map(x) && Object.keys(x).every(k => keys.includes(k));
  const text = x => typeof x === "string" && x.length <= 500;
  const score = x => Number.isInteger(x) && x >= 1 && x <= 5;
  const date = x => typeof x === "string" && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString() === x;
  const list = x => Array.isArray(x) && x.length <= 30 && x.every(text);
  const nullable = (x, predicate) => x === null || predicate(x);
  requireThat(fields(value, allowed) && ["date", "emotions", "stateChanges", "moodScale", "updatedAt"].every(k => Object.hasOwn(value, k)) && date(value.date) && value.moodScale === 5, "data-loss");
  const emotions = value.emotions;
  requireThat((Array.isArray(emotions) && emotions.length <= 30 && emotions.every(x => fields(x, ["name", "value"]) && Object.keys(x).length === 2 && text(x.name) && score(x.value))) ||
    (map(emotions) && Object.keys(emotions).length <= 30 && Object.entries(emotions).every(([k, v]) => text(k) && score(v))), "data-loss");
  requireThat(map(value.stateChanges) && Object.keys(value.stateChanges).length <= 30 && Object.entries(value.stateChanges).every(([k, v]) => text(k) && score(v)), "data-loss");
  for (const k of ["symptoms", "bodySymptoms"]) if (Object.hasOwn(value, k)) requireThat(nullable(value[k], list), "data-loss");
  for (const k of ["symptomSectionCompleted", "emotionSectionCompleted", "stateSectionCompleted", "isPeriod"]) if (Object.hasOwn(value, k)) requireThat(typeof value[k] === "boolean", "data-loss");
  if (Object.hasOwn(value, "overallMood")) requireThat(nullable(value.overallMood, x => Number.isFinite(x) && x >= 1 && x <= 5), "data-loss");
  for (const k of ["savedAt", "createdAt", "updatedAt", "periodNextExpectedStart"]) if (Object.hasOwn(value, k)) requireThat(nullable(value[k], date), "data-loss");
  const dayId = x => typeof x === "string" && /^\d{4}-\d\d-\d\d$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString().slice(0, 10) === x;
  for (const k of ["periodStartId", "periodEndId"]) if (Object.hasOwn(value, k)) requireThat(nullable(value[k], dayId), "data-loss");
  const cycle = x => Number.isInteger(x) && x >= 1 && x <= 366;
  const delta = x => Number.isInteger(x) && Math.abs(x) <= 366;
  if (Object.hasOwn(value, "periodCycleLength")) requireThat(cycle(value.periodCycleLength), "data-loss");
  if (Object.hasOwn(value, "periodArrivalDeltaDays")) requireThat(nullable(value.periodArrivalDeltaDays, delta), "data-loss");
  if (value.periodData != null) {
    const p = value.periodData;
    requireThat(fields(p, ["isPeriod", "periodStartId", "periodEndId", "cycleLength", "nextExpectedStart", "arrivalDeltaDays"]), "data-loss");
    if (Object.hasOwn(p, "isPeriod")) requireThat(typeof p.isPeriod === "boolean", "data-loss");
    for (const k of ["periodStartId", "periodEndId"]) if (Object.hasOwn(p, k)) requireThat(nullable(p[k], dayId), "data-loss");
    if (Object.hasOwn(p, "cycleLength")) requireThat(cycle(p.cycleLength), "data-loss");
    if (Object.hasOwn(p, "nextExpectedStart")) requireThat(nullable(p.nextExpectedStart, date), "data-loss");
    if (Object.hasOwn(p, "arrivalDeltaDays")) requireThat(nullable(p.arrivalDeltaDays, delta), "data-loss");
  }
  // Current new-record page sends these slots null; do not invent nested legacy schemas.
  if (Object.hasOwn(value, "dailyActivities")) requireThat(value.dailyActivities === null, "data-loss");
  if (Object.hasOwn(value, "medicines")) requireThat(value.medicines === null, "data-loss");
  if (value.bodyMeasurement != null) {
    const b = value.bodyMeasurement;
    requireThat(fields(b, ["weightKg", "bodyFatPercent", "waistCm", "measuredAt", "measurementTiming", "customMeasurementTime"]), "data-loss");
    for (const [k, min, max] of [["weightKg",20,300],["bodyFatPercent",1,70],["waistCm",30,250]]) if (Object.hasOwn(b,k)) requireThat(nullable(b[k], x => Number.isFinite(x) && x >= min && x <= max), "data-loss");
    if (Object.hasOwn(b,"measuredAt")) requireThat(nullable(b.measuredAt,date), "data-loss");
    if (Object.hasOwn(b,"measurementTiming")) requireThat(nullable(b.measurementTiming, x => ["afterWaking","afterBreakfast","afterLunch","afterDinner","beforeSleep","other"].includes(x)), "data-loss");
    if (Object.hasOwn(b,"customMeasurementTime")) requireThat(nullable(b.customMeasurementTime,text), "data-loss");
  }
  if (value.sleep != null) {
    const s = value.sleep;
    requireThat(fields(s, ["sleepTime", "wakeTime", "finalWakeTime", "quality", "midWakeList", "flags", "naps"]), "data-loss");
    const time = x => typeof x === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(x);
    for (const k of ["sleepTime","wakeTime","finalWakeTime"]) if (Object.hasOwn(s,k)) requireThat(nullable(s[k],time), "data-loss");
    if (Object.hasOwn(s,"quality")) requireThat(nullable(s.quality,score), "data-loss");
    if (Object.hasOwn(s,"midWakeList")) requireThat(nullable(s.midWakeList,text), "data-loss");
    if (Object.hasOwn(s,"flags")) requireThat(list(s.flags), "data-loss");
    if (Object.hasOwn(s,"naps")) requireThat(Array.isArray(s.naps) && s.naps.length === 0, "data-loss");
  }
  return value;
}
async function decrypt(uid, clinicId, documentId, envelope, unwrap, type = "sleepRecords") {
  validateEnvelope(envelope);
  let key; let plaintext;
  try {
    key = await unwrap(envelope.keyVersion, decode(envelope.wrappedDataKey, 384));
    requireThat(Buffer.isBuffer(key) && key.length === 32, "data-loss");
    const cipher = crypto.createDecipheriv("aes-256-gcm", key, decode(envelope.nonce, 12));
    cipher.setAAD(aad(uid, clinicId, documentId, envelope, type));
    cipher.setAuthTag(decode(envelope.authenticationTag, 16));
    plaintext = Buffer.concat([cipher.update(decode(envelope.ciphertext, 1, 8192)), cipher.final()]);
    const value = JSON.parse(plaintext.toString("utf8"));
    return type === "aiSummaries" ? require("./summary-schema").validateSummary(value) : type === "dailyRecords" ? validateDailyRecord(value) : type === "medications" ? validateMedication(value) : type === "healthEvents" ? validateHealthEvent(value) : type === "checkIns" ? validateCheckIn(value) : validateSleep(value);
  } catch { throw new ShareError("data-loss"); }
  finally { key?.fill(0); plaintext?.fill(0); }
}
function encryptSummary(uid, clinicId, epoch, keyVersion, publicKeyPem, value) {
  require("./summary-schema").validateSummary(value);
  versionName(keyVersion);
  const publicKey = crypto.createPublicKey(publicKeyPem);
  requireThat(publicKey.asymmetricKeyDetails?.modulusLength === 3072, "failed-precondition");
  const key = crypto.randomBytes(32), nonce = crypto.randomBytes(12);
  const plaintext = Buffer.from(JSON.stringify(value), "utf8");
  const envelope = { schemaVersion: 1, algorithm: ALGORITHM, wrappingAlgorithm: WRAPPING, keyVersion, epoch };
  try {
    requireThat(plaintext.length <= 8192, "resource-exhausted");
    const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
    cipher.setAAD(aad(uid, clinicId, "current", envelope, "aiSummaries"));
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const wrapped = crypto.publicEncrypt({ key: publicKey, oaepHash: "sha256", padding: crypto.constants.RSA_PKCS1_OAEP_PADDING }, key);
    return validateEnvelope({ ...envelope, nonce: nonce.toString("base64"), ciphertext: ciphertext.toString("base64"),
      authenticationTag: cipher.getAuthTag().toString("base64"), wrappedDataKey: wrapped.toString("base64") });
  } finally { key.fill(0); plaintext.fill(0); }
}
module.exports = { PROJECT, ALGORITHM, WRAPPING, ShareError, requireThat, identifier, versionName, aad, validateEnvelope, validateSleep, validateHealthEvent, validateCheckIn, validateMedication, validateDailyRecord, decrypt, encryptSummary };
