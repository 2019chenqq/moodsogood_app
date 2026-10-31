"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");
test("every callable enforces App Check, dedicated service identity and safe errors", async () => {
  const exports = {};
  const source = fs.readFileSync(path.resolve(__dirname, "../index.js"), "utf8");
  vm.runInNewContext(source, { exports, process: { env: { GCLOUD_PROJECT: "production" } }, require: name => {
    if (name === "firebase-functions/v2/https") return {
      onCall: (options, handler) => ({ options, handler }),
      HttpsError: class extends Error { constructor(code, message) { super(message); this.code = code; } },
    };
    if (name === "firebase-functions/params") return { defineSecret: () => ({}) };
    if (name.startsWith("firebase-admin/")) return {};
    return require(path.resolve(__dirname, "..", name));
  } });
  assert.equal(Object.keys(exports).length, 25);
  for (const entry of Object.values(exports)) {
    assert.equal(entry.options.enforceAppCheck, true);
    assert.equal(entry.options.serviceAccount, "demo-encrypted-share@innera-demo.iam.gserviceaccount.com");
    await assert.rejects(() => entry.handler({}), { code: "failed-precondition", message: "無法完成請求，請確認授權或稍後重試。" });
  }
});

for (const authFailure of ["auth/user-disabled", "auth/id-token-revoked"]) test(`Check-in/Medication/dailyRecords wrapper rejects ${authFailure} before runtime operation`, async () => {
  const exports = {}; let operations = 0, checks = 0;
  vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, "../index.js"), "utf8"), {
    exports, process: { env: { GCLOUD_PROJECT: "innera-demo" } }, require: name => {
      if (name === "firebase-functions/v2/https") return { onCall: (options, handler) => handler,
        HttpsError: class extends Error { constructor(code, message) { super(message); this.code = code; } } };
      if (name === "firebase-functions/params") return { defineSecret: () => ({}) };
      if (name === "firebase-admin/app") return { applicationDefault: () => ({}), initializeApp: () => ({}) };
      if (name === "firebase-admin/firestore") return { getFirestore: () => ({}) };
      if (name === "firebase-admin/auth") return { getAuth: () => ({ verifyIdToken: async (token, revoked) => {
        checks++; assert.equal(revoked, true); throw Object.assign(Error("Must not release raw SDK error"), { code: authFailure });
      } }) };
      if (name === "./service") return { createService: () => new Proxy({}, { get: () => async () => { operations++; } }) };
      if (name === "./kms") return { createKms: () => ({}) };
      return require(path.resolve(__dirname, "..", name));
    },
  });
  for (const name of ["demoCheckInContext", "demoPublishCheckIns", "demoReadCheckIns", "demoRevokeCheckIns", "demoMedicationContext", "demoPublishMedications", "demoReadMedications", "demoRevokeMedications", "demoDailyRecordContext", "demoPublishDailyRecords", "demoReadDailyRecords", "demoRevokeDailyRecords"]) {
    await assert.rejects(() => exports[name]({ auth: { uid: "synthetic" }, rawRequest: { headers: { authorization: "Bearer synthetic-test-only" } } }),
      { code: "unauthenticated", message: "無法完成請求，請確認授權或稍後重試。" });
  }
  assert.equal(checks, 12); assert.equal(operations, 0);
  for (const name of ["demoSummaryConsent", "demoRevokeSummary", "demoGenerateSummary", "demoReadSummary"]) {
    await assert.rejects(() => exports[name]({ auth: { uid: "synthetic" }, rawRequest: { headers: { authorization: "Bearer synthetic-test-only" } } }), { code: "unauthenticated" });
  }
  assert.equal(checks, 16); assert.equal(operations, 0);
});

test("demo race opt-in gives generation 240s headroom; default and read remain 60s", () => {
  for (const enabled of [false,true]) {
    const exports={};
    vm.runInNewContext(fs.readFileSync(path.resolve(__dirname,"../index.js"),"utf8"),{exports,process:{env:{GCLOUD_PROJECT:"innera-demo",...(enabled?{DEMO_RACE_TEST_ENABLED:"true"}:{})}},require:name=>{
      if(name==="firebase-functions/v2/https")return{onCall:options=>({options}),HttpsError:class extends Error{}};
      if(name==="firebase-functions/params")return{defineSecret:()=>({})};
      if(name.startsWith("firebase-admin/"))return{};
      return require(path.resolve(__dirname,"..",name));
    }});
    assert.equal(exports.demoGenerateSummary.options.timeoutSeconds,enabled?240:60);
    assert.equal(exports.demoReadSummary.options.timeoutSeconds,60);
    assert.equal(exports.demoGenerateSummary.options.enforceAppCheck,true);
  }
});
