"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { normalizeExternal, validateRequest, validateOutput, createOpenAiAdapter } = require("../openai-summary");
const { createSummaryService } = require("../summary-service");
const { createService } = require("../service");
const { TYPES } = require("../summary-schema");
const { VERSION, keyPair, sleep, encrypt, unwrap, MemoryDb, fixture, request } = require("./helpers");
const payloads = { sleepRecords: sleep, healthEvents: require("./health-event-fixture"), checkIns: require("./check-in-fixture"), medications: require("./medication-fixture"), dailyRecords: require("./daily-record-fixture").confirmation };
const input = () => normalizeExternal(Object.fromEntries(TYPES.map(t => [t, [payloads[t]]])));
const output = p => ({ schemaVersion: 2, periodText: p.periodLabel, domains: p.domains.map(d => ({ type: d.type, status: d.facts.some(f => f.value !== null && f.sampleCount > 0) ? "observed" : "insufficient_data", factCodes: d.facts.filter(f => f.value !== null && f.sampleCount > 0).map(f => f.code) })) });
const wire = p => ({ status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: JSON.stringify(output(p)) }] }], usage: { input_tokens: 100, output_tokens: 30 } });
function adapter(handler) {
  return createOpenAiAdapter({ apiKey: "local-placeholder-not-a-key", Client: class { constructor(options) {
    assert.equal(options.timeout, 15000); assert.equal(options.maxRetries, 0); assert.equal(options.logLevel, "off");
    this.responses = { create: async body => { assert.equal(body.store, false); assert.equal(body.background, false); assert.equal(body.stream, false); assert.deepEqual(body.tools, []); return handler(body); } };
  } } });
}
test("five sources normalize only fixed numeric codes, without exact dates/free text", () => {
  const p = input(), text = JSON.stringify(p);
  assert.equal(p.domains.length, 5);
  for (const prohibited of ["2026-", "Synthetic-", "合成症狀", "note", "uid", "epoch", "provenance", "projects/"]) assert.ok(!text.includes(prohibited), "No forbidden data in provider input");
  assert.equal(p.windowDays, 1);
});
test("unknown raw field fails closed before normalization", () => {
  assert.throws(() => normalizeExternal({ sleepRecords: [{ ...sleep, email: "sentinel@example.test" }] }), { code: "data-loss" });
});
test("unknown outbound field/code rejected", () => {
  const p = input(); p.uid = "forbidden"; assert.throws(() => validateRequest(p), { code: "data-loss" });
  const q = input(); q.domains[0].facts[0].code = "raw_note"; assert.throws(() => validateRequest(q), { code: "data-loss" });
});
test("window/record limit fails without silent truncation", () => {
  assert.throws(() => normalizeExternal({ sleepRecords: [sleep, { ...sleep, date: "2026-09-01" }] }), { code: "failed-precondition" });
  assert.throws(() => normalizeExternal({ sleepRecords: Array(31).fill(sleep) }), { code: "resource-exhausted" });
});
test("strict response rejects extra fields, missing/duplicate/unprovided domains and oversized text", () => {
  for (const mutate of [v => v.uid = "no", v => v.domains.pop(), v => v.domains[1].type = v.domains[0].type, v => v.domains[0].summary = "x".repeat(601)]) {
    const p = input(), v = output(p); mutate(v); assert.throws(() => validateOutput(v, p), { code: "data-loss" });
  }
  const p = normalizeExternal({ sleepRecords: [sleep] }); const v = output(p); v.domains[0].type = "medications";
  assert.throws(() => validateOutput(v, p), { code: "data-loss" });
});
test("structured response passes with safe request options", async () => {
  const p = input(); assert.ok(await adapter(() => wire(p))(p));
});
for (const kind of ["refusal", "incomplete", "malformed", "timeout", "4xx", "5xx"]) test(`provider ${kind} fails sanitized`, async () => {
  const p = input(); const call = adapter(() => {
    if (["timeout", "4xx", "5xx"].includes(kind)) throw Object.assign(Error("sensitive-error-sentinel"), { name: kind === "timeout" ? "APIConnectionTimeoutError" : "APIError", status: kind === "4xx" ? 400 : 500 });
    const r = wire(p);
    if (kind === "refusal") r.output[0].content = [{ type: "refusal", refusal: "sensitive-error-sentinel" }];
    if (kind === "incomplete") r.status = "incomplete";
    if (kind === "malformed") r.output[0].content[0].text = "sensitive-error-sentinel";
    return r;
  });
  await assert.rejects(() => call(p), e => !e.message.includes("sentinel") && !e.cause);
});
async function setup(provider, options = {}) {
  const db = new MemoryDb(); fixture(db); let time = 1790812800000;
  const keys = { canRead: (c, v) => v === VERSION, canWrite: (c, v) => v === VERSION,
    publicKey: async () => ({ keyVersion: VERSION, publicKeyPem: keyPair.publicKey.export({ type: "spki", format: "pem" }) }), unwrap: async (c, v, b) => unwrap(v, b) };
  const sources = {};
  for (const type of TYPES) {
    sources[type] = createService({ db, keys, projectId: "innera-demo", type });
    await sources[type].publish(request("fake-patient", { expectedEpoch: 0, consentVersion: 1, records: [{ id: `opaque-${type}`, envelope: encrypt({ id: `opaque-${type}`, type, payload: payloads[type] }) }] }));
  }
  const summary = createSummaryService({ db, keys, projectId: "innera-demo", now: () => time, externalPatientUid: "fake-patient", openAiProvider: provider, ...options });
  await summary.consent(request("fake-patient", { consentVersion: 1, provider: "openai" }));
  return { db, keys, sources, summary, advance: (ms = 61000) => time += ms };
}
const doctor = () => request("doctor", { uid: "fake-patient" });
const current = "demoEncryptedShares/fake-patient/clinics/clinic-a/aiSummaries/current";
test("encrypted save/read and valid current reuse incur one provider call", async () => {
  let calls = 0; const s = await setup(async p => { calls++; return output(p); });
  await s.summary.generate(doctor()); await s.summary.generate(doctor());
  assert.equal(calls, 1); assert.equal(Object.keys(s.db.data.get(current)).length, 9);
  assert.equal((await s.summary.read(doctor())).records[0].schemaVersion, 4);
  for (const [path, data] of s.db.data) if (/aiSummaries|GenerationLocks|Audit/.test(path)) assert.ok(!JSON.stringify(data).includes("合成統計觀察"));
});
test("revoke before request: zero provider calls", async () => {
  let calls = 0; const s = await setup(async p => { calls++; return output(p); });
  await s.summary.revoke(request("fake-patient")); await assert.rejects(() => s.summary.generate(doctor())); assert.equal(calls, 0);
});
for (const kind of ["revoke", "epoch"]) test(`${kind} during request discards result and does not save`, async () => {
  let s; s = await setup(async p => {
    if (kind === "revoke") await s.sources.healthEvents.revoke(request("fake-patient"));
    else s.db.data.get("demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/checkIns").epoch++;
    return output(p);
  });
  await assert.rejects(() => s.summary.generate(doctor()), { code: "aborted" }); assert.equal(s.db.data.has(current), false);
});
test("distributed in-flight lock, cooldown and daily attempt cap", async () => {
  let release, entered; const started = new Promise(r => entered = r);
  const s = await setup(p => { entered(); return new Promise(r => release = () => r(output(p))); });
  const first = s.summary.generate(doctor()); await started;
  await assert.rejects(() => s.summary.generate(doctor()), { code: "resource-exhausted" }); release(); await first;
  await s.sources.healthEvents.revoke(request("fake-patient"));
  await assert.rejects(() => s.summary.generate(doctor()), { code: "resource-exhausted" });
  s.advance(); const second = s.summary.generate(doctor()); await new Promise(r => setTimeout(r, 30)); release(); await second;
  await s.sources.medications.revoke(request("fake-patient")); s.advance();
  await assert.rejects(() => s.summary.generate(doctor()), { code: "resource-exhausted" });
});
test("unknown provider output prevents save", async () => {
  const s = await setup(async p => ({ ...output(p), note: "forbidden" }));
  await assert.rejects(() => s.summary.generate(doctor()), { code: "data-loss" }); assert.equal(s.db.data.has(current), false);
});
test("source change after provider validation but before encryption/save aborts", async () => {
  const s = await setup(async p => output(p)); const original = s.keys.publicKey;
  s.keys.publicKey = async (...args) => { await s.sources.checkIns.revoke(request("fake-patient")); return original(...args); };
  await assert.rejects(() => s.summary.generate(doctor()), { code: "aborted" }); assert.equal(s.db.data.has(current), false);
});
test("provider response never saved when Auth recheck fails", async () => {
  let revoked = false;
  const s = await setup(async p => { revoked = true; return output(p); }, { verifySession: async () => {
    if (revoked) throw new (require("../protocol").ShareError)("unauthenticated");
  } });
  await assert.rejects(() => s.summary.generate(doctor()), { code: "unauthenticated" }); assert.equal(s.db.data.has(current), false);
});
test("provider summary round-trip and metadata contain no external payload/provenance", async () => {
  const s = await setup(async p => output(p)); await s.summary.generate(doctor());
  const v = (await s.summary.read(doctor())).records[0];
  assert.ok(TYPES.every(t => v.sources[t].epoch === 1));
  for (const [p, data] of s.db.data) if (/GenerationLocks|Audit/.test(p)) {
    assert.ok(!Object.hasOwn(data, "prompt") && !Object.hasOwn(data, "domains") && !Object.hasOwn(data, "sourceVersions"));
  }
});
test("adapter does not log provider prompt/response/errors", async () => {
  let messages = 0; const original = {};
  for (const name of ["log", "info", "warn", "error", "debug"]) { original[name] = console[name]; console[name] = () => { messages++; }; }
  try { const p = input(); await adapter(() => wire(p))(p); await assert.rejects(() => adapter(() => { throw Error("sentinel"); })(p)); }
  finally { Object.assign(console, original); }
  assert.equal(messages, 0);
});

