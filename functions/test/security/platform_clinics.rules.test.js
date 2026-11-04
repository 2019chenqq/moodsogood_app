"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const { initializeTestEnvironment, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
  serverTimestamp, writeBatch,
} = require("firebase/firestore");

const settings = {
  name: "Updated clinic",
  phone: "02-12345678",
  defaultDepartment: "General",
  address: "Test address",
  sessionSettings: {
    morning: { enabled: true, start: "09:00", end: "12:00" },
    afternoon: { enabled: false, start: "", end: "" },
    evening: { enabled: false, start: "", end: "" },
  },
  updatedAt: () => serverTimestamp(),
};
const valueOf = value => typeof value === "function" ? value() : value;
const denied = promise => assert.rejects(promise, { code: "permission-denied" });

// Both deployed rule sources receive exactly the same client permission matrix.
for (const [index, rulesFile] of ["firestore.rules", "firestore.demo.rules"].entries()) {
  describe(rulesFile, { concurrency: false }, () => {
    let env;
    const dbFor = uid => uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
    const clinic = (uid, id = "a") => doc(dbFor(uid), "clinics", id);

    before(async () => {
      // Fail explicitly rather than silently skipping this security gate.
      assert.match(process.env.FIRESTORE_EMULATOR_HOST || "", /^(127\.0\.0\.1|localhost):\d+$/,
        "A local Firestore Emulator is required; run npm run test:rules:platform");
      env = await initializeTestEnvironment({
        projectId: `demo-innera-platform-rules-${index}`,
        firestore: { rules: fs.readFileSync(path.resolve(__dirname, "../../..", rulesFile), "utf8") },
      });
      await env.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        const batch = writeBatch(db);
        const fixtures = {
          "clinics/a": { name: "Clinic A", status: "active", primaryAdminUid: "admin", initialAdminInviteId: "invite-a" },
          "clinics/b": { name: "Clinic B", status: "active" },
          "clinics/inactive": { name: "Inactive", status: "inactive" },
          "platformAdmins/platform": { role: "platform_admin", status: "active" },
          "platformAdmins/dual": { role: "platform_admin", status: "active" },
          "platformAdmins/dualAlias": { role: "platform_admin", status: "active" },
          "platformAdmins/inactivePlatform": { role: "platform_admin", status: "inactive" },
        };
        for (const [uid, role] of Object.entries({ admin: "admin", alias: "clinic_admin", dual: "admin", dualAlias: "clinic_admin", doctor: "doctor", nurse: "nurse", staff: "staff" })) {
          fixtures[`clinicStaff/${uid}`] = { clinicId: "a", role, active: true, status: "active" };
        }
        fixtures["clinicStaff/disabledFlag"] = { clinicId: "a", role: "admin", active: false, status: "active" };
        fixtures["clinicStaff/disabledStatus"] = { clinicId: "a", role: "admin", active: true, status: "inactive" };
        fixtures["clinicStaff/inactiveClinic"] = { clinicId: "inactive", role: "admin", active: true, status: "active" };
        for (const [name, data] of Object.entries(fixtures)) batch.set(doc(db, name), data);
        await batch.commit();
      });
    });
    after(async () => { if (env) await env.cleanup(); });

    it("platform reads individual clinics and the complete clinic list", async () => {
      await assertSucceeds(getDoc(clinic("platform")));
      await assertSucceeds(getDoc(clinic("platform", "inactive")));
      const result = await assertSucceeds(getDocs(collection(dbFor("platform"), "clinics")));
      assert.equal(result.size, 3);
    });
    it("platform cannot update settings, sensitive fields, or merge/replace a document", async () => {
      for (const [field, value] of Object.entries({ ...settings, status: "inactive", primaryAdminUid: "attacker", initialAdminInviteId: "other", arbitrary: true })) {
        await denied(updateDoc(clinic("platform"), { [field]: valueOf(value) }));
      }
      await denied(setDoc(clinic("platform"), { name: "merge" }, { merge: true }));
      await denied(setDoc(clinic("platform"), { name: "replacement", status: "active" }));
    });
    it("platform cannot create or delete clinics", async () => {
      await denied(setDoc(clinic("platform", "new"), { status: "active" }));
      await denied(deleteDoc(clinic("platform")));
    });
    it("dual platform/clinic admin identities cannot update even permitted settings", async () => {
      for (const uid of ["dual", "dualAlias"]) await denied(updateDoc(clinic(uid), { name: "forbidden" }));
    });
    for (const [field, value] of Object.entries(settings)) {
      it(`both clinic admin aliases can update ${field}`, async () => {
        for (const uid of ["admin", "alias"]) await assertSucceeds(updateDoc(clinic(uid), { [field]: valueOf(value) }));
      });
    }
    it("accepts the complete saveClinicSettings payload", async () => {
      const payload = Object.fromEntries(Object.entries(settings).map(([field, value]) => [field, valueOf(value)]));
      for (const uid of ["admin", "alias"]) await assertSucceeds(updateDoc(clinic(uid), payload));
    });
    it("clinic admins cannot change status, ownership, invitations, or arbitrary fields", async () => {
      for (const uid of ["admin", "alias"]) {
        for (const [field, value] of Object.entries({ status: "inactive", primaryAdminUid: "other", initialAdminInviteId: "other", inviteToken: "forbidden", allowPatientInvite: false, clinicCode: "OTHER" })) {
          await denied(updateDoc(clinic(uid), { [field]: value }));
        }
      }
    });
    it("clinic admins cannot update another clinic", async () => {
      for (const uid of ["admin", "alias"]) await denied(updateDoc(clinic(uid, "b"), { name: "forbidden" }));
    });
    it("disabled employees and inactive clinics cannot update settings", async () => {
      for (const uid of ["disabledFlag", "disabledStatus"]) await denied(updateDoc(clinic(uid), { name: "forbidden" }));
      await denied(updateDoc(clinic("inactiveClinic", "inactive"), { name: "forbidden" }));
    });
    it("doctor, nurse, staff, ordinary, inactive platform and unauthenticated clients cannot update", async () => {
      for (const uid of ["doctor", "nurse", "staff", "ordinary", "inactivePlatform", null]) await denied(updateDoc(clinic(uid), { name: "forbidden" }));
    });
    it("mixed authorized/unauthorized fields reject the entire update", async () => {
      const beforeData = (await getDoc(clinic("admin"))).data();
      await denied(updateDoc(clinic("admin"), { name: "must not persist", status: "inactive" }));
      assert.deepEqual((await getDoc(clinic("admin"))).data(), beforeData);
    });
    it("a batch containing an unauthorized update commits neither write", async () => {
      const db = dbFor("admin");
      const beforeData = (await getDoc(doc(db, "clinics/a"))).data();
      const batch = writeBatch(db);
      batch.update(doc(db, "clinics/a"), { name: "must not persist" });
      batch.update(doc(db, "clinics/b"), { name: "forbidden" });
      await denied(batch.commit());
      assert.deepEqual((await getDoc(doc(db, "clinics/a"))).data(), beforeData);
    });
    it("preserves same-clinic staff reads without granting ordinary or cross-clinic reads", async () => {
      for (const uid of ["admin", "alias", "doctor", "nurse", "staff"]) {
        await assertSucceeds(getDoc(clinic(uid)));
        await denied(getDoc(clinic(uid, "b")));
      }
      for (const uid of ["ordinary", "inactivePlatform", "disabledFlag", "disabledStatus", null]) await denied(getDoc(clinic(uid)));
      await denied(getDoc(clinic("inactiveClinic", "inactive")));
    });
    it("does not grant create/delete to any other client role", async () => {
      for (const uid of ["admin", "alias", "dual", "doctor", "nurse", "staff", "ordinary", null]) {
        await denied(setDoc(clinic(uid, "new"), { status: "active" }));
        await denied(deleteDoc(clinic(uid)));
      }
    });
  });
}
