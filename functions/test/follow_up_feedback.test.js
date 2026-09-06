"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { feedbackId, validateFeedback, submitFeedback } = require("../follow_up_feedback");
const { buildReport } = require("../scripts/export_follow_up_feedback");
const no = { summaryId: "summary-1", shownToDoctor: false };
const yes = { summaryId: "summary-1", shownToDoctor: true,
  surfacedForgottenInfo: "yes", hadDeeperDiscussion: "unsure", doctorRequestedAgain: "notMentioned" };

test("only coded answers accepted; No nulls follow-up answers", () => {
  assert.equal(validateFeedback(no).hadDeeperDiscussion, null);
  assert.equal(validateFeedback(yes).doctorRequestedAgain, "notMentioned");
  for (const invalid of [{ ...no, note: "private" }, { ...no, summaryId: "../other" },
    { ...yes, hadDeeperDiscussion: "free text" }, { ...no, shownToDoctor: "false" },
    { ...yes, doctorRequestedAgain: null }, { ...no, hadDeeperDiscussion: "yes" },
    { ...no, submittedAt: "forged" }]) {
    assert.throws(() => validateFeedback(invalid), { code: "invalid-argument" });
  }
});

test("authentication, ownership, replacement and server timestamp", async () => {
  const stored = new Map();
  let owned = true;
  const db = { doc: (path) => path, collection: () => ({ doc: (id) => id }),
    runTransaction: async (fn) => fn({ get: async (path) => {
      assert.equal(path, "users/alice/followUpSummaries/summary-1");
      return { exists: owned };
    }, set: (ref, data) => stored.set(ref, data) }) };
  await assert.rejects(submitFeedback(db, { data: no }, () => 1), { code: "unauthenticated" });
  owned = false;
  await assert.rejects(submitFeedback(db, { auth: { uid: "alice" }, data: no }, () => 1), { code: "not-found" });
  assert.equal(stored.size, 0);
  owned = true;
  await submitFeedback(db, { auth: { uid: "alice" }, data: yes }, () => 1);
  await submitFeedback(db, { auth: { uid: "alice" }, data: no }, () => 2);
  assert.equal(stored.size, 1);
  assert.deepEqual([...stored.values()][0], { ...validateFeedback(no), submittedAt: 2 });
  assert.notEqual(feedbackId("alice", "summary-1"), feedbackId("bob", "summary-1"));
});

test("CSV excludes identifiers; follow-up denominator is shown-to-doctor only", () => {
  const report = buildReport([no, yes].map((data) => ({ ...data, uid: "private-id",
    submittedAt: new Date("2026-09-06T00:00:00Z") })));
  assert.equal(report.rates.shownToDoctor.percent.true, 50);
  assert.equal(report.rates.surfacedForgottenInfo.denominator, 1);
  assert.equal(report.rates.surfacedForgottenInfo.percent.yes, 100);
  assert.ok(!report.csv.includes("private-id"));
  assert.ok(!report.csv.includes("summary-1"));
  assert.equal(buildReport([]).rates.hadDeeperDiscussion.percent.yes, null);
  assert.throws(() => buildReport([{ ...yes, hadDeeperDiscussion: "=CMD()" }]));
});
