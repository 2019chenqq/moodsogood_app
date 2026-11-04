"use strict";

const { describe, it, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { loadPlatform, seed, requests, request } = require("./platform_test_support.cjs");

for (const source of ["functions", "functions_demo"]) {
  describe(`${source}: real Firestore transaction integration`, { concurrency: false }, () => {
    const projectId = `demo-innera-platform-atomic-${source === "functions" ? "prod" : "demo"}`;
    let app, db, host;
    before(() => {
      host = process.env.FIRESTORE_EMULATOR_HOST || "";
      assert.match(host, /^127\.0\.0\.1:\d+$/, "Local Emulator required; no cloud fallback allowed");
      app = initializeApp({ projectId }, projectId);
      db = getFirestore(app);
    });
    beforeEach(async () => {
      const response = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
      assert.equal(response.ok, true);
      const batch = db.batch();
      for (const [name, data] of Object.entries(seed())) batch.set(db.doc(name), data);
      await batch.commit();
    });
    after(async () => { if (db) await db.terminate(); if (app) await deleteApp(app); });

    function load(mode = {}) {
      let auditRef, attempts = 0;
      const transport = {
        collection(name) {
          const collection = db.collection(name);
          return { doc(id) {
            const ref = id === undefined ? collection.doc() : collection.doc(id);
            if (name === "auditLogs") auditRef = ref;
            return ref;
          } };
        },
        async runTransaction(callback) {
          // Test-only fault injection outside the production callback.
          if (mode.revoke) await db.doc("platformAdmins/platform").update({ status: "inactive" });
          // A real server-side create precondition failure, not a mocked write.
          if (mode.auditCollision) await auditRef.create({ collisionFixture: true });
          return db.runTransaction(async tx => {
            attempts++;
            if (mode.revokeOnRetry && attempts === 2) {
              await db.doc("platformAdmins/platform").update({ status: "inactive" });
            }
            const result = await callback(tx);
            if ((mode.retry || mode.revokeOnRetry) && attempts === 1) {
              // Drive the real SDK's ABORTED retry path with queued real writes.
              const error = new Error("Injected ABORTED"); error.code = 10; throw error;
            }
            return result;
          }, { maxAttempts: 3 });
        },
      };
      return { ...loadPlatform(source, transport), attempts: () => attempts };
    }
    async function entries(collection) {
      const snap = await db.collection(collection).get();
      return snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    }
    async function businessState() {
      return Promise.all(["clinics", "staffInvites", "inneraCounters"].map(entries));
    }
    async function verifySuccess(name, result) {
      assert.equal(result.success, true);
      const logs = await entries("auditLogs"); assert.equal(logs.length, 1);
      const audit = logs[0];
      assert.equal(audit.result, "success"); assert.equal(audit.actorUid, "platform");
      assert.equal(audit.actorClinicId, "platform"); assert.equal(audit.id, audit.requestId);
      assert.equal(audit.targetClinicId, result.clinicId);
      const serialized = JSON.stringify(logs);
      for (const secret of [result.token, "owner@example.test", "Test admin"].filter(Boolean)) assert.ok(!serialized.includes(secret));
      if (name === "createClinic") {
        assert.deepEqual(Object.keys(result).sort(), ["success", "clinicId", "clinicCode", "adminEmail", "inviteId", "token", "expiresAt"].sort());
        assert.equal(result.clinicCode, "CL00009");
        assert.equal((await db.doc("inneraCounters/clinic").get()).data().value, 9);
        assert.equal((await entries("clinics")).length, 2);
        assert.equal((await entries("staffInvites")).length, 2);
        const invitation = (await db.doc(`staffInvites/${result.inviteId}`).get()).data();
        assert.equal(invitation.tokenHash, crypto.createHash("sha256").update(result.token).digest("hex"));
        assert.equal(invitation.role, "admin"); assert.equal(invitation.email, result.adminEmail);
        assert.equal(audit.action, "clinic.create"); assert.equal(audit.eventType, "clinic_and_invitation_created");
      } else if (name === "setClinicStatus") {
        assert.equal(result.status, "inactive"); assert.equal(result.changed, true);
        const clinic = (await db.doc("clinics/a").get()).data();
        assert.equal(clinic.status, "inactive"); assert.equal(clinic.active, true);
        assert.equal(clinic.updatedBy, "platform");
        assert.equal(audit.before.status, "active"); assert.equal(audit.after.status, "inactive");
        assert.equal(audit.action, "clinic.disable");
      } else {
        assert.deepEqual(Object.keys(result).sort(), ["success", "clinicId", "inviteId", "adminEmail", "token", "expiresAt", "resendCount"].sort());
        const invite = (await db.doc("staffInvites/invite-a").get()).data();
        assert.equal(result.resendCount, 3); assert.equal(invite.resendCount, 3);
        assert.equal(invite.tokenHash, crypto.createHash("sha256").update(result.token).digest("hex"));
        assert.equal(invite.email, "owner@example.test"); assert.equal(invite.role, "admin");
        assert.equal(audit.action, "clinic.initial_admin_invite.resend"); assert.equal(audit.eventType, "invitation_rotated");
        assert.equal(audit.before.resendCount, 2); assert.equal(audit.after.resendCount, 3);
      }
    }

    for (const name of Object.keys(requests)) {
      it(`${name}: commits compatible business result and one success audit`, async () => {
        const loaded = load(); const result = await loaded.functions[name].run(request(name));
        await verifySuccess(name, result); assert.equal(loaded.logs.length, 0);
      });
      it(`${name}: real audit create-precondition failure rolls back every business write`, async () => {
        const previous = await businessState(); const loaded = load({ auditCollision: true });
        await assert.rejects(loaded.functions[name].run(request(name)), { code: "internal" });
        assert.deepEqual(await businessState(), previous);
        const logs = await entries("auditLogs"); assert.equal(logs.length, 1); assert.equal(logs[0].collisionFixture, true);
        assert.equal(logs[0].result, undefined); assert.equal(loaded.logs[0][1].result, "failure");
      });
      it(`${name}: real SDK retry commits once with stable audit/token allocations`, async () => {
        const loaded = load({ retry: true }); const result = await loaded.functions[name].run(request(name));
        assert.equal(loaded.attempts(), 2); assert.equal(loaded.random.requests, 1);
        assert.equal(loaded.random.tokens, name === "setClinicStatus" ? 0 : 1);
        await verifySuccess(name, result);
      });
      it(`${name}: revoked identity after entry validation cannot commit`, async () => {
        const previous = await businessState(); const loaded = load({ revoke: true });
        await assert.rejects(loaded.functions[name].run(request(name)), { code: "permission-denied" });
        assert.deepEqual(await businessState(), previous); assert.equal((await entries("auditLogs")).length, 0);
      });
      it(`${name}: revocation between retry attempts prevents all queued writes`, async () => {
        const previous = await businessState(); const loaded = load({ revokeOnRetry: true });
        await assert.rejects(loaded.functions[name].run(request(name)), { code: "permission-denied" });
        assert.equal(loaded.attempts(), 2);
        assert.deepEqual(await businessState(), previous); assert.equal((await entries("auditLogs")).length, 0);
      });
    }
    it("same status is a no-op; subsequent enable preserves existing fields and action", async () => {
      const loaded = load(); const previous = await businessState();
      const result = await loaded.functions.setClinicStatus.run(request("setClinicStatus", { status: "active" }));
      assert.equal(result.changed, false); assert.deepEqual(await businessState(), previous);
      assert.equal((await entries("auditLogs")).length, 0);
      await db.doc("clinics/a").update({ status: "inactive" });
      const enabled = await loaded.functions.setClinicStatus.run(request("setClinicStatus", { status: "active" }));
      assert.equal(enabled.changed, true); assert.equal((await entries("auditLogs"))[0].action, "clinic.enable");
    });
    it("inactive clinic cannot rotate its invitation", async () => {
      await db.doc("clinics/a").update({ status: "inactive" }); const previous = await businessState(); const loaded = load();
      await assert.rejects(loaded.functions.resendInitialAdminInvite.run(request("resendInitialAdminInvite")), { code: "failed-precondition" });
      assert.deepEqual(await businessState(), previous); assert.equal((await entries("auditLogs")).length, 0);
    });
    it("extra request fields cannot replace recipient or role", async () => {
      const loaded = load();
      const result = await loaded.functions.resendInitialAdminInvite.run(request("resendInitialAdminInvite", { email: "attacker@example.test", role: "doctor" }));
      await verifySuccess("resendInitialAdminInvite", result);
    });
  });
}