test("semantic validator rejects severity, active use, adherence, diagnosis and unsupported time prose", () => {
  const p = input();
  for (const claim of ["輕微症狀", "活躍使用", "服藥依從性良好", "診斷為憂鬱症", "建議增加藥量", "過去三天"]) {
    const v = output(p); v.domains[0].summary = claim;
    assert.throws(() => validateOutput(v, p), { code: "data-loss" });
  }
  const v = output(p); v.periodText = "近期資料";
  assert.throws(() => validateOutput(v, p), { code: "data-loss" });
});
test("fact references cannot move between domains or invent clinical classifications", () => {
  const p = input();
  for (const code of ["mild", "currently_taking", "adherence", "sleep_quality"]) {
    const v = output(p); v.domains.find(d => d.type === "healthEvents").factCodes = [code];
    assert.throws(() => validateOutput(v, p), { code: "data-loss" });
  }
  const q = input(); q.domains.find(d => d.type === "medications").facts[0].code = "sleep_quality";
  assert.throws(() => validateRequest(q), { code: "data-loss" });
});
test("deterministic text distinguishes records from clinical severity and administration", () => {
  const p = input(), v = validateOutput(output(p), p);
  assert.equal(v.patternSummary, p.periodLabel);
  const h = v.domains.find(d => d.type === "healthEvents");
  assert.ok(h.summary.includes("不代表嚴重程度"));
  assert.ok(h.limitations.some(x => x.includes("insufficient_data")));
  const m = v.domains.find(d => d.type === "medications");
  assert.ok(m.summary.includes("用藥紀錄數"));
  assert.ok(m.summary.includes("不代表實際服用"));
  assert.ok(!JSON.stringify(v).includes("過去"));
});
test("missing facts must return insufficient_data and no invented references", () => {
  const p = normalizeExternal({ medications: [] });
  assert.equal(validateOutput(output(p), p).domains[0].status, "insufficient_data");
  const v = output(p); v.domains[0].status = "observed";
  assert.throws(() => validateOutput(v, p), { code: "data-loss" });
});

