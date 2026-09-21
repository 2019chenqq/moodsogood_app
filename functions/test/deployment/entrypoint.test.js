"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const functions = require("../../index");

const aiSecrets = ["OPENAI_API_KEY", "REVENUECAT_SECRET_API_KEY"];
const callables = {
  submitFollowUpSummaryFeedback: [],
  deleteOwnAccount: [],
  createFollowUpSummaryShare: [],
  getFollowUpShareStatuses: [],
  revokeFollowUpShare: [],
  createCommunityPost: [],
  generateAiJournalReflection: aiSecrets,
  generateInneraDiaryDraft: aiSecrets,
  recommendInneraSongs: [
    "OPENAI_API_KEY", "LASTFM_API_KEY", "SPOTIFY_CLIENT_ID",
    "SPOTIFY_CLIENT_SECRET", "REVENUECAT_SECRET_API_KEY",
  ],
  searchInneraSongs: [
    "SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET", "REVENUECAT_SECRET_API_KEY",
  ],
  summarizeInneraHealthEvents: aiSecrets,
  generateClinicalSummary: ["OPENAI_API_KEY"],
  getInneraAiFreeQuota: ["REVENUECAT_SECRET_API_KEY"],
  generateInneraAiChat: aiSecrets,
  createClinicStaff: [],
  disableClinicStaff: [],
  enableClinicStaff: [],
};
const schedules = {
  aggregateDailyAiUsage: ["0 1 * * *", 3],
  cleanupFollowUpSummaryShares: ["every 15 minutes", 1],
  cleanupExpiredAiChatImages: ["every 60 minutes", 1],
};

test("deployment entrypoint retains public names, trigger types and configuration", () => {
  assert.deepEqual(Object.keys(functions).sort(), [
    ...Object.keys(callables), ...Object.keys(schedules),
    "getFollowUpSummaryShare", "deleteFollowUpSummaryFeedback",
  ].sort());
  for (const [name, secretKeys] of Object.entries(callables)) {
    const endpoint = functions[name].__endpoint;
    assert.equal(endpoint.platform, "gcfv2", name);
    assert.deepEqual(endpoint.callableTrigger, {}, name);
    assert.deepEqual(
      (endpoint.secretEnvironmentVariables || []).map(secret => secret.key),
      secretKeys, name,
    );
    assert.deepEqual(endpoint.region, name.endsWith("ClinicStaff") ? ["us-central1"] : undefined, name);
  }
  for (const [name, [schedule, retryCount]] of Object.entries(schedules)) {
    const endpoint = functions[name].__endpoint;
    assert.equal(endpoint.scheduleTrigger.schedule, schedule, name);
    assert.equal(endpoint.scheduleTrigger.timeZone, "Asia/Taipei", name);
    assert.equal(endpoint.scheduleTrigger.retryConfig.retryCount, retryCount, name);
    assert.equal(endpoint.maxInstances, 1, name);
    assert.deepEqual(endpoint.region, ["us-central1"], name);
  }
  assert.deepEqual(functions.getFollowUpSummaryShare.__endpoint.httpsTrigger, {});
  const event = functions.deleteFollowUpSummaryFeedback.__endpoint.eventTrigger;
  assert.equal(event.eventType, "google.cloud.firestore.document.v1.deleted");
  assert.equal(event.eventFilterPathPatterns.document, "users/{uid}/followUpSummaries/{summaryId}");
});

test("loaded callable handlers reject anonymous requests before using external services", async () => {
  for (const name of Object.keys(callables)) {
    const expectedCode = name === "createCommunityPost" ? "failed-precondition" : "unauthenticated";
    await assert.rejects(
      async () => functions[name].run({ data: {} }),
      { code: expectedCode }, name,
    );
  }
});
