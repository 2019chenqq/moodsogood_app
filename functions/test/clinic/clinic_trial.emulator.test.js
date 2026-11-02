"use strict";
const { describe, it, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { doc, collection, getDocFromServer, getDocsFromServer, setDoc, updateDoc, deleteDoc } = require("firebase/firestore");
const { loadPlatform, seed } = require("./platform_test_support.cjs");
const plain = value => JSON.parse(JSON.stringify(value));
const operations = { contactName: "Synthetic contact", contactTitle: "Office", contactEmail: "test@example.test",
  contactPhone: "000", clinicType: "hospital", cooperationNotes: "Synthetic only" };
const request = (data, uid = "platform") => ({ auth: uid ? { uid } : null, data });
const wire = stamp => ({ seconds: stamp.seconds, nanoseconds: stamp.nanoseconds });

for (const [index, source] of ["functions", "functions_demo"].entries()) {
  describe(`${source}: F2-D real Firestore transactions and Rules`, { concurrency: false }, () => {
    const projectId = `demo-innera-f2d-${index}`;
    let app, db, env, host, now;
    before(async () => {
      host = process.env.FIRESTORE_EMULATOR_HOST || "";
      assert.match(host, /^127\.0\.0\.1:\d+$/, "Local Firestore Emulator is mandatory; no cloud fallback");
      app = initializeApp({ projectId }, projectId);
      db = getFirestore(app);
      env = await initializeTestEnvironment({ projectId, firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, "../../..", index ? "firestore.demo.rules" : "firestore.rules"), "utf8")
      } });
    });
    beforeEach(async () => {
      const response = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
      assert.equal(response.ok, true);
      now = Date.parse("2026-10-27T04:00:00Z");
      const fixtures = seed();
      Object.assign(fixtures, {
        "platformAdmins/inactive": { role: "platform_admin", status: "inactive" },
        "clinics/b": { status: "active", active: true },
        "clinicStaff/doctor": { clinicId: "a", role: "doctor", status: "active", active: true },
        "clinicStaff/outsider": { clinicId: "b", role: "doctor", status: "active", active: true },
        "clinicStaff/disabled": { clinicId: "a", role: "doctor", status: "inactive", active: false },
        "clinicStaff/nurse": { clinicId: "a", role: "nurse", status: "active", active: true },
        "inneraPatients/p": { clinicId: "a", userId: "patient" },
        "users/patient/sleepRecords/private": { durationMinutes: 420 },
        "clinicalShares/patient/clinics/a": { active: true, sleepSharingEnabled: true,
          healthEventSharingEnabled: true, dailyCheckInSharingEnabled: true, medicationSharingEnabled: true },
        "clinicalShares/unshared/clinics/a": { active: false, sleepSharingEnabled: true },
        "clinicalShares/unshared/clinics/a/sleepRecords/r": { durationMinutes: 420 },
      });
      for (const kind of ["sleepRecords", "healthEvents", "dailyCheckIns", "medications", "aiSummaries"]) {
        fixtures[`clinicalShares/patient/clinics/a/${kind}/r`] = { synthetic: true, value: 1 };
      }
      const batch = db.batch();
      for (const [key, value] of Object.entries(fixtures)) batch.set(db.doc(key), value);
      await batch.commit();
    });
    after(async () => { if (env) await env.cleanup(); if (db) await db.terminate(); if (app) await deleteApp(app); });
    function load(mode = {}) {
      let auditRef, attempts = 0;
      class Clock extends Date { static now() { return now; } }
      const transport = {
        collection(name) { return { doc(id) {
          const ref = id === undefined ? db.collection(name).doc() : db.collection(name).doc(id);
          if (name === "auditLogs") {
            auditRef = ref;
            if (mode.timestampReadFailure) ref.get = async () => { throw new Error("Injected post-commit failure"); };
          }
          return ref;
        } }; },
        async runTransaction(callback) {
          if (mode.collision) await auditRef.create({ collisionFixture: true });
          if (mode.revoke) await db.doc("platformAdmins/platform").update({ status: "inactive" });
          return db.runTransaction(async tx => {
            attempts++;
            if (mode.revokeOnRetry && attempts === 2) await db.doc("platformAdmins/platform").update({ status: "inactive" });
            const result = await callback(tx);
            if ((mode.retry || mode.revokeOnRetry) && attempts === 1) {
              const error = new Error("Injected SDK ABORTED"); error.code = 10; throw error;
            }
            return result;
          }, { maxAttempts: 3 });
        }
      };
      return { ...loadPlatform(source, transport, { Date: Clock }), attempts: () => attempts };
    }
    const read = (loaded = load(), uid = "platform") => loaded.functions.getClinicDetails.run(request({ clinicId: "a" }, uid));
    const start = (loaded = load(), revision = 0, startDate = "2026-10-28", uid = "platform") =>
      loaded.functions.updateClinicTrial.run(request({ clinicId: "a", expectedRevision: revision, action: "setStart", startDate }, uid));
    const close = (action = "convert", revision = 1, loaded = load()) =>
      loaded.functions.updateClinicTrial.run(request({ clinicId: "a", expectedRevision: revision, action, reason: " Synthetic decision " }));
    const f1 = (revision, loaded = load()) => loaded.functions.updateClinicOperations.run(request({ clinicId: "a", expectedRevision: revision, operations }));
    const stored = async () => (await db.doc("clinicOperations/a").get()).data();
    const audits = async () => (await db.collection("auditLogs").get()).docs.map(d => d.data());
    const client = uid => uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
    const denied = promise => assert.rejects(promise, { code: "permission-denied" });

    it("missing trial read has no writes; timestamps and exact F2-B wire contract match committed data", async () => {
      const empty = await read();
      assert.equal(empty.trial, null); assert.equal(empty.trialComputed.status, "not_configured");
      assert.equal(await stored(), undefined); assert.equal((await audits()).length, 0);
      const result = await start(); const data = await stored(); const log = (await audits())[0];
      assert.equal(data.schemaVersion, 1); assert.equal(data.revision, 1);
      for (const stamp of [data.createdAt, data.updatedAt, data.trial.updatedAt]) {
        assert.ok(stamp instanceof Timestamp); assert.ok(stamp.isEqual(log.createdAt));
      }
      assert.deepEqual(plain(result.updatedAt), wire(data.updatedAt));
      assert.deepEqual(plain(result.trial.updatedAt), wire(data.trial.updatedAt));
      assert.deepEqual(plain(result.evaluatedAt), wire(Timestamp.fromMillis(now)));
      assert.deepEqual(plain((await read()).trial), plain(result.trial));
      assert.equal(Object.values((await read()).operations).filter(v => v === "").length, 6);
      const closed = await close(); const final = await stored();
      assert.ok(final.trial.resolvedAt.isEqual(final.updatedAt));
      assert.deepEqual(plain(closed.trial.resolvedAt), wire(final.trial.resolvedAt));
      assert.equal(final.trial.resolutionReason, "Synthetic decision");
    });
    it("real simultaneous F2 writes at revision zero commit exactly once; stale revision cannot overwrite", async () => {
      const outcomes = await Promise.allSettled([start(load(), 0, "2026-10-28"), start(load(), 0, "2026-10-29")]);
      assert.equal(outcomes.filter(r => r.status === "fulfilled").length, 1);
      assert.equal(outcomes.find(r => r.status === "rejected").reason.details.reason, "revision-conflict");
      const previous = await stored();
      await assert.rejects(start(), error => error.details.reason === "revision-conflict");
      assert.deepEqual(await stored(), previous); assert.equal((await audits()).length, 1);
    });
    it("real simultaneous F1/F2 writes serialize and both update directions preserve the other fields", async () => {
      await start();
      const outcomes = await Promise.allSettled([f1(1), close("convert", 1)]);
      assert.equal(outcomes.filter(r => r.status === "fulfilled").length, 1);
      assert.equal(outcomes.find(r => r.status === "rejected").reason.details.reason, "revision-conflict");
      assert.equal((await stored()).revision, 2); assert.equal((await audits()).length, 2);
      const trialBefore = (await stored()).trial;
      await f1(2); assert.deepEqual((await stored()).trial, trialBefore);
      if (!trialBefore.resolution) await close("terminate", 3);
      const final = await stored();
      for (const [key, value] of Object.entries(operations)) assert.equal(final[key], value);
      assert.equal((await read()).operations.contactName, operations.contactName);
    });
    it("nonempty F1 fields survive both F2 setup and closure; F1 edits preserve stored trial exactly", async () => {
      await f1(0); await start(load(), 1);
      for (const [key, value] of Object.entries(operations)) assert.equal((await stored())[key], value);
      const previousTrial = (await stored()).trial;
      await f1(2); assert.deepEqual((await stored()).trial, previousTrial);
      await close("terminate", 3);
      for (const [key, value] of Object.entries(operations)) assert.equal((await stored())[key], value);
      assert.equal((await stored()).revision, 4);
    });
    for (const existing of [false, true]) it(`real audit create-precondition collision rolls back ${existing ? "closure" : "creation"}`, async () => {
      if (existing) await start();
      const previous = await stored(), clinic = (await db.doc("clinics/a").get()).data();
      await assert.rejects(existing ? close("terminate", 1, load({ collision: true })) : start(load({ collision: true })), { code: "internal" });
      assert.deepEqual(await stored(), previous);
      assert.deepEqual((await db.doc("clinics/a").get()).data(), clinic);
      assert.equal((await audits()).filter(log => log.result === "success").length, existing ? 1 : 0);
    });
    it("duplicate closure and terminal transitions do not change revision or audit", async () => {
      await start(); await close();
      const previous = await stored();
      for (const action of ["convert", "terminate"]) await assert.rejects(close(action, 2), error => error.details.reason === "trial-terminal");
      await assert.rejects(start(load(), 2, "2026-11-01"), error => error.details.reason === "trial-terminal");
      assert.deepEqual(await stored(), previous); assert.equal((await audits()).length, 2);
    });
    it("unconfigured closure, past start and started rescheduling leave storage/audit unchanged", async () => {
      await assert.rejects(close("convert", 0), error => error.details.reason === "trial-not-configured");
      await assert.rejects(start(load(), 0, "2026-10-26"), error => error.details.reason === "trial-start-in-past");
      assert.equal(await stored(), undefined); assert.equal((await audits()).length, 0);
      await start(load(), 0, "2026-10-27"); const previous = await stored();
      await assert.rejects(start(load(), 1, "2026-10-29"), error => error.details.reason === "trial-already-started");
      assert.deepEqual(await stored(), previous); assert.equal((await audits()).length, 1);
    });
    it("actual read/write handlers deny absent, wrong-role and inactive identities", async () => {
      for (const uid of [null, "ordinary", "doctor", "inactive"]) {
        const code = uid ? "permission-denied" : "unauthenticated";
        await assert.rejects(read(load(), uid), { code });
        await assert.rejects(start(load(), 0, "2026-10-28", uid), { code });
      }
      assert.equal(await stored(), undefined); assert.equal((await audits()).length, 0);
    });
    for (const mode of ["revoke", "revokeOnRetry"]) it(`${mode}: transaction authorization rejects revoked admin with no writes`, async () => {
      const loaded = load({ [mode]: true });
      await assert.rejects(start(loaded), { code: "permission-denied" });
      assert.equal(loaded.attempts(), mode === "revoke" ? 1 : 2);
      assert.equal(await stored(), undefined); assert.equal((await audits()).length, 0);
    });
    it("real SDK retry commits once; post-commit metadata failure remains recoverable and does not resend", async () => {
      const loaded = load({ retry: true }); await start(loaded);
      assert.equal(loaded.attempts(), 2); assert.equal((await audits()).length, 1);
      await assert.rejects(close("terminate", 1, load({ timestampReadFailure: true })), { code: "internal" });
      assert.equal((await stored()).revision, 2); assert.equal((await audits()).length, 2);
      assert.equal((await read()).trialComputed.status, "terminated");
    });
    it("Rules deny direct get/list/create/update/delete of operations and audit for every tested identity", async () => {
      await start(); const log = (await db.collection("auditLogs").get()).docs[0];
      for (const uid of [null, "ordinary", "platform", "inactive", "doctor", "nurse", "patient"]) {
        const dbClient = client(uid);
        for (const [name, id] of [["clinicOperations", "a"], ["auditLogs", log.id]]) {
          const ref = doc(dbClient, name, id);
          for (const operation of [() => getDocFromServer(ref), () => getDocsFromServer(collection(dbClient, name)),
            () => setDoc(doc(dbClient, name, "new"), { value: 1 }), () => setDoc(ref, { value: 1 }),
            () => updateDoc(ref, { value: 1 }), () => deleteDoc(ref)]) await denied(operation());
        }
      }
      assert.equal((await stored()).revision, 1); assert.equal((await audits()).length, 1);
    });
    for (const status of ["not_configured", "scheduled", "active", "expired", "converted", "terminated"]) {
      it(`${status}: actual medical Rules preserve allowed and denied access; clinic activation unchanged`, async () => {
        const clinic = (await db.doc("clinics/a").get()).data();
        const share = (await db.doc("clinicalShares/patient/clinics/a").get()).data();
        if (status !== "not_configured") {
          await start();
          if (status !== "scheduled") now = Date.parse("2026-10-29T04:00:00Z");
          if (status === "expired") now = Date.parse("2027-02-01T04:00:00Z");
          if (["converted", "terminated"].includes(status)) await close(status === "converted" ? "convert" : "terminate");
        }
        assert.equal((await read()).trialComputed.status, status);
        const doctor = client("doctor"), patient = client("patient");
        for (const kind of ["sleepRecords", "healthEvents", "dailyCheckIns", "medications", "aiSummaries"]) {
          const record = `clinicalShares/patient/clinics/a/${kind}/r`;
          assert.equal((await getDocFromServer(doc(doctor, record))).exists(), true);
          assert.equal((await getDocFromServer(doc(patient, record))).exists(), true);
          await denied(updateDoc(doc(doctor, record), { value: 1 }));
          if (kind === "aiSummaries") await denied(updateDoc(doc(patient, record), { value: 1 }));
          else await updateDoc(doc(patient, record), { value: 1 });
          for (const uid of [null, "platform", "outsider", "disabled", "nurse", "other-patient"]) {
            await denied(getDocFromServer(doc(client(uid), record)));
          }
        }
        await denied(getDocFromServer(doc(doctor, "clinicalShares/unshared/clinics/a/sleepRecords/r")));
        assert.equal((await getDocFromServer(doc(patient, "users/patient/sleepRecords/private"))).exists(), true);
        await updateDoc(doc(patient, "users/patient/sleepRecords/private"), { durationMinutes: 420 });
        await denied(getDocFromServer(doc(doctor, "users/patient/sleepRecords/private")));
        assert.deepEqual((await db.doc("clinics/a").get()).data(), clinic);
        assert.deepEqual((await db.doc("clinicalShares/patient/clinics/a").get()).data(), share);
        if (status === "not_configured") assert.equal(await stored(), undefined);
      });
    }
  });
}