test("previous v3 OpenAI summary is stale and cannot revive after semantic rollout", async () => {
  const s = await setup(async p => output(p)); await s.summary.generate(doctor());
  const oldEnvelope = s.db.data.get(current);
  const { decrypt, encryptSummary } = require("../protocol");
  const payload = await decrypt("fake-patient", "clinic-a", "current", oldEnvelope, unwrap, "aiSummaries");
  payload.schemaVersion = 3;
  const legacy = encryptSummary("fake-patient", "clinic-a", oldEnvelope.epoch, VERSION, keyPair.publicKey.export({ type: "spki", format: "pem" }), payload);
  s.db.data.set(current, legacy);
  await assert.rejects(() => s.summary.readCurrent(doctor()), { code: "failed-precondition" });
  s.advance(); const result = await s.summary.read(doctor());
  assert.equal(result.records[0].schemaVersion, 4);
  assert.notEqual(s.db.data.get(current).ciphertext, legacy.ciphertext);
});

test("controlled post-provider revoke is rechecked before validation and save", async () => {
  let s, providerReturned = false;
  s = await setup(async p => { providerReturned = true; return output(p); }, {
    afterProviderResponse: async () => {
      assert.equal(providerReturned, true);
      await s.sources.healthEvents.revoke(request("fake-patient"));
    }
  });
  await assert.rejects(() => s.summary.generate(doctor()), { code: "aborted" });
  assert.equal(s.db.data.has(current), false);
  const scope = s.db.data.get("demoEncryptedShares/fake-patient/clinics/clinic-a/scopes/healthEvents");
  assert.equal(scope.active, false); assert.equal(scope.epoch, 2);
  assert.ok(![...s.db.data.entries()].filter(([p]) => p.startsWith("demoEncryptedAudit/")).some(([,d]) => ["summary.generate", "summary.generated"].includes(d.action)));
  assert.ok([...s.db.data.entries()].filter(([p]) => p.startsWith("demoEncryptedAudit/")).some(([,d]) => d.action === "summary.rejected" && d.result === "rejected"));
});

