"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { HttpsError } = require("firebase-functions/v2/https");
const { withFreeQuota, readQuota, taipeiDay, MODES, RESERVATION_MS } = require("../innera_free_quota");

// Serial transactions model Firestore's atomic read/write behavior across callers.
function database() {
  const documents = new Map();
  let queue = Promise.resolve();
  function ref(path) {
    return {
      path,
      collection: (name) => ref(`${path}/${name}`),
      doc: (name) => ref(`${path}/${name}`),
      get: async () => ({ data: () => structuredClone(documents.get(path)) }),
    };
  }
  return {
    documents,
    collection: ref,
    runTransaction: (callback) => {
      const result = queue.then(async () => {
        const writes = [];
        const value = await callback({
          get: (reference) => reference.get(),
          set: (reference, data) => writes.push([reference.path, structuredClone(data)]),
        });
        for (const [path, data] of writes) documents.set(path, data);
        return value;
      });
      queue = result.catch(() => {});
      return result;
    },
  };
}
const free = async () => {
  throw new HttpsError("permission-denied", "Pro required", { reason: "pro_entitlement_required" });
};
const start = Date.parse("2026-09-06T15:59:00Z");
function fixture() {
  const db = database();
  let time = start;
  let seq = 0;
  const call = (extra = {}) => withFreeQuota({
    db, verifyPro: free, now: () => time,
    request: { auth: { uid: "alice" }, data: { mode: "emotionalSupport", requestId: `r${seq++}` } },
    run: async () => ({ reply: "ok" }), ...extra,
  });
  return { db, call, setTime: (value) => { time = value; } };
}
test("Taipei midnight resets quota, independent of client clock", () => {
  assert.equal(taipeiDay(start), "2026-09-06");
  assert.equal(taipeiDay(Date.parse("2026-09-06T16:00:00Z")), "2026-09-07");
});
test("allows three replies per mode and rejects fourth, independently for each account", async () => {
  const f = fixture();
  for (const mode of MODES) {
    for (let i = 0; i < 3; i++) {
      await f.call({ request: { auth: { uid: "alice" }, data: { mode, requestId: `${mode}-${i}` } } });
    }
    await assert.rejects(f.call({ request: { auth: { uid: "alice" }, data: { mode, requestId: "fourth" } } }),
      (error) => error.details.reason === "free_daily_quota_exhausted");
  }
  const quota = await readQuota({ db: f.db, uid: "alice", verifyPro: free, nowMs: start });
  assert.deepEqual(Object.values(quota.remaining), [0, 0, 0, 0]);
  await f.call({ request: { auth: { uid: "bob" }, data: { mode: MODES[0], requestId: "bob1" } } });
  f.setTime(start + 60000);
  await f.call();
});
test("concurrent devices cannot reserve more than three slots", async () => {
  const f = fixture();
  let release;
  const wait = new Promise((resolve) => { release = resolve; });
  const attempts = Array.from({ length: 8 }, () => f.call({ run: async () => { await wait; return { reply: "ok" }; } }));
  const outcomes = Promise.allSettled(attempts);
  await new Promise((resolve) => setImmediate(resolve));
  release();
  const results = await outcomes;
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 3);
  assert.equal(results.filter((r) => r.status === "rejected").length, 5);
});
test("failed requests and fixed safety responses release reservations", async () => {
  const f = fixture();
  for (let i = 0; i < 5; i++) {
    await assert.rejects(f.call({ run: async () => { throw new Error("upstream failed"); } }));
    await f.call({ run: async () => ({ requiresFixedSafetyUi: true }) });
  }
  const quota = await readQuota({ db: f.db, uid: "alice", verifyPro: free, nowMs: start });
  assert.equal(quota.remaining.emotionalSupport, 3);
});
test("same request cannot execute twice or deduct twice", async () => {
  const f = fixture();
  const request = { auth: { uid: "alice" }, data: { mode: MODES[0], requestId: "same" } };
  await f.call({ request });
  await assert.rejects(f.call({ request, run: () => assert.fail("duplicate ran") }), { code: "already-exists" });
  const quota = await readQuota({ db: f.db, uid: "alice", verifyPro: free, nowMs: start });
  assert.equal(quota.remaining.emotionalSupport, 2);
});
test("Pro bypasses free quota, verification outages do not grant Pro access", async () => {
  const f = fixture();
  for (let i = 0; i < 5; i++) await f.call({ verifyPro: async () => {} });
  assert.equal(f.db.documents.size, 0);
  await assert.rejects(f.call({ verifyPro: async () => { throw new HttpsError("unavailable", "outage"); } }), { code: "unavailable" });
});
test("unauthenticated and unsupported modes never invoke AI", async () => {
  const f = fixture();
  await assert.rejects(f.call({ request: { data: {} } }), { code: "unauthenticated" });
  await assert.rejects(f.call({ request: { auth: { uid: "alice" }, data: { mode: "fake" } } }), { code: "invalid-argument" });
});
test("abandoned reservations expire and stale failure cannot remove a replacement", async () => {
  const f = fixture();
  const earlier = start - 60 * 60 * 1000;
  f.setTime(earlier);
  let fail;
  const pending = new Promise((_, reject) => { fail = reject; });
  const request = { auth: { uid: "alice" }, data: { mode: MODES[0], requestId: "same" } };
  const original = f.call({ request, run: () => pending });
  const rejected = assert.rejects(original);
  await new Promise((resolve) => setImmediate(resolve));
  // Remain in the same Taipei day for the expiration test.
  f.setTime(earlier + RESERVATION_MS + 1);
  await f.call({ request });
  fail(new Error("old failure"));
  await rejected;
  const quota = await readQuota({ db: f.db, uid: "alice", verifyPro: free, nowMs: earlier + RESERVATION_MS + 1 });
  assert.equal(quota.remaining.emotionalSupport, 2);
});
