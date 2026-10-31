"use strict";
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { createService } = require("./service");
const { createSummaryService } = require("./summary-service");
const { createKms } = require("./kms");
const { PROJECT, ShareError } = require("./protocol");
const { defineSecret } = require("firebase-functions/params");
const openAiSecret = defineSecret("OPENAI_ENCRYPTED_DEMO_API_KEY");

let service;
let healthService;
let checkService;
let medicationService;
let dailyService;
let summaryService;
let sessionAuth;
async function verifySession(request) {
  const header = request.rawRequest?.headers?.authorization || "";
  if (!header.startsWith("Bearer ") || !request.auth) throw new ShareError("unauthenticated");
  try {
    const token = await sessionAuth.verifyIdToken(header.slice(7), true);
    if (token.uid !== request.auth.uid) throw new Error();
  } catch { throw new ShareError("unauthenticated"); }
}
function getService() {
  if (service) return service;
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  if (projectId !== PROJECT) throw new ShareError("failed-precondition");
  const credential = applicationDefault();
  const app = initializeApp({ projectId, credential }, "encrypted-sleep-demo");
  sessionAuth = getAuth(app);
  const keys = createKms({ mapping: JSON.parse(process.env.DEMO_CLINIC_KMS_VERSIONS || "{}"), credential });
  service = createService({ db: getFirestore(app), projectId, keys });
  healthService = createService({ db: getFirestore(app), projectId, keys, type: "healthEvents" });
  checkService = createService({ db: getFirestore(app), projectId, keys, type: "checkIns" });
  medicationService = createService({ db: getFirestore(app), projectId, keys, type: "medications" });
  dailyService = createService({ db: getFirestore(app), projectId, keys, type: "dailyRecords" });
  summaryService = createSummaryService({ db: getFirestore(app), projectId, keys, verifySession,
    raceTestEnabled: projectId === PROJECT && process.env.DEMO_RACE_TEST_ENABLED === "true",
    openAiProvider: async input => {
      const { createOpenAiAdapter } = require("./openai-summary");
      const OpenAI = require("openai");
      const adapter = createOpenAiAdapter({ apiKey: openAiSecret.value(), Client: OpenAI,
        emit: metrics => console.info("demo.openai.usage", metrics) });
      return adapter(input);
    } });
  return service;
}
const options = {
  region: "us-central1", enforceAppCheck: true, timeoutSeconds: 60,
  maxInstances: 3, concurrency: 10,
  serviceAccount: "demo-encrypted-share@innera-demo.iam.gserviceaccount.com",
};
for (const [name, method] of Object.entries({
  demoSummaryConsent: "summary:consent", demoRevokeSummary: "summary:revoke",
  demoGenerateSummary: "summary:generate", demoReadSummary: "summary:read",
  demoSleepContext: "context", demoPublishSleep: "publish",
  demoRevokeSleep: "revoke", demoReadSleep: "read",
  demoListSleepPatients: "list",
  demoDailyRecordContext: "daily:context", demoPublishDailyRecords: "daily:publish",
  demoRevokeDailyRecords: "daily:revoke", demoReadDailyRecords: "daily:read",
  demoMedicationContext: "med:context", demoPublishMedications: "med:publish",
  demoRevokeMedications: "med:revoke", demoReadMedications: "med:read",
  demoCheckInContext: "check:context", demoPublishCheckIns: "check:publish",
  demoRevokeCheckIns: "check:revoke", demoReadCheckIns: "check:read",
  demoHealthEventContext: "health:context", demoPublishHealthEvents: "health:publish",
  demoRevokeHealthEvents: "health:revoke", demoReadHealthEvents: "health:read",
})) {
  exports[name] = onCall({ ...options, ...(name === "demoGenerateSummary" && process.env.DEMO_RACE_TEST_ENABLED === "true" ? { timeoutSeconds: 240 } : {}), ...(["demoGenerateSummary", "demoReadSummary"].includes(name) ? { secrets: [openAiSecret] } : {}) }, async request => {
    request.rawRequest?.res?.setHeader("Cache-Control", "no-store, private");
    try {
      const target = getService();
      await verifySession(request);
      if (method === "summary:generate" && request.data?.raceOperation) return await summaryService.raceOperation(request);
      if (method.startsWith("summary:")) return await summaryService[method.slice(8)](request);
      return method.startsWith("daily:") ? await dailyService[method.slice(6)](request) : method.startsWith("med:") ? await medicationService[method.slice(4)](request) : method.startsWith("check:") ? await checkService[method.slice(6)](request) : method.startsWith("health:")
        ? await healthService[method.slice(7)](request) : await target[method](request);
    }
    catch (error) {
      // Never log/return SDK errors, request bodies, tokens, keys or medical data.
      throw new HttpsError(error instanceof ShareError ? error.code : "internal", "無法完成請求，請確認授權或稍後重試。", error instanceof ShareError && error.raceExpired === true ? { racePhase: "expired" } : undefined);
    }
  });
}
