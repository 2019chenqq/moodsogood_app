"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { createSummaryService } = require("../summary-service");
const { createService } = require("../service");
const { TYPES, summarize, normalize } = require("../summary-schema");
const { decrypt, encryptSummary } = require("../protocol");
const { VERSION, keyPair, sleep, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");
const ROOT = "demoEncryptedShares/fake-patient/clinics/clinic-a";
const CURRENT = `${ROOT}/aiSummaries/current`, SCOPE = `${ROOT}/scopes/aiSummary`;
const patient = () => request("fake-patient"), doctor = () => request("doctor", { uid: "fake-patient" });
async function setup() {
  const db = new MemoryDb(); fixture(db);
  for (const method of ["doc", "collection"]) {
    const original = db[method].bind(db);
    db[method] = p => { assert.ok(!p.startsWith("users/") && !p.startsWith("clinicalShares/"), "Demo-only source boundary"); return original(p); };
  }
  const keys = { canRead: (c, v) => c === "clinic-a" && v === VERSION, canWrite: (c, v) => c === "clinic-a" && v === VERSION,
    publicKey: async () => ({ keyVersion: VERSION, publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }),
    unwrap: async (c, v, b) => unwrap(v, b) };
  const sources = {};
  const payloads = { sleepRecords: sleep, healthEvents: require("./health-event-fixture"), checkIns: require("./check-in-fixture"),
    medications: require("./medication-fixture"), dailyRecords: require("./daily-record-fixture").confirmation };
  async function upload(type, epoch) {
    return sources[type].publish(request("fake-patient", { expectedEpoch: epoch, consentVersion: 1,
      records: [{ id: `opaque-${type}`, envelope: encrypt({ id: `opaque-${type}`, epoch: epoch + 1, type, payload: payloads[type] }) }] }));
  }
  for (const type of TYPES) { sources[type] = createService({ db, keys, projectId: "innera-demo", type }); await upload(type, 0); }
  const summary = createSummaryService({ db, keys, projectId: "innera-demo", now: () => 1790812800000 });
  await summary.consent(request("fake-patient", { consentVersion: 1 }));
  return { db, keys, sources, summary, upload };
}
test("five-source decrypt, normalize, deterministic summary, fresh envelope and automatic doctor read", async () => {
  const { db, summary } = await setup();
  await summary.generate(doctor());
  const envelope = db.data.get(CURRENT);
  assert.equal(Object.keys(envelope).length, 9);
  assert.ok(!Object.hasOwn(envelope, "domains") && !Object.hasOwn(envelope, "generatedAt") && !Object.hasOwn(envelope, "sourceVersions"));
  const result = await summary.read(doctor());
  assert.ok(TYPES.every(t => result.records[0].domains[t].recordCount === 1));
  const direct = await decrypt("fake-patient", "clinic-a", "current", envelope, unwrap, "aiSummaries");
  assert.ok(JSON.stringify(direct) === JSON.stringify(result.records[0]), "Round-trip equal without plaintext diagnostics");
  const next = encryptSummary("fake-patient", "clinic-a", 2, VERSION, keyPair.publicKey.export({ type: "spki", format: "pem" }), direct);
  assert.notEqual(next.nonce, envelope.nonce); assert.notEqual(next.wrappedDataKey, envelope.wrappedDataKey);
  assert.deepEqual(summarize(normalize({ sleepRecords: [sleep] }), { ...Object.fromEntries(TYPES.map(t => [t, { active: true, epoch: 1, consentVersion: 1 }])), ...Object.fromEntries(TYPES.filter(t => t !== "sleepRecords").map(t => [t, { active: false, epoch: 0, consentVersion: 0 }])) }, direct.generatedAt),
    summarize(normalize({ sleepRecords: [sleep] }), { ...Object.fromEntries(TYPES.map(t => [t, { active: true, epoch: 1, consentVersion: 1 }])), ...Object.fromEntries(TYPES.filter(t => t !== "sleepRecords").map(t => [t, { active: false, epoch: 0, consentVersion: 0 }])) }, direct.generatedAt));
});
for (const mutation of ["uid", "clinic", "id", "type", "epoch", "ciphertext", "tag", "version"]) test(`summary AAD/tamper rejects ${mutation}`, async () => {
  const { db, summary } = await setup(); await summary.generate(doctor());
  const envelope = structuredClone(db.data.get(CURRENT));
  let uid = "fake-patient", clinic = "clinic-a", id = "current", type = "aiSummaries";
  if (mutation === "uid") uid = "other";
  if (mutation === "clinic") clinic = "other";
  if (mutation === "id") id = "other";
  if (mutation === "type") type = "sleepRecords";
  if (mutation === "epoch") envelope.epoch++;
  if (mutation === "version") envelope.keyVersion = VERSION.replace(/1$/, "2");
  if (mutation === "ciphertext" || mutation === "tag") { const k = mutation === "tag" ? "authenticationTag" : "ciphertext"; const b = Buffer.from(envelope[k], "base64"); b[0] ^= 1; envelope[k] = b.toString("base64"); }
  await assert.rejects(() => decrypt(uid, clinic, id, envelope, unwrap, type), { code: "data-loss" });
});
test("source version equality is semantic and independent of JSON field ordering", async () => {
  const { db, summary } = await setup(); await summary.generate(doctor());
  const original = db.data.get(CURRENT);
  const payload = await decrypt("fake-patient", "clinic-a", "current", original, unwrap, "aiSummaries");
  payload.sources = Object.fromEntries(TYPES.slice().reverse().map(type => [type,
    Object.fromEntries(Object.entries(payload.sources[type]).reverse())]));
  db.data.set(CURRENT, encryptSummary("fake-patient", "clinic-a", original.epoch, VERSION,
    keyPair.publicKey.export({ type: "spki", format: "pem" }), payload));
  assert.equal((await summary.read(doctor())).records.length, 1);
});
for (const invalid of ["non-doctor", "inactive", "cross-clinic", "clinic", "link"]) test(`summary generation and read reject ${invalid}`, async () => {
  const { db, summary } = await setup(); await summary.generate(doctor());
  const staff = db.data.get("clinicStaff/doctor");
  if (invalid === "non-doctor") staff.role = "admin";
  if (invalid === "inactive") staff.active = false;
  if (invalid === "cross-clinic") staff.clinicId = "clinic-b";
  if (invalid === "clinic") db.data.get("clinics/clinic-a").status = "disabled";
  if (invalid === "link") db.data.get("inneraPatients/fake-chart").linked = false;
  await assert.rejects(() => summary.generate(doctor()), { code: "permission-denied" });
  await assert.rejects(() => summary.read(doctor()), { code: "permission-denied" });
});
test("no App Check or patient summary consent: zero key operations", async () => {
  const { keys, summary, db } = await setup(); let calls = 0;
  keys.unwrap = async () => { calls++; throw Error(); };
  const r = doctor(); r.app = null;
  await assert.rejects(() => summary.generate(r), { code: "failed-precondition" });
  db.data.get(SCOPE).active = false;
  await assert.rejects(() => summary.generate(doctor()), { code: "permission-denied" });
  assert.equal(calls, 0);
});
test("inactive source is never decrypted and has no summary domain", async () => {
  const { summary, sources, keys } = await setup();
  await sources.healthEvents.revoke(patient()); let operations = 0;
  const original = keys.unwrap; keys.unwrap = (...args) => { operations++; return original(...args); };
  await summary.generate(doctor()); assert.equal(operations, 4);
  const result = await summary.read(doctor());
  assert.ok(!Object.hasOwn(result.records[0].domains, "healthEvents"));
  assert.ok(!Object.hasOwn(result.records[0].sources, "healthEvents"));
});
for (const type of TYPES) test(`${type} revoke/re-share invalidates summary, strict stale read rejects; regeneration and other scopes preserved`, async () => {
  const { summary, sources, db, upload } = await setup(); await summary.generate(doctor());
  const old = structuredClone(db.data.get(CURRENT));
  await sources[type].revoke(patient()); assert.equal(db.data.has(CURRENT), false);
  await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
  await upload(type, 2); await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
  db.data.set(CURRENT, old); // Restored ciphertext cannot bypass source-version validation.
  await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
  await summary.generate(doctor()); assert.equal((await summary.read(doctor())).records.length, 1);
  for (const other of TYPES.filter(t => t !== type)) assert.equal((await sources[other].read(doctor())).records.length, 1);
});
for (const stage of ["source-decrypt", "public-key", "summary-decrypt", "after-save"]) test(`source revoke race at ${stage} discards result`, async () => {
  const { summary, keys, sources, db } = await setup();
  if (stage === "summary-decrypt") await summary.generate(doctor());
  const originalUnwrap = keys.unwrap, originalPublic = keys.publicKey;
  let fired = false;
  if (stage === "source-decrypt" || stage === "summary-decrypt") keys.unwrap = async (...args) => {
    if (!fired) { fired = true; await sources.healthEvents.revoke(patient()); }
    return originalUnwrap(...args);
  };
  if (stage === "public-key") keys.publicKey = async (...args) => { await sources.healthEvents.revoke(patient()); return originalPublic(...args); };
  if (stage === "after-save") {
    const transaction = db.runTransaction.bind(db);
    db.runTransaction = async fn => {
      const result = await transaction(fn);
      if (!fired && db.data.has(CURRENT)) { fired = true; await sources.healthEvents.revoke(patient()); }
      return result;
    };
  }
  await assert.rejects(() => stage === "summary-decrypt" ? summary.read(doctor()) : summary.generate(doctor()));
  assert.equal(db.data.has(CURRENT), false);
  assert.ok([...db.data.values()].some(v => v.action === "summary.rejected" && v.result === "rejected"));
});
test("summary-only revoke preserves all source documents; consent again cannot revive old summary", async () => {
  const { summary, sources, db } = await setup(); await summary.generate(doctor());
  const old = structuredClone(db.data.get(CURRENT));
  await summary.revoke(patient()); assert.equal(db.data.has(CURRENT), false);
  await assert.rejects(() => summary.read(doctor()), { code: "permission-denied" });
  for (const type of TYPES) assert.equal((await sources[type].read(doctor())).records.length, 1);
  await summary.consent(request("fake-patient", { consentVersion: 1 })); db.data.set(CURRENT, old);
  await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
});
for (const failure of ["disabled", "revoked"]) test(`Auth ${failure} during generation fails before saving`, async () => {
  const { db, keys } = await setup(); let checks = 0;
  const summary = createSummaryService({ db, keys, projectId: "innera-demo", verifySession: async () => { if (++checks === 3) throw Object.assign(Error("unauthenticated"), { code: "unauthenticated" }); } });
  await assert.rejects(() => summary.generate(doctor()), { code: "unauthenticated" });
  assert.equal(db.data.has(CURRENT), false);
});
test("audit failure prevents summary save and plaintext release", async () => {
  const { db, summary } = await setup(); db.failAudit = true;
  await assert.rejects(() => summary.generate(doctor())); assert.equal(db.data.has(CURRENT), false);
  db.failAudit = false; await summary.generate(doctor()); db.failAudit = true;
  await assert.rejects(() => summary.read(doctor()));
});
test("Auth revocation after save removes only the failed generation before returning", async () => {
  const { db, keys } = await setup(); let checks = 0;
  const summary = createSummaryService({ db, keys, projectId: "innera-demo", verifySession: async () => {
    if (++checks === 8) throw Object.assign(Error("unauthenticated"), { code: "unauthenticated" });
  } });
  await assert.rejects(() => summary.generate(doctor()), { code: "unauthenticated" });
  assert.equal(db.data.has(CURRENT), false);
});
test("summary and sources have no plaintext log, audit or database metadata or direct network/persistence code", async () => {
  const fs = require("node:fs"), path = require("node:path");
  for (const name of ["summary-service.js", "summary-schema.js"]) {
    const code = fs.readFileSync(path.resolve(__dirname, "..", name), "utf8");
    assert.ok(!/console\.|fetch\(|https?:\/\/|writeFile|clinicalShares|users\//i.test(code));
  }
  const { db, summary } = await setup(); await summary.generate(doctor()); await summary.read(doctor());
  for (const [p, v] of db.data) if (p.startsWith("demoEncryptedAudit/")) {
    assert.deepEqual(Object.keys(v).sort(), ["action", "result", "actorRef", "subjectRef", "at", "schemaVersion"].sort());
    assert.ok(!JSON.stringify(v).includes("fake-patient"));
  }
  assert.equal(Object.keys(db.data.get(CURRENT)).length, 9);
});

test("automatic partial regeneration A/B/C uses only currently authorized provenance", async () => {
  const { summary, sources, db, upload, keys } = await setup();
  const a = await summary.read(doctor()); assert.equal(a.updated, true);
  assert.equal(Object.keys(a.records[0].sources).length, 5);
  const envelopeA = structuredClone(db.data.get(CURRENT));
  await sources.healthEvents.revoke(patient()); assert.equal(db.data.has(CURRENT), false);
  let unwraps = 0; const original = keys.unwrap;
  keys.unwrap = (...args) => { unwraps++; return original(...args); };
  const b = await summary.read(doctor()); assert.equal(b.updated, true); assert.equal(unwraps, 5);
  assert.ok(!Object.hasOwn(b.records[0].sources, "healthEvents"));
  assert.ok(!Object.hasOwn(b.records[0].domains, "healthEvents"));
  assert.equal(Object.keys(b.records[0].sources).length, 4);
  assert.notEqual(db.data.get(CURRENT).ciphertext, envelopeA.ciphertext);
  assert.equal((await summary.read(doctor())).updated, undefined);
  await upload("healthEvents", 2); assert.equal(db.data.has(CURRENT), false);
  db.data.set(CURRENT, envelopeA);
  await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
  const c = await summary.read(doctor()); assert.equal(c.updated, true);
  assert.equal(c.records[0].sources.healthEvents.epoch, 3);
  await sources.medications.revoke(patient());
  const d = await summary.read(doctor()); assert.ok(!Object.hasOwn(d.records[0].sources, "medications"));
});
test("single source regenerates; zero sources unavailable with no key operations", async () => {
  const { summary, sources, keys, db } = await setup();
  for (const type of TYPES.filter(t => t !== "sleepRecords")) await sources[type].revoke(patient());
  const result = await summary.read(doctor()); assert.deepEqual(Object.keys(result.records[0].sources), ["sleepRecords"]);
  await sources.sleepRecords.revoke(patient()); let calls = 0;
  keys.unwrap = keys.publicKey = async () => { calls++; throw Error(); };
  await assert.rejects(() => summary.read(doctor()), { code: "failed-precondition" });
  assert.equal(calls, 0); assert.equal(db.data.has(CURRENT), false);
});
test("automatic regeneration race discards result and never saves stale ciphertext", async () => {
  const { summary, sources, keys, db } = await setup();
  await summary.generate(doctor()); await sources.healthEvents.revoke(patient());
  const original = keys.publicKey;
  keys.publicKey = async (...args) => { await sources.medications.revoke(patient()); return original(...args); };
  await assert.rejects(() => summary.read(doctor()), { code: "aborted" }); assert.equal(db.data.has(CURRENT), false);
});
test("automatic read never regenerates on missing consent or corrupt ciphertext", async () => {
  const { summary, sources, keys, db } = await setup(); await summary.generate(doctor());
  const bad = db.data.get(CURRENT); bad.authenticationTag = Buffer.alloc(16).toString("base64");
  let publicCalls = 0; const original = keys.publicKey; keys.publicKey = (...args) => { publicCalls++; return original(...args); };
  await assert.rejects(() => summary.read(doctor()), { code: "data-loss" }); assert.equal(publicCalls, 0);
  await summary.revoke(patient());
  await assert.rejects(() => summary.read(doctor()), { code: "permission-denied" }); assert.equal(publicCalls, 0);
});

test("unknown summary key version and missing App Check never trigger regeneration", async () => {
  const { summary, db, keys } = await setup(); await summary.generate(doctor());
  db.data.get(CURRENT).keyVersion = VERSION.replace(/1$/, "2"); let publicCalls = 0;
  keys.publicKey = async () => { publicCalls++; throw Error(); };
  await assert.rejects(() => summary.read(doctor()), { code: "failed-precondition" });
  const r = doctor(); r.app = null; await assert.rejects(() => summary.read(r), { code: "failed-precondition" });
  assert.equal(publicCalls, 0);
});

test("legacy v1 summary is stale and regenerated as v2 without reviving its ciphertext", async () => {
  const { summary, db } = await setup(); await summary.generate(doctor());
  const oldEnvelope = db.data.get(CURRENT);
  const payload = await decrypt("fake-patient", "clinic-a", "current", oldEnvelope, unwrap, "aiSummaries");
  const legacy = { schemaVersion: 1, synthetic: true, model: payload.model, generatedAt: payload.generatedAt,
    sourcePeriod: payload.sourcePeriod, sourceVersions: Object.fromEntries(TYPES.map(t => [t, { active: true, epoch: 1, consentVersion: 1 }])), domains: payload.domains };
  const v1 = encryptSummary("fake-patient", "clinic-a", oldEnvelope.epoch, VERSION, keyPair.publicKey.export({ type: "spki", format: "pem" }), legacy);
  db.data.set(CURRENT, v1);
  await assert.rejects(() => summary.readCurrent(doctor()), { code: "failed-precondition" });
  const result = await summary.read(doctor()); assert.equal(result.updated, true); assert.equal(result.records[0].schemaVersion, 2);
  assert.ok(!Object.hasOwn(result.records[0], "sourceVersions")); assert.notEqual(db.data.get(CURRENT).ciphertext, v1.ciphertext);
});
