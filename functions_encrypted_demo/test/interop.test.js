"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");
const { decrypt } = require("../protocol");
const { VERSION, keyPair, sleep, unwrap } = require("./helpers");

for (const type of ["sleepRecords", "healthEvents", "checkIns", "medications", "dailyRecords", "aiSummaries"]) test(`real Dart GCM/OAEP ${type} output decrypts with Node`, async () => {
  const input = { uid: "fake-patient", clinicId: "clinic-a", documentId: "opaque-record", epoch: 1,
    keyVersion: VERSION, publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }),
    type, sleep: type === "dailyRecords" ? require("./daily-record-fixture").confirmation : type === "medications" ? require("./medication-fixture") : type === "checkIns" ? require("./check-in-fixture") : type === "healthEvents" ? require("./health-event-fixture") : sleep };
  if (type === "aiSummaries") {
    const { TYPES, normalize, summarize } = require("../summary-schema");
    input.documentId = "current";
    input.sleep = summarize(normalize({ sleepRecords: [sleep], healthEvents: [require("./health-event-fixture")], checkIns: [require("./check-in-fixture")],
      medications: [require("./medication-fixture")], dailyRecords: [require("./daily-record-fixture").confirmation] }),
      Object.fromEntries(TYPES.map(t => [t, { active: true, epoch: 1, consentVersion: 1 }])), "2026-10-01T00:00:00.000Z");
  }
  const dart = process.env.DART_EXECUTABLE || (process.platform === "win32" ? "D:/flutter/bin/cache/dart-sdk/bin/dart.exe" : "dart");
  const envelope = await new Promise((resolve, reject) => {
    const child = spawn(dart, ["run", "tool/demo_sleep_interop.dart"], { cwd: path.resolve(__dirname, "../.."), windowsHide: true });
    let output = "";
    const timer = setTimeout(() => { child.kill(); reject(Error("Dart interop timed out")); }, 90000);
    child.stdout.on("data", chunk => { output += chunk; });
    child.stderr.resume(); // Never echo the pipe payload or arbitrary diagnostics.
    child.on("error", () => { clearTimeout(timer); reject(Error("Dart unavailable")); });
    child.on("close", code => {
      clearTimeout(timer);
      if (code !== 0) return reject(Error("Dart interop failed; run dart analyze for diagnostics"));
      try { resolve(JSON.parse(output)); } catch { reject(Error("Invalid interop response")); }
    });
    child.stdin.end(JSON.stringify(input));
  });
  const result = await decrypt(input.uid, input.clinicId, input.documentId, envelope, unwrap, type);
  assert.ok(JSON.stringify(result) === JSON.stringify(input.sleep), "Interop payload matches without printing plaintext");
});
