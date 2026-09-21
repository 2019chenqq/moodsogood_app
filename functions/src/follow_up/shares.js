const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const {
  buildShareDocument,
  authorizeShareRevocation,
  isValidShareToken,
  validateShareDocument,
} = require("./follow_up_share");
const { db, admin } = require("../config/firebase");
const crypto = require("crypto");
const { onSchedule } = require("firebase-functions/v2/scheduler");

exports.createFollowUpSummaryShare = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再建立分享");
  const summaryId = String(request.data?.summaryId || "").trim();
  const summarySnapshot = request.data?.summarySnapshot;
  if (!summaryId || !summarySnapshot || typeof summarySnapshot !== "object") {
    throw new HttpsError("invalid-argument", "摘要資料不完整");
  }
  const share = buildShareDocument({ ownerUid: request.auth.uid, summarySnapshot });
  await db.collection("followUpSummaryShares").doc(share.shareId).set({ ...share.document, summaryId });
  return {
    shareId: share.shareId,
    url: `https://moodsogood-9e45b.web.app/follow-up-share.html?token=${encodeURIComponent(share.token)}`,
    expiresAt: share.expiresAt.toISOString(),
  };
});

exports.getFollowUpShareStatuses = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再查看分享");
  const summaryIds = Array.isArray(request.data?.summaryIds)
    ? request.data.summaryIds.map(String).filter(Boolean).slice(0, 100) : [];
  if (!summaryIds.length) return { activeShares: [] };
  const snapshot = await db.collection("followUpSummaryShares")
    .where("ownerUid", "==", request.auth.uid).get();
  const wanted = new Set(summaryIds);
  const now = Date.now();
  return { activeShares: snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((item) => wanted.has(item.summaryId) && !item.revokedAt && item.expiresAt?.toMillis?.() > now)
    .map((item) => ({ summaryId: item.summaryId, shareId: item.id,
      expiresAt: item.expiresAt.toDate().toISOString() })) };
});

exports.revokeFollowUpShare = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "請先登入後再停止分享");
  const ref = db.collection("followUpSummaryShares").doc(String(request.data?.shareId || "").trim());
  const snapshot = await ref.get();
  const authorization = authorizeShareRevocation({
    document: snapshot.exists ? snapshot.data() : null,
    ownerUid: request.auth.uid,
  });
  if (!authorization.ok) {
    throw new HttpsError(authorization.reason === "forbidden" ? "permission-denied" : "not-found", "找不到分享或沒有權限");
  }
  if (!authorization.alreadyRevoked) {
    await ref.update({ revokedAt: admin.firestore.FieldValue.serverTimestamp() });
  }
  return { revoked: true };
});

exports.getFollowUpSummaryShare = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  if (request.method === "OPTIONS") return response.status(204).send("");
  response.set("Cache-Control", "no-store");
  response.set("Referrer-Policy", "no-referrer");
  response.set("X-Content-Type-Options", "nosniff");
  if (request.method !== "GET") {
    return response.status(405).json({ error: "method_not_allowed" });
  }
  const token = String(request.query.token || "");
  if (!isValidShareToken(token)) {
    return response.status(404).json({ error: "not_found" });
  }
  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  const matches = await db.collection("followUpSummaryShares").where("tokenHash", "==", tokenHash).limit(1).get();
  const validation = validateShareDocument({
    document: matches.empty ? null : matches.docs[0].data(), token,
  });
  if (!validation.ok) return response.status(404).json({ error: validation.reason });
  return response.json({ summary: validation.summarySnapshot, expiresAt: validation.expiresAt.toISOString() });
});

exports.cleanupFollowUpSummaryShares = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 1,
    maxInstances: 1,
  },
  async () => {
    const now = Date.now();
    let deletedCount = 0;
    for (const collectionName of [
      "followUpSummaryShares",
      "follow_up_summary_shares",
    ]) {
      const snapshot = await db.collection(collectionName).get();
      const deletions = snapshot.docs.filter((doc) => {
        const data = doc.data();
        const expiresAt = data.expiresAt?.toMillis?.() ??
          new Date(data.expiresAt || 0).getTime();
        const containsPlaintext = Object.prototype.hasOwnProperty.call(
          data,
          "summarySnapshot",
        );
        return containsPlaintext || !Number.isFinite(expiresAt) || expiresAt <= now;
      });
      for (let index = 0; index < deletions.length; index += 500) {
        const batch = db.batch();
        for (const doc of deletions.slice(index, index + 500)) {
          batch.delete(doc.ref);
        }
        await batch.commit();
      }
      deletedCount += deletions.length;
    }
    console.log("Follow-up summary share cleanup completed", { deletedCount });
  },
);
