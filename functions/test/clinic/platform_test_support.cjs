"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const crypto = require("node:crypto");
const admin = require("firebase-admin");
const https = require("firebase-functions/v2/https");

// Execute the actual callable bodies/helper with an injected database transport.
// Emulator tests supply a real Admin Firestore client, not an in-memory store.
function loadPlatform(source, db, options = {}) {
  const logs = [];
  const random = { tokens: 0, requests: 0 };
  const trackedCrypto = {
    ...crypto,
    randomBytes(...args) { random.tokens++; return crypto.randomBytes(...args); },
    randomUUID() { random.requests++; return crypto.randomUUID(); },
  };
  const cache = {};
  function load(name) {
    if (cache[name]) return cache[name];
    const module = { exports: {} };
    const filename = path.resolve(__dirname, "../../..", source, "src/clinic", name);
    vm.runInNewContext(fs.readFileSync(filename, "utf8"), {
      module, exports: module.exports, Date: options.Date || Date, Buffer, console: {
        warn: (...args) => logs.push(args), error: (...args) => logs.push(args),
      },
      require(specifier) {
        if (specifier === "../config/firebase") return { db, admin };
        if (specifier === "./platform_audit") return load("platform_audit.js");
        if (specifier === "./clinic_trial") return load("clinic_trial.js");
        if (specifier === "node:crypto") return trackedCrypto;
        if (specifier === "firebase-functions/v2/https") return options.rawHandlers
          ? { ...https, onCall: (_, handler) => handler } : https;
        throw new Error(`Unexpected dependency: ${specifier}`);
      },
    }, { filename });
    cache[name] = module.exports;
    return module.exports;
  }
  return { functions: load("clinics.js"), helper: load("platform_audit.js"), logs, random };
}

function memoryDb(seed = {}, mode = {}) {
  const clone = value => value instanceof admin.firestore.Timestamp || value instanceof admin.firestore.FieldValue
    ? value : Array.isArray(value) ? value.map(clone) : value && typeof value === "object"
      ? Object.fromEntries(Object.entries(value).map(([key, item]) => [key, clone(item)])) : value;
  let docs = clone(seed);
  let generated = 0;
  let attempts = 0;
  const snapshot = ref => ({ exists: Object.hasOwn(docs, ref.path), data: () => {
    const result = clone(docs[ref.path]);
    for (const [key, value] of Object.entries(docs[ref.path] || {})) {
      if (value instanceof admin.firestore.Timestamp) result[key] = value;
    }
    return result;
  } });
  const db = {
    collection(name) {
      return { doc(id = `generated-${++generated}`) {
        return { path: `${name}/${id}`, id, get: async function () { return snapshot(this); } };
      } };
    },
    async runTransaction(callback) {
      if (mode.revoke) docs["platformAdmins/platform"].status = "inactive";
      for (let attempt = 0; attempt < (mode.retry ? 2 : 1); attempt++) {
        attempts++;
        const pending = [];
        let writing = false;
        const tx = {
          async get(ref) { if (writing) throw new Error("Read after write"); return snapshot(ref); },
        };
        for (const method of ["set", "create", "update"]) tx[method] = (ref, data) => {
          writing = true;
          pending.push({ method, ref, data });
        };
        const result = await callback(tx);
        if (mode.auditFailure) throw new Error("PRIVATE_TOKEN_DO_NOT_LOG");
        if (mode.retry && attempt === 0) continue;
        const commitTime = admin.firestore.Timestamp.now();
        const resolve = value => value instanceof admin.firestore.FieldValue &&
          value.isEqual(admin.firestore.FieldValue.serverTimestamp()) ? commitTime :
          value instanceof admin.firestore.Timestamp ? value : value && typeof value === "object"
            ? Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolve(item)])) : value;
        for (const { method, ref, data } of pending) {
          const resolved = resolve(data);
          docs[ref.path] = method === "update" ? { ...docs[ref.path], ...resolved } : resolved;
        }
        return result;
      }
    },
  };
  return { db, docs: () => docs, attempts: () => attempts };
}

const seed = () => ({
  "platformAdmins/platform": { role: "platform_admin", status: "active" },
  "clinics/a": { status: "active", active: true, primaryAdminUid: null, initialAdminInviteId: "invite-a" },
  "staffInvites/invite-a": { clinicId: "a", inviteType: "initial_admin", role: "admin", status: "pending", email: "owner@example.test", tokenHash: "old-hash", resendCount: 2 },
  "inneraCounters/clinic": { value: 8 },
});
const requests = {
  createClinic: { clinicName: "Test clinic", adminName: "Test admin", email: " OWNER@example.test " },
  setClinicStatus: { clinicId: "a", status: "inactive" },
  resendInitialAdminInvite: { clinicId: "a" },
};
const request = (name, extra = {}) => ({ auth: { uid: "platform" }, data: { ...requests[name], ...extra } });
module.exports = { loadPlatform, memoryDb, seed, requests, request };
