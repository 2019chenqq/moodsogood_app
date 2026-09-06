"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc } = require("firebase/firestore");
const { ref, uploadBytes } = require("firebase/storage");

const hasEmulators = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST,
);

test("Firestore and Storage rules enforce private and server-only boundaries", {
  skip: !hasEmulators && "run with npm run test:rules",
}, async () => {
  const projectRoot = path.resolve(__dirname, "..", "..");
  const environment = await initializeTestEnvironment({
    projectId: "moodsogood-security-test",
    firestore: {
      rules: fs.readFileSync(path.join(projectRoot, "firestore.rules"), "utf8"),
    },
    storage: {
      rules: fs.readFileSync(path.join(projectRoot, "storage.rules"), "utf8"),
    },
  });

  try {
    const alice = environment.authenticatedContext("alice");
    const bob = environment.authenticatedContext("bob");
    const anonymous = environment.unauthenticatedContext();

    await assertSucceeds(setDoc(
      doc(alice.firestore(), "users/alice/private/profile"),
      { displayName: "Alice" },
    ));
    await assertFails(getDoc(
      doc(bob.firestore(), "users/alice/private/profile"),
    ));
    await assertFails(getDoc(
      doc(anonymous.firestore(), "users/alice/private/profile"),
    ));

    for (const collection of [
      "community_rooms",
      "community_room_requests",
      "server_entitlements",
      "followUpSummaryFeedback",
      "ai_usage_events",
      "ai_usage_daily",
      "ai_rate_limits",
      "ai_global_rate_limits",
      "innera_free_quota",
    ]) {
      await assertFails(setDoc(
        doc(alice.firestore(), `${collection}/attempt`),
        { active: true },
      ));
      await assertFails(getDoc(
        doc(alice.firestore(), `${collection}/attempt`),
      ));
    }

    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    await assertSucceeds(uploadBytes(
      ref(alice.storage(), "user_photos/alice/profile.jpg"),
      jpeg,
      { contentType: "image/jpeg" },
    ));
    await assertFails(uploadBytes(
      ref(bob.storage(), "user_photos/alice/profile.jpg"),
      jpeg,
      { contentType: "image/jpeg" },
    ));
  } finally {
    await environment.cleanup();
  }
});
