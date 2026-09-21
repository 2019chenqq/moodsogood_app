const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const { HttpsError } = require("firebase-functions/v2/https");

function setup({ caller = {}, share = {}, records = {}, result, finish = "stop" } = {}) {
  const queries = [];
  const logs = [];
  let aiInput;
  const output = result || {
    domains: Object.fromEntries(["drive", "cognition", "mood", "behavior", "sleep"]
      .map((key) => [key, { status: "資料不足", summary: "資料不足" }])),
    patternSummary: "資料不足", importantEvents: [],
  };
  const shareRef = {
    get: async () => ({ data: () => ({ active: true, healthEventSharingEnabled: true,
      dailyCheckInSharingEnabled: true, sleepSharingEnabled: true, ...share }) }),
    collection(name) {
      const query = { name, filters: [] };
      queries.push(query);
      const chain = {
        where(...args) { query.filters.push(args); return chain; },
        orderBy() { return chain; }, limit() { return chain; },
        select(...fields) { query.fields = fields; return chain; },
        async get() {
          const rows = (records[name] || []).filter((row) => query.filters.every(([field, op, value]) =>
            op === ">=" ? row[field].toDate() >= value : row[field].toDate() <= value));
          return { size: rows.length, docs: rows.map((row) => ({ data: () =>
            Object.fromEntries(Object.entries(row).filter(([key]) => query.fields.includes(key))) })) };
        },
      };
      return chain;
    },
  };
  const db = { collection(name) {
    if (name === "clinicStaff") return { doc: () => ({ get: async () => ({ data: () =>
      ({ active: true, role: "doctor", clinicId: "clinic", ...caller }) }) }) };
    assert.equal(name, "clinicalShares");
    return { doc: (uid) => {
      assert.equal(uid, "patient");
      return { collection: (name) => {
        assert.equal(name, "clinics");
        return { doc: (id) => { assert.equal(id, "clinic"); return shareRef; } };
      } };
    } };
  } };
  const exports = {};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../../src/clinic/clinical_summary.js"), "utf8"), {
    exports, Buffer, console: { log: (...args) => logs.push(args) },
    require(name) {
      if (name === "firebase-functions/v2/https") return { HttpsError, onCall: (_, handler) => handler };
      if (name === "../config/firebase") return { db };
      if (name === "../config/params") return { openAiApiKey: { value: () => "test" }, DEFAULT_AI_MODEL: "existing-model" };
      if (name === "openai") return class {
        chat = { completions: { create: async (input) => {
          aiInput = input;
          return { choices: [{ finish_reason: finish, message: { content: JSON.stringify(output) } }] };
        } } };
      };
      throw new Error(`Unexpected dependency: ${name}`);
    },
  });
  return { run: (data = {}, auth = { uid: "doctor" }) => exports.generateClinicalSummary({
    auth, data: { uid: "patient", clinicId: "clinic", ...data },
  }), queries, logs, input: () => aiInput };
}
const stamp = (offsetDays = 0) => ({ toDate: () => new Date(Date.now() - offsetDays * 86400000 - 1000) });

test("reads the requested date window and sends only valid sleep aggregates to existing AI", async () => {
  const app = setup({ records: {
    sleepRecords: [360, 480, null, -1, 1500, "420"].map((durationMinutes) =>
      ({ date: stamp(), durationMinutes, sleepConditions: ["private raw sleep text"] })),
    healthEvents: [{ timestamp: stamp(), note: "recent" }, { timestamp: stamp(31), note: "old" }],
    dailyCheckIns: [{ date: stamp(), overallMood: 3 }],
  } });
  assert.equal((await app.run()).success, true);
  assert.equal(app.input().model, "existing-model");
  const input = JSON.parse(app.input().messages[1].content);
  assert.equal(input.period.days, 30);
  assert.deepEqual(input.sleepStatistics, { averageHours: 7, minHours: 6, maxHours: 8, validRecordCount: 2 });
  assert.equal(input.healthEvents.length, 1);
  assert.equal(input.sleepRecords, undefined);
  assert.equal(JSON.stringify(input).includes("private raw sleep text"), false);
  assert.deepEqual(app.queries.map((query) => query.name), ["healthEvents", "dailyCheckIns", "sleepRecords"]);
  assert.equal(app.logs.length, 1);
  assert.equal(JSON.parse(app.logs[0][1]).importantEvents.length, 0);
});

test("rejects unauthenticated, invalid, cross-clinic and revoked access before AI", async () => {
  await assert.rejects(setup().run({}, null), { code: "unauthenticated" });
  for (const data of [{ uid: "a/b" }, { days: 0 }, { days: "30" }, { days: 366 }]) {
    await assert.rejects(setup().run(data), { code: "invalid-argument" });
  }
  for (const options of [{ caller: { clinicId: "other" } }, { caller: { active: false } },
    { share: { active: false } }, { share: { revokedAt: stamp() } }]) {
    const app = setup(options);
    await assert.rejects(app.run(), { code: "permission-denied" });
    assert.equal(app.queries.length, 0);
    assert.equal(app.input(), undefined);
  }
});

test("disabled sharing skips data; missing sleep stays null instead of zero", async () => {
  const app = setup({ share: { sleepSharingEnabled: false, healthEventSharingEnabled: false } });
  await app.run({ days: 7 });
  assert.deepEqual(app.queries.map((query) => query.name), ["dailyCheckIns"]);
  const input = JSON.parse(app.input().messages[1].content);
  assert.equal(input.period.days, 7);
  assert.deepEqual(input.sleepStatistics, { averageHours: null, minHours: null, maxHours: null, validRecordCount: 0 });
});

test("invalid or incomplete AI output is never logged", async () => {
  for (const options of [{ result: { domains: {} } }, { finish: "length" }]) {
    const app = setup(options);
    await assert.rejects(app.run(), { code: "internal" });
    assert.equal(app.logs.length, 0);
  }
});
