const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  SHARE_DURATION_MS,
  authorizeShareRevocation,
  buildShareDocument,
  hashToken,
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
      display: {
        keyChanges: ["變化"],
        recordEvidenceHighlights: ["心悸出現 2 天，快速記錄共 4 次。"],
        medicationSubjectiveSummaries: ["藥物甲（使用者主觀回報）：第7天感受混合。"],
        representativeHealthEvents: [{ timestamp: "must-not-leak" }],
        uid: "must-be-removed",
      },
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
  assert.equal(share.document.summarySnapshot, undefined);
  assert.equal(share.document.encryptedSummary.algorithm, "aes-256-gcm");
  assert.ok(share.document.encryptedSummary.ciphertext.length > 0);
  assert.ok(share.shareId.length >= 20);
  assert.equal(result.summarySnapshot.uid, undefined);
  assert.equal(result.summarySnapshot.email, undefined);
  assert.equal(result.summarySnapshot.display.uid, undefined);
  assert.deepEqual(result.summarySnapshot.display.keyChanges, ["變化"]);
  assert.equal(result.summarySnapshot.display.recordEvidenceHighlights.length, 1);
  assert.equal(result.summarySnapshot.display.medicationSubjectiveSummaries.length, 1);
  assert.equal(result.summarySnapshot.display.representativeHealthEvents, undefined);
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
    "card('基本資訊'", "discussion(d)",
    "card('主要變化'", "<h2>睡眠趨勢</h2>",
    "card('症狀與情緒共現模式'", "card('身體測量'",
    "card('藥物調整時間軸'", "card('其他想跟醫師說的內容'",
    "card('資料限制'",
  ];
  let previous = -1;
  for (const call of renderCalls) {
    const current = html.lastIndexOf(call);
    assert.ok(current > previous, `${call} should follow the App section order`);
    previous = current;
  }
  assert.match(html, /s\.display\|\|displayFromLegacy/);
  assert.match(html, /<li>/);
  assert.doesNotMatch(html, /card\('重要時間關聯'/);
  assert.match(html, /Math\.floor\(dataMin-1\)/);
  assert.match(html, /Math\.ceil\(dataMax\+1\)/);
  assert.match(html, /viewBox="0 0 600 220"/);
  assert.match(html, /stroke="#63A8C7"/);
  assert.match(html, /fill="#4E6AA5"/);
});

test("stored share ciphertext does not expose medical summary text", () => {
  const secretText = "體重減少 0.5kg";
  const share = buildShareDocument({
    ownerUid: "u",
    now,
    summarySnapshot: { display: { bodyMeasurements: [secretText] } },
  });
  assert.doesNotMatch(JSON.stringify(share.document), new RegExp(secretText));
  const result = validateShareDocument({ document: share.document, token: share.token, now });
  assert.equal(result.ok, true);
  assert.deepEqual(result.summarySnapshot.display.bodyMeasurements, [secretText]);
});

test("ciphertext cannot be decrypted with a different token or after tampering", () => {
  const share = buildShareDocument({ ownerUid: "u", now, summarySnapshot: { display: {} } });
  const wrongTokenDocument = { ...share.document, tokenHash: hashToken("different-token") };
  assert.deepEqual(validateShareDocument({
    document: wrongTokenDocument,
    token: "different-token",
    now,
  }), { ok: false, reason: "invalid_encrypted_summary" });

  const tampered = structuredClone(share.document);
  const ciphertext = Buffer.from(tampered.encryptedSummary.ciphertext, "base64");
  ciphertext[0] ^= 1;
  tampered.encryptedSummary.ciphertext = ciphertext.toString("base64");
  assert.deepEqual(validateShareDocument({ document: tampered, token: share.token, now }), {
    ok: false,
    reason: "invalid_encrypted_summary",
  });
});

test("legacy plaintext shares are rejected", () => {
  const token = "legacy-token";
  assert.deepEqual(validateShareDocument({
    document: {
      tokenHash: hashToken(token),
      summarySnapshot: { display: {} },
      expiresAt: new Date(now.getTime() + 1000),
      revokedAt: null,
    },
    token,
    now,
  }), { ok: false, reason: "legacy_plaintext" });
});
