const crypto = require("crypto");

const SHARE_DURATION_MS = 36 * 60 * 60 * 1000;
const ENCRYPTION_VERSION = 1;
const ENCRYPTION_ALGORITHM = "aes-256-gcm";
const ENCRYPTION_INFO = Buffer.from("moodsogood-follow-up-share-v1", "utf8");
const ALLOWED_KEYS = new Set([
  "appointmentDate",
  "periodStart",
  "periodEnd",
  "validRecordDays",
  "selectedTopics",
  "discussionDetails",
  "additionalNotes",
  "aiOutput",
  "sleepSummary",
  "sleepTrend",
  "medicationTimeline",
  "schemaVersion",
  "display",
]);
const DISPLAY_KEYS = new Set([
  "schemaVersion", "visitInfo", "topicLabels", "discussionItems",
  "keyChanges", "timelineRelations", "userSharedNotes",
  "recordEvidenceHighlights", "medicationSubjectiveSummaries",
  "symptoms", "bodyMeasurements", "sleepSummaryItems", "sleepTrend", "medicationTimeline",
  "dataLimitations", "generatedAt", "disclaimer",
  "includedSections",
]);
const PUBLIC_TEXT_ARRAY_KEYS = [
  "discussionItems", "keyChanges", "userSharedNotes", "dataLimitations",
  "symptoms", "bodyMeasurements",
  "recordEvidenceHighlights", "medicationSubjectiveSummaries",
];

function isQuestionAnswerTranscript(value) {
  return /(AI\s*補問|使用者(?:原始)?回答|問題[一二三四五0-9]|(^|[\s　])問[：:]|(^|[\s　])答[：:]|回答[：:])/i
    .test(String(value || ""));
}

function createToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function createShareId() {
  return crypto.randomBytes(18).toString("base64url");
}

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token)).digest("hex");
}

function encryptSummarySnapshot(summarySnapshot, token) {
  const salt = crypto.randomBytes(16);
  const iv = crypto.randomBytes(12);
  const tokenHash = hashToken(token);
  const key = crypto.hkdfSync(
    "sha256",
    Buffer.from(String(token), "utf8"),
    salt,
    ENCRYPTION_INFO,
    32,
  );
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGORITHM, key, iv);
  cipher.setAAD(Buffer.from(tokenHash, "utf8"));
  const plaintext = Buffer.from(JSON.stringify(summarySnapshot), "utf8");
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    version: ENCRYPTION_VERSION,
    algorithm: ENCRYPTION_ALGORITHM,
    salt: salt.toString("base64"),
    iv: iv.toString("base64"),
    ciphertext: ciphertext.toString("base64"),
    authTag: cipher.getAuthTag().toString("base64"),
  };
}

function decryptSummarySnapshot(encryptedSummary, token) {
  if (!encryptedSummary ||
      encryptedSummary.version !== ENCRYPTION_VERSION ||
      encryptedSummary.algorithm !== ENCRYPTION_ALGORITHM) {
    throw new Error("unsupported_encryption");
  }
  const salt = Buffer.from(String(encryptedSummary.salt || ""), "base64");
  const iv = Buffer.from(String(encryptedSummary.iv || ""), "base64");
  const authTag = Buffer.from(String(encryptedSummary.authTag || ""), "base64");
  const ciphertext = Buffer.from(
    String(encryptedSummary.ciphertext || ""),
    "base64",
  );
  if (salt.length !== 16 || iv.length !== 12 || authTag.length !== 16 ||
      ciphertext.length === 0) {
    throw new Error("invalid_encrypted_summary");
  }
  const tokenHash = hashToken(token);
  const key = crypto.hkdfSync(
    "sha256",
    Buffer.from(String(token), "utf8"),
    salt,
    ENCRYPTION_INFO,
    32,
  );
  const decipher = crypto.createDecipheriv(ENCRYPTION_ALGORITHM, key, iv);
  decipher.setAAD(Buffer.from(tokenHash, "utf8"));
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]).toString("utf8");
  return JSON.parse(plaintext);
}

