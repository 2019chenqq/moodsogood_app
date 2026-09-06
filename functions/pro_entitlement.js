"use strict";

const ENTITLEMENT_COLLECTION = "server_entitlements";
const PREMIUM_ENTITLEMENT_ID = "premium";
const FRESH_CACHE_MS = 15 * 60 * 1000;
const PROVIDER_OUTAGE_GRACE_MS = 6 * 60 * 60 * 1000;

class ProEntitlementError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ProEntitlementError";
    this.code = code;
  }
}

function parseDateMs(value) {
  if (!value) return null;
  const parsed = Date.parse(String(value));
  return Number.isFinite(parsed) ? parsed : null;
}

function parseRevenueCatEntitlement(payload, nowMs = Date.now()) {
  const entitlement = payload?.subscriber?.entitlements?.[PREMIUM_ENTITLEMENT_ID];
  if (!entitlement || typeof entitlement !== "object") {
    return { active: false, expiresAtMs: null };
  }

  const expiresAtMs = parseDateMs(entitlement.expires_date);
  const graceExpiresAtMs = parseDateMs(entitlement.grace_period_expires_date);
  const effectiveExpiryMs = Math.max(expiresAtMs || 0, graceExpiresAtMs || 0) || null;
  const lifetime = entitlement.expires_date === null;
  return {
    // RevenueCat uses null expiration for lifetime entitlements.
    active: lifetime || (effectiveExpiryMs != null && effectiveExpiryMs > nowMs),
    expiresAtMs: effectiveExpiryMs,
  };
}

function timestampToMs(value) {
  if (typeof value?.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function cachedEntitlementState(data, nowMs = Date.now()) {
  if (!data || data.active !== true) return { active: false, verifiedAtMs: null };
  const verifiedAtMs = timestampToMs(data.verifiedAt);
  const expiresAtMs = timestampToMs(data.expiresAt);
  return {
    active: expiresAtMs == null || expiresAtMs > nowMs,
    verifiedAtMs,
  };
}

async function fetchRevenueCatEntitlement({ uid, apiKey, fetchImpl = fetch, nowMs }) {
  const response = await fetchImpl(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
    {
      method: "GET",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
    },
  );
  if (!response.ok) {
    throw new Error(`RevenueCat status ${response.status}`);
  }
  return parseRevenueCatEntitlement(await response.json(), nowMs);
}

async function requireProEntitlement({
  db,
  admin,
  uid,
  apiKey,
  fetchImpl = fetch,
  nowMs = Date.now(),
}) {
  if (!apiKey) {
    throw new ProEntitlementError(
      "configuration",
      "RevenueCat server API key is not configured",
    );
  }

  const ref = db.collection(ENTITLEMENT_COLLECTION).doc(uid);
  const snapshot = await ref.get();
  const cached = cachedEntitlementState(snapshot.data(), nowMs);
  if (
    cached.active &&
    cached.verifiedAtMs != null &&
    nowMs - cached.verifiedAtMs <= FRESH_CACHE_MS
  ) {
    return;
  }

  try {
    const current = await fetchRevenueCatEntitlement({
      uid,
      apiKey,
      fetchImpl,
      nowMs,
    });
    await ref.set({
      active: current.active,
      entitlementId: PREMIUM_ENTITLEMENT_ID,
      source: "revenuecat_server_api",
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: current.expiresAtMs == null
        ? null
        : admin.firestore.Timestamp.fromMillis(current.expiresAtMs),
    });
    if (!current.active) {
      throw new ProEntitlementError("required", "Active Pro entitlement required");
    }
  } catch (error) {
    if (error instanceof ProEntitlementError) throw error;
    if (
      cached.active &&
      cached.verifiedAtMs != null &&
      nowMs - cached.verifiedAtMs <= PROVIDER_OUTAGE_GRACE_MS
    ) {
      return;
    }
    throw new ProEntitlementError(
      "unavailable",
      "Unable to verify RevenueCat entitlement",
    );
  }
}

module.exports = {
  ENTITLEMENT_COLLECTION,
  FRESH_CACHE_MS,
  PREMIUM_ENTITLEMENT_ID,
  PROVIDER_OUTAGE_GRACE_MS,
  ProEntitlementError,
  cachedEntitlementState,
  fetchRevenueCatEntitlement,
  parseRevenueCatEntitlement,
  requireProEntitlement,
};