test("race mode default off and exact test identity required", async () => {
  const s = await setup(async p => output(p));
  for (const op of ["config","status","run"]) await assert.rejects(() => s.summary.raceOperation({...doctor(), data:{...doctor().data,raceOperation:op}}), {code:"permission-denied"});
});
test("race state, post-response revoke, quota and no stale resurrection", async () => {
  let s, calls=0, timeExpired=false;
  s = await setup(async p => {calls++;return output(p);}, {raceTestEnabled:true,raceDoctorUid:"doctor",raceClinicId:"clinic-a",raceWait:async()=>{
    const waiting = await s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"status"}});
    assert.ok(Number.isSafeInteger(waiting.requestingAt)); assert.ok(Number.isSafeInteger(waiting.waitingAt)); assert.equal(waiting.finishedAt,null);
    assert.equal(waiting.phase,"waiting_for_revoke");assert.equal(waiting.expiresInMs,120000);
    assert.deepEqual(Object.keys(waiting).sort(),["expiresInMs","finishedAt","phase","requestingAt","waitingAt"]);
    await s.sources.healthEvents.revoke(request("fake-patient"));
  }});
  const run=()=>s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"run"}});
  await assert.rejects(()=>s.summary.generate(doctor()),{code:"failed-precondition"});
  await assert.rejects(()=>s.summary.read(doctor()),{code:"failed-precondition"});assert.equal(calls,0);
  await assert.rejects(run,{code:"aborted"});assert.equal(calls,1);assert.equal(s.db.data.has(current),false);
  const terminal = await s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"status"}});assert.equal(terminal.phase,"invalidated");assert.ok(Number.isSafeInteger(terminal.finishedAt));
  await assert.rejects(()=>s.summary.read(doctor()),{code:"failed-precondition"});assert.equal(calls,1);
  await s.sources.healthEvents.publish(request("fake-patient",{expectedEpoch:2,consentVersion:1,records:[{id:"reshare-event",envelope:encrypt({id:"reshare-event",type:"healthEvents",epoch:3,payload:payloads.healthEvents})}]}));
  assert.equal(s.db.data.has(current),false);
  await assert.rejects(run,{code:"resource-exhausted"});assert.equal(calls,1);
  s.advance();const expired = await s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"status"}});assert.equal(expired.phase,"idle");assert.equal(expired.requestingAt,null);assert.equal(expired.waitingAt,null);assert.equal(expired.finishedAt,null);
  await assert.rejects(run,{code:"aborted"});assert.equal(calls,2);
  await s.sources.healthEvents.publish(request("fake-patient",{expectedEpoch:4,consentVersion:1,records:[{id:"reshare-event",envelope:encrypt({id:"reshare-event",type:"healthEvents",epoch:5,payload:payloads.healthEvents})}]}));
  s.advance();await assert.rejects(run,{code:"resource-exhausted"});assert.equal(calls,2);
});