function sanitizeSummarySnapshot(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("invalid_summary_snapshot");
  }
  const snapshot = Object.fromEntries(
    Object.entries(value).filter(([key]) => ALLOWED_KEYS.has(key)),
  );
  if (snapshot.display && typeof snapshot.display === "object" &&
      !Array.isArray(snapshot.display)) {
    snapshot.display = Object.fromEntries(
      Object.entries(snapshot.display)
        .filter(([key]) => DISPLAY_KEYS.has(key)),
    );
    for (const key of PUBLIC_TEXT_ARRAY_KEYS) {
      if (Array.isArray(snapshot.display[key])) {
        snapshot.display[key] = snapshot.display[key]
          .filter((item) => typeof item === "string")
          .filter((item) => !isQuestionAnswerTranscript(item));
      }
    }
    // New clients send the canonical display model. Do not retain parallel raw
    // fields that could contain unchecked user text.
    return {
      schemaVersion: snapshot.schemaVersion,
      display: snapshot.display,
    };
  }
  return snapshot;
}

function buildShareDocument({ ownerUid, summarySnapshot, now = new Date() }) {
  const shareId = createShareId();
  const token = createToken();
  const expiresAt = new Date(now.getTime() + SHARE_DURATION_MS);
  return {
    shareId,
    token,
    tokenHash: hashToken(token),
    expiresAt,
    document: {
      ownerUid,
      tokenHash: hashToken(token),
      encryptedSummary: encryptSummarySnapshot(
        sanitizeSummarySnapshot(summarySnapshot),
        token,
      ),
      createdAt: now,
      expiresAt,
      revokedAt: null,
    },
  };
}

function authorizeShareRevocation({ document, ownerUid }) {
  if (!document) return { ok: false, reason: "not_found" };
  if (!ownerUid || document.ownerUid !== ownerUid) {
    return { ok: false, reason: "forbidden" };
  }
  if (document.revokedAt) {
    return { ok: true, alreadyRevoked: true };
  }
  return { ok: true, alreadyRevoked: false };
}

function validateShareDocument({ document, token, now = new Date() }) {
  if (!document || !token) return { ok: false, reason: "not_found" };
  const suppliedHash = hashToken(token);
  const storedHash = String(document.tokenHash || "");
  const sameLength = suppliedHash.length === storedHash.length;
  const validHash = sameLength && crypto.timingSafeEqual(
    Buffer.from(suppliedHash),
    Buffer.from(storedHash),
  );
  if (!validHash) return { ok: false, reason: "invalid_token" };
  if (document.revokedAt) return { ok: false, reason: "revoked" };
  const expiresAt = document.expiresAt instanceof Date
    ? document.expiresAt
    : document.expiresAt?.toDate?.() || new Date(document.expiresAt);
  if (!expiresAt || Number.isNaN(expiresAt.getTime()) || expiresAt <= now) {
    return { ok: false, reason: "expired" };
  }
  // Legacy shares stored medical summaries as plaintext. They cannot be
  // migrated because only the recipient URL contains the original token.
  if (!document.encryptedSummary) {
    return { ok: false, reason: document.summarySnapshot ? "legacy_plaintext" : "not_found" };
  }
  try {
    return {
      ok: true,
      summarySnapshot: decryptSummarySnapshot(document.encryptedSummary, token),
      expiresAt,
    };
  } catch (_) {
    return { ok: false, reason: "invalid_encrypted_summary" };
  }
}

module.exports = {
  SHARE_DURATION_MS,
  authorizeShareRevocation,
  buildShareDocument,
  decryptSummarySnapshot,
  encryptSummarySnapshot,
  hashToken,
  sanitizeSummarySnapshot,
  validateShareDocument,
};
