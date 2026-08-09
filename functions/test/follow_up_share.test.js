const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  SHARE_DURATION_MS,
  authorizeShareRevocation,
  buildShareDocument,
  validateShareDocument,
} = require("../follow_up_share");

const now = new Date("2026-08-05T06:00:00.000Z");

test("normal share is valid for 36 hours and contains no identifiers", () => {
  const share = buildShareDocument({
    ownerUid: "private-owner",
    now,
    summarySnapshot: {
      periodStart: "2026-07-20",
      periodEnd: "2026-08-05",
      validRecordDays: 8,
      uid: "must-be-removed",
      email: "must-be-removed@example.com",
      additionalNotes: "unchecked raw text",
      display: { keyChanges: ["變化"], uid: "must-be-removed" },
    },
  });
  const result = validateShareDocument({
    document: share.document,
    token: share.token,
    now: new Date(now.getTime() + 1000),
  });
  assert.equal(result.ok, true);
  assert.equal(share.expiresAt.getTime() - now.getTime(), SHARE_DURATION_MS);
  assert.equal(share.document.token, undefined);
  assert.ok(share.shareId.length >= 20);
  assert.equal(result.summarySnapshot.uid, undefined);
  assert.equal(result.summarySnapshot.email, undefined);
  assert.equal(result.summarySnapshot.display.uid, undefined);
  assert.deepEqual(result.summarySnapshot.display.keyChanges, ["變化"]);
  assert.equal(result.summarySnapshot.additionalNotes, undefined);
});

test("new shares always use a new shareId and token", () => {
  const first = buildShareDocument({ ownerUid: "u", now, summarySnapshot: {} });
  const second = buildShareDocument({ ownerUid: "u", now, summarySnapshot: {} });
  assert.notEqual(first.shareId, second.shareId);
  assert.notEqual(first.token, second.token);
  assert.notEqual(first.tokenHash, second.tokenHash);
});

test("share revocation requires the owner and handles an existing revoke", () => {
  const share = buildShareDocument({ ownerUid: "owner", now, summarySnapshot: {} });
  assert.deepEqual(authorizeShareRevocation({
    document: null,
    ownerUid: "owner",
  }), { ok: false, reason: "not_found" });
  assert.deepEqual(authorizeShareRevocation({
    document: share.document,
    ownerUid: "another-user",
  }), { ok: false, reason: "forbidden" });
  assert.deepEqual(authorizeShareRevocation({
    document: share.document,
    ownerUid: "owner",
  }), { ok: true, alreadyRevoked: false });
  share.document.revokedAt = now;
  assert.deepEqual(authorizeShareRevocation({
    document: share.document,
    ownerUid: "owner",
  }), { ok: true, alreadyRevoked: true });
});

test("expired share is rejected", () => {
  const share = buildShareDocument({ ownerUid: "u", now, summarySnapshot: {} });
  const result = validateShareDocument({
    document: share.document,
    token: share.token,
    now: new Date(now.getTime() + SHARE_DURATION_MS + 1),
  });
  assert.deepEqual(result, { ok: false, reason: "expired" });
});

test("revoked share is rejected", () => {
  const share = buildShareDocument({ ownerUid: "u", now, summarySnapshot: {} });
  share.document.revokedAt = new Date(now.getTime() + 1000);
  const result = validateShareDocument({
    document: share.document,
    token: share.token,
    now,
  });
  assert.deepEqual(result, { ok: false, reason: "revoked" });
});

test("wrong token is rejected", () => {
  const share = buildShareDocument({ ownerUid: "u", now, summarySnapshot: {} });
  const result = validateShareDocument({
    document: share.document,
    token: "wrong-token",
    now,
  });
  assert.deepEqual(result, { ok: false, reason: "invalid_token" });
});

test("public page renders the canonical display model in App order", () => {
  const html = fs.readFileSync(
    path.join(__dirname, "..", "..", "public", "follow-up-share.html"),
    "utf8",
  );
  const renderCalls = [
    "card('回診資料'", "discussion(d)", "card('主要變化'",
    "card('重要時間關聯'", "<h2>睡眠趨勢</h2>",
    "card('藥物調整時間軸'", "card('其他想跟醫師說的內容'",
    "card('資料限制'", "card('AI 整理時間'",
  ];
  let previous = -1;
  for (const call of renderCalls) {
    const current = html.lastIndexOf(call);
    assert.ok(current > previous, `${call} should follow the App section order`);
    previous = current;
  }
  assert.match(html, /s\.display\|\|displayFromLegacy/);
  assert.match(html, /<li>/);
});
