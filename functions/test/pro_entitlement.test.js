"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  cachedEntitlementState,
  fetchRevenueCatEntitlement,
  parseRevenueCatEntitlement,
} = require("../pro_entitlement");

test("RevenueCat lifetime premium entitlement is active", () => {
  assert.deepEqual(parseRevenueCatEntitlement({
    subscriber: { entitlements: { premium: { expires_date: null } } },
  }), { active: true, expiresAtMs: null });
});

test("RevenueCat expired premium entitlement is inactive", () => {
  const now = Date.UTC(2026, 8, 6);
  const result = parseRevenueCatEntitlement({
    subscriber: { entitlements: { premium: {
      expires_date: "2026-09-05T00:00:00Z",
      grace_period_expires_date: null,
    } } },
  }, now);
  assert.equal(result.active, false);
});

test("malformed RevenueCat expiration fails closed", () => {
  const result = parseRevenueCatEntitlement({
    subscriber: { entitlements: { premium: { expires_date: "not-a-date" } } },
  });
  assert.equal(result.active, false);
});

test("RevenueCat grace period keeps premium active", () => {
  const now = Date.UTC(2026, 8, 6);
  const result = parseRevenueCatEntitlement({
    subscriber: { entitlements: { premium: {
      expires_date: "2026-09-05T00:00:00Z",
      grace_period_expires_date: "2026-09-07T00:00:00Z",
    } } },
  }, now);
  assert.equal(result.active, true);
});

test("server lookup URL encodes uid and never exposes the key in the URL", async () => {
  let request;
  const result = await fetchRevenueCatEntitlement({
    uid: "user/with spaces",
    apiKey: "server-secret",
    fetchImpl: async (url, options) => {
      request = { url, options };
      return { ok: true, json: async () => ({ subscriber: { entitlements: {} } }) };
    },
  });
  assert.equal(request.url.endsWith("user%2Fwith%20spaces"), true);
  assert.equal(request.url.includes("server-secret"), false);
  assert.equal(request.options.headers.Authorization, "Bearer server-secret");
  assert.equal(result.active, false);
});

test("expired cached entitlement is never accepted", () => {
  const now = Date.UTC(2026, 8, 6);
  const state = cachedEntitlementState({
    active: true,
    verifiedAt: now - 1000,
    expiresAt: now - 1,
  }, now);
  assert.equal(state.active, false);
});
