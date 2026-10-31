"use strict";
const crypto = require("node:crypto");
const { aad, ALGORITHM, WRAPPING } = require("../protocol");
const VERSION = "projects/innera-demo/locations/global/keyRings/demo/cryptoKeys/clinic-a/cryptoKeyVersions/1";
const keyPair = crypto.generateKeyPairSync("rsa", { modulusLength: 3072 });
const sleep = { date: "2026-10-01", bedTime: "22:30", sleepStart: "23:00", wakeTime: "07:00",
  activityWakeTime: "07:15", durationMinutes: 480, quality: 4, sleepConditions: ["合成測試紀錄"] };
function encrypt({ uid = "fake-patient", clinicId = "clinic-a", id = "opaque-record", epoch = 1, version = VERSION, type = "sleepRecords", payload = sleep } = {}) {
  const key = crypto.randomBytes(32); const nonce = crypto.randomBytes(12);
  const envelope = { schemaVersion: 1, algorithm: ALGORITHM, wrappingAlgorithm: WRAPPING, keyVersion: version, epoch };
  const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(aad(uid, clinicId, id, envelope, type));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(payload)), cipher.final()]);
  const wrapped = crypto.publicEncrypt({ key: keyPair.publicKey, oaepHash: "sha256", padding: crypto.constants.RSA_PKCS1_OAEP_PADDING }, key);
  key.fill(0);
  return { ...envelope, nonce: nonce.toString("base64"), ciphertext: ciphertext.toString("base64"),
    authenticationTag: cipher.getAuthTag().toString("base64"), wrappedDataKey: wrapped.toString("base64") };
}
function unwrap(version, bytes) {
  return crypto.privateDecrypt({ key: keyPair.privateKey, oaepHash: "sha256", padding: crypto.constants.RSA_PKCS1_OAEP_PADDING }, bytes);
}

class MemoryDb {
  constructor() { this.data = new Map(); this.failAudit = false; }
  doc(path) {
    return { path, id: path.split("/").at(-1), collection: name => this.collection(`${path}/${name}`) };
  }
  collection(path) {
    const query = { path, max: Infinity, condition: null, doc: id => this.doc(`${path}/${id}`) };
    query.limit = n => ({ ...query, max: n });
    query.where = (field, op, value) => {
      const result = { ...query, condition: [field, value] };
      result.limit = n => ({ ...result, max: n }); return result;
    };
    return query;
  }
  snap(ref) { return { id: ref.id, ref, data: () => structuredClone(this.data.get(ref.path)) }; }
  async runTransaction(action) {
    const writes = [];
    const result = await action({
      get: async ref => {
        if (ref.max === undefined) return this.snap(ref);
        const docs = [...this.data.keys()].filter(p => p.startsWith(`${ref.path}/`) && p.split("/").length === ref.path.split("/").length + 1)
          .filter(p => !ref.condition || this.data.get(p)[ref.condition[0]] === ref.condition[1])
          .slice(0, ref.max).map(p => this.snap(this.doc(p)));
        return { size: docs.length, docs };
      },
      set: (ref, data) => { if (this.failAudit && ref.path.startsWith("demoEncryptedAudit/")) throw Error("audit unavailable"); writes.push([ref.path, data]); },
      delete: ref => writes.push([ref.path, undefined]),
    });
    for (const [path, value] of writes) {
      if (value === undefined) this.data.delete(path); else this.data.set(path, structuredClone(value));
    }
    return result;
  }
}
function fixture(db) {
  db.data.set("clinics/clinic-a", { status: "active" });
  db.data.set("clinicStaff/doctor", { status: "active", role: "doctor", clinicId: "clinic-a" });
  db.data.set("demoEncryptedFixtures/fake-patient", { synthetic: true, clinicId: "clinic-a", patientId: "fake-chart" });
  db.data.set("inneraPatients/fake-chart", { linked: true, firebaseUid: "fake-patient", clinicId: "clinic-a" });
}
function request(uid, data = {}) { return { auth: { uid, token: { firebase: { sign_in_provider: "password" } } }, app: { appId: "demo-app" }, data: { clinicId: "clinic-a", ...data } }; }
module.exports = { VERSION, keyPair, sleep, encrypt, unwrap, MemoryDb, fixture, request };
