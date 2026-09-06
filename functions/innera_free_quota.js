"use strict";

const { createHash, randomUUID } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");

const MODES = ["emotionalSupport", "dailyRecord", "physicalHealth", "recentReview"];
const DAILY_LIMIT = 3;
// Longer than the callable's execution deadline; abandoned reservations expire.
const RESERVATION_MS = 5 * 60 * 1000;
const COLLECTION = "innera_free_quota";

function taipeiDay(nowMs = Date.now()) {
  return new Date(nowMs + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function liveEntries(data, nowMs) {
  return (data?.entries || []).filter(
    (entry) => entry.status === "done" || entry.expiresAt > nowMs,
  );
}

function quotaRef(db, uid, day, mode) {
  return db.collection(COLLECTION).doc(uid).collection("days").doc(`${day}_${mode}`);
}

async function isPro(verifyPro, uid) {
  try {
    await verifyPro(uid);
    return true;
  } catch (error) {
    // Verification outages must not silently downgrade an active subscriber.
    if (error.details?.reason === "pro_entitlement_required") return false;
    throw error;
  }
}

async function readQuota({ db, uid, verifyPro, nowMs = Date.now() }) {
  const pro = await isPro(verifyPro, uid);
  const date = taipeiDay(nowMs);
  const remaining = {};
  if (!pro) {
    await Promise.all(MODES.map(async (mode) => {
      const snapshot = await quotaRef(db, uid, date, mode).get();
      remaining[mode] = Math.max(0, DAILY_LIMIT - liveEntries(snapshot.data(), nowMs).length);
    }));
  }
  return { pro, date, limit: DAILY_LIMIT, remaining, timeZone: "Asia/Taipei" };
}

async function withFreeQuota({ db, request, verifyPro, run, now = Date.now }) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "請先登入後再使用心域 AI");
  const mode = String(request.data?.mode || "emotionalSupport").trim();
  if (!MODES.includes(mode)) throw new HttpsError("invalid-argument", "Unsupported AI mode");
  if (await isPro(verifyPro, uid)) return run(request);

  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || !requestId.trim() || requestId.length > 200) {
    throw new HttpsError("invalid-argument", "請更新 App 後再試（缺少訊息識別碼）。");
  }
  const id = createHash("sha256").update(requestId).digest("hex");
  const token = randomUUID();
  const start = now();
  const ref = quotaRef(db, uid, taipeiDay(start), mode);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const entries = liveEntries(snapshot.data(), start);
    const duplicate = entries.find((entry) => entry.id === id);
    if (duplicate) {
      throw new HttpsError(duplicate.status === "done" ? "already-exists" : "aborted",
        duplicate.status === "done"
          ? "這則訊息已處理完成，不會重複扣除額度。請查看原對話。"
          : "這則訊息仍在處理中，請稍候。",
        { reason: "free_quota_duplicate" });
    }
    if (entries.length >= DAILY_LIMIT) {
      throw new HttpsError("resource-exhausted",
        "此模式今日免費額度已用完，可於台灣時間凌晨 00:00 後再來，或升級 Pro。",
        { reason: "free_daily_quota_exhausted", mode, limit: DAILY_LIMIT, remaining: 0 });
    }
    entries.push({ id, token, status: "pending", expiresAt: start + RESERVATION_MS });
    // Store counters and hashed IDs only, never conversation content.
    tx.set(ref, { entries });
  });

  async function settle(success) {
    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      const entries = snapshot.data()?.entries || [];
      const owned = entries.find((entry) => entry.token === token);
      if (!owned || owned.status === "done") return;
      tx.set(ref, { entries: success
        ? entries.map((entry) => entry.token === token ? { ...entry, status: "done" } : entry)
        : entries.filter((entry) => entry.token !== token) });
    });
  }

  let response;
  try {
    response = await run(request);
  } catch (error) {
    await settle(false);
    throw error;
  }
  // Fixed safety notices do not consume the free AI allowance.
  await settle(response?.requiresFixedSafetyUi !== true);
  return response;
}

module.exports = { DAILY_LIMIT, MODES, RESERVATION_MS, taipeiDay, liveEntries, readQuota, withFreeQuota };
