"use strict";
const { describe, it, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const { loadPlatform, seed } = require("./platform_test_support.cjs");
const data = () => ({
  contactName: "Private contact", contactTitle: "Private title", contactEmail: "private@example.test",
  contactPhone: "+886-0000", clinicType: "hospital", cooperationNotes: "Private notes <script>text</script>",
});
for (const [index, source] of ["functions", "functions_demo"].entries()) {
  describe(`${source}: operations Firestore integration`, { concurrency: false }, () => {
    const projectId = `demo-innera-operations-${index}`;
    let app, db, host, env;
    before(async () => {
      host = process.env.FIRESTORE_EMULATOR_HOST || "";
      assert.match(host, /^127\.0\.0\.1:\d+$/, "Local Emulator required; never fall back to cloud");
      app = initializeApp({ projectId }, projectId);
      db = getFirestore(app);
      env = await initializeTestEnvironment({
        projectId,
        firestore: { rules: fs.readFileSync(path.resolve(__dirname, "../../..",
          index ? "firestore.demo.rules" : "firestore.rules"), "utf8") },
      });
    });
    beforeEach(async () => {
      const response = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
      assert.equal(response.ok, true);
      const batch = db.batch();
      const fixtures = seed();
      fixtures["clinics/a"].createdAt = Timestamp.fromMillis(1000);
      fixtures["clinicStaff/staff"] = { clinicId: "a", role: "admin", active: true, status: "active" };
      for (const [key, value] of Object.entries(fixtures)) batch.set(db.doc(key), value);
      await batch.commit();
    });
    after(async () => {
      if (env) await env.cleanup();
      if (db) await db.terminate();
      if (app) await deleteApp(app);
    });
    function load(mode = {}) {
      let auditRef, attempts = 0;
      const transport = {
        collection(name) {
          return { doc(id) {
            const ref = id === undefined ? db.collection(name).doc() : db.collection(name).doc(id);
            if (name === "auditLogs") auditRef = ref;
            if (name === "auditLogs" && mode.timestampReadFailure) ref.get = async () => { throw new Error("Injected metadata read failure"); };
            return ref;
          } };
        },
        async runTransaction(callback) {
          if (mode.collision) await auditRef.create({ collisionFixture: true });
          if (mode.revoke) await db.doc("platformAdmins/platform").update({ status: "inactive" });
          const result = await db.runTransaction(async tx => {
            attempts++;
            if (attempts === 2 && mode.revokeOnRetry) await db.doc("platformAdmins/platform").update({ status: "inactive" });
            if (attempts === 2 && mode.conflictOnRetry) {
              await db.doc("clinicOperations/a").set({ ...data(), schemaVersion: 1, revision: 1 });
            }
            const result = await callback(tx);
            if (attempts === 1 && (mode.retry || mode.revokeOnRetry || mode.conflictOnRetry)) {
              const error = new Error("Injected SDK ABORTED"); error.code = 10; throw error;
            }
            return result;
          }, { maxAttempts: 3 });
          if (mode.advanceAfterCommit) {
            await db.doc("clinicOperations/a").update({ revision: 2, updatedAt: Timestamp.fromMillis(2000000000000) });
          }
          return result;
        },
      };
      return { ...loadPlatform(source, transport), attempts: () => attempts };
    }
    const read = (loaded, clinicId = "a") => loaded.functions.getClinicDetails.run({ auth: { uid: "platform" }, data: { clinicId } });
    const save = (loaded, expectedRevision = 0, operations = data(), clinicId = "a") =>
      loaded.functions.updateClinicOperations.run({ auth: { uid: "platform" }, data: { clinicId, expectedRevision, operations } });
    const auditDocs = async () => (await db.collection("auditLogs").get()).docs.map(doc => doc.data());
    it("create/read/update/clear serialize fields and preserve clinic and creation metadata", async () => {
      const original = (await db.doc("clinics/a").get()).data();
      const loaded = load();
      const empty = await read(loaded);
      assert.equal(empty.operations, null); assert.equal(empty.revision, 0);
      assert.equal(empty.updatedAt, null);
      assert.deepEqual(JSON.parse(JSON.stringify(empty.clinic.createdAt)), { seconds: 1, nanoseconds: 0 });
      assert.equal(empty.clinic.primaryAdminUid, undefined);
      const saved = await save(loaded);
      assert.equal(saved.revision, 1);
      const first = (await db.doc("clinicOperations/a").get()).data();
      assert.deepEqual(JSON.parse(JSON.stringify(saved.updatedAt)), { seconds: first.updatedAt.seconds, nanoseconds: first.updatedAt.nanoseconds });
      assert.ok(first.createdAt instanceof Timestamp); assert.ok(first.updatedAt instanceof Timestamp);
      assert.equal(first.createdBy, "platform"); assert.equal(first.updatedBy, "platform");
      await db.doc("clinicOperations/a").update({ futureExtension: { keep: true } });
      await save(loaded, 1, { ...data(), contactName: "Changed" });
      const blank = Object.fromEntries(Object.keys(data()).map(key => [key, ""]));
      await save(loaded, 2, blank);
      const result = await read(loaded);
      assert.equal(result.revision, 3);
      assert.deepEqual(JSON.parse(JSON.stringify(result.operations)), blank);
      const stored = (await db.doc("clinicOperations/a").get()).data();
      assert.deepEqual(JSON.parse(JSON.stringify(result.updatedAt)), { seconds: stored.updatedAt.seconds, nanoseconds: stored.updatedAt.nanoseconds });
      assert.deepEqual(stored.createdAt, first.createdAt);
      assert.equal(stored.createdBy, first.createdBy);
      assert.deepEqual(stored.futureExtension, { keep: true });
      assert.deepEqual((await db.doc("clinics/a").get()).data(), original);
      const logs = await auditDocs(); assert.equal(logs.length, 3);
      for (const value of Object.values(data())) assert.ok(!JSON.stringify(logs).includes(value));
      assert.ok(logs.every(log => log.action === "clinic.operations.update" && log.createdAt instanceof Timestamp));
    });
    it("save timestamp belongs to the committed revision even after another writer advances the document", async () => {
      const result = await save(load({ advanceAfterCommit: true }));
      const audit = (await auditDocs())[0];
      assert.equal(result.revision, 1);
      assert.deepEqual(JSON.parse(JSON.stringify(result.updatedAt)), { seconds: audit.createdAt.seconds, nanoseconds: audit.createdAt.nanoseconds });
      assert.notEqual(result.updatedAt.seconds, 2000000000);
      const latest = await read(load());
      assert.equal(latest.revision, 2);
      assert.equal(latest.updatedAt.seconds, 2000000000);
    });
    it("metadata read failure reports uncertainty without undoing or repeating the committed write", async () => {
      await assert.rejects(save(load({ timestampReadFailure: true })), { code: "internal" });
      assert.equal((await db.doc("clinicOperations/a").get()).data().revision, 1);
      assert.equal((await auditDocs()).length, 1);
      const latest = await read(load());
      assert.equal(latest.revision, 1);
      assert.equal(typeof latest.updatedAt.seconds, "number");
    });
    it("missing clinic rejects both calls; inactive clinic remains unchanged", async () => {
      const loaded = load();
      await assert.rejects(read(loaded, "missing"), { code: "not-found" });
      await assert.rejects(save(loaded, 0, data(), "missing"), { code: "not-found" });
      await db.doc("clinics/a").update({ status: "inactive" });
      const previous = (await db.doc("clinics/a").get()).data();
      await save(loaded);
      assert.equal((await read(loaded)).clinic.status, "inactive");
      assert.deepEqual((await db.doc("clinics/a").get()).data(), previous);
    });
    it("stale revision and simultaneous first saves never overwrite", async () => {
      const results = await Promise.allSettled([save(load()), save(load())]);
      assert.equal(results.filter(r => r.status === "fulfilled").length, 1);
      const failure = results.find(r => r.status === "rejected").reason;
      assert.equal(failure.code, "failed-precondition");
      assert.equal(failure.details.reason, "revision-conflict");
      const previous = (await db.doc("clinicOperations/a").get()).data();
      await assert.rejects(save(load()), { code: "failed-precondition" });
      assert.deepEqual((await db.doc("clinicOperations/a").get()).data(), previous);
      assert.equal((await auditDocs()).length, 1);
    });
    it("SDK transaction retry uses one audit and one revision", async () => {
      const loaded = load({ retry: true });
      assert.equal((await save(loaded)).revision, 1);
      assert.equal(loaded.attempts(), 2); assert.equal(loaded.random.requests, 1);
      assert.equal((await auditDocs()).length, 1);
    });
    it("revision is rechecked on the real SDK retry path", async () => {
      const loaded = load({ conflictOnRetry: true });
      await assert.rejects(save(loaded), error => error.details?.reason === "revision-conflict");
      assert.equal(loaded.attempts(), 2);
      assert.equal((await db.doc("clinicOperations/a").get()).data().revision, 1);
      assert.equal((await auditDocs()).length, 0);
    });
    for (const existing of [false, true]) {
      it(`audit create precondition failure rolls back ${existing ? "update" : "creation"}`, async () => {
        if (existing) await save(load());
        const previous = (await db.doc("clinicOperations/a").get()).data();
        const clinic = (await db.doc("clinics/a").get()).data();
        await assert.rejects(save(load({ collision: true }), existing ? 1 : 0,
          { ...data(), contactName: "must not persist" }), { code: "internal" });
        assert.deepEqual((await db.doc("clinicOperations/a").get()).data(), previous);
        assert.deepEqual((await db.doc("clinics/a").get()).data(), clinic);
        assert.equal((await auditDocs()).filter(log => log.result === "success").length, existing ? 1 : 0);
      });
    }
    for (const mode of ["revoke", "revokeOnRetry"]) {
      it(`${mode}: authorization rechecked inside transaction`, async () => {
        await assert.rejects(save(load({ [mode]: true })), { code: "permission-denied" });
        assert.equal((await db.doc("clinicOperations/a").get()).exists, false);
        assert.equal((await auditDocs()).length, 0);
      });
    }
    it("every client identity is denied direct get/list/create/update/delete", async () => {
      await save(load());
      for (const uid of ["platform", "staff", "ordinary", null]) {
        const client = uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
        const ref = doc(client, "clinicOperations/a");
        for (const action of [
          () => getDoc(ref), () => getDocs(collection(client, "clinicOperations")),
          () => setDoc(doc(client, "clinicOperations/new"), data()),
          () => setDoc(ref, data()), () => updateDoc(ref, { contactName: "denied" }), () => deleteDoc(ref),
        ]) await assert.rejects(action(), { code: "permission-denied" });
      }
      assert.equal((await db.doc("clinicOperations/a").get()).data().revision, 1);
    });
  });
}