test("race status/run reject other identities, missing App Check and inactive or cross-clinic staff", async () => {
  const s=await setup(async p=>output(p),{raceTestEnabled:true,raceDoctorUid:"doctor",raceClinicId:"clinic-a"});
  await assert.rejects(()=>s.summary.raceOperation(request("fake-patient",{raceOperation:"config"})),{code:"permission-denied"});
  const noApp=doctor();noApp.app=null;await assert.rejects(()=>s.summary.raceOperation(noApp),{code:"failed-precondition"});
  const staff=s.db.data.get("clinicStaff/doctor");staff.active=false;
  await assert.rejects(()=>s.summary.raceOperation({...doctor(),data:{raceOperation:"status"}}));
  staff.active=true;staff.clinicId="other-clinic";
  await assert.rejects(()=>s.summary.raceOperation({...doctor(),data:{raceOperation:"run"}}));
});

for (const revokeAfter of [1000,30000,119000,null]) test(`race waits for revoke (${revokeAfter ?? "timeout"}ms), never saves and uses one provider call`, async () => {
  let s,calls=0,elapsed=0;
  s=await setup(async p=>{calls++;return output(p);},{raceTestEnabled:true,raceDoctorUid:"doctor",raceClinicId:"clinic-a",raceWait:async ms=>{
    elapsed+=ms;s.advance(ms);
    if(revokeAfter!==null && elapsed>=revokeAfter)await s.sources.healthEvents.revoke(request("fake-patient"));
  }});
  const run=()=>s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"run"}});
  await assert.rejects(run,e=>revokeAfter===null ? e.code==="deadline-exceeded" && e.raceExpired===true : e.code==="aborted");
  assert.equal(calls,1);assert.equal(s.db.data.has(current),false);
  const status=await s.summary.raceOperation({...doctor(),data:{...doctor().data,raceOperation:"status"}});
  assert.equal(status.phase,revokeAfter===null?"expired":"invalidated");
  assert.equal(status.finishedAt-status.waitingAt,revokeAfter===null?120000:revokeAfter);
  assert.ok(![...s.db.data.entries()].filter(([p])=>p.startsWith("demoEncryptedAudit/")).some(([,d])=>["summary.generate","summary.generated"].includes(d.action)));
});
