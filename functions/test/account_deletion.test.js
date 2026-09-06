"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  RECENT_SIGN_IN_SECONDS,
  deleteUserAccountData,
  hasRecentSignIn,
} = require("../account_deletion");

test("account deletion requires a recent sign-in", () => {
  assert.equal(hasRecentSignIn(null, 1000), false);
  assert.equal(hasRecentSignIn({ token: { auth_time: 1000 } }, 1000), true);
  assert.equal(hasRecentSignIn({ token: { auth_time: 1000 } }, 1000 + RECENT_SIGN_IN_SECONDS), true);
  assert.equal(hasRecentSignIn({ token: { auth_time: 1000 } }, 1001 + RECENT_SIGN_IN_SECONDS), false);
});

test("account deletion removes data before deleting Authentication", async () => {
  const calls = [];
  const ref = (path) => ({
    path,
    doc: (id) => ref(`${path}/${id}`),
    where: (field, op, value) => ({
      get: async () => ({
        size: 1,
        docs: [{ ref: ref(`${path}/matched-${field}-${op}-${value}`) }],
      }),
    }),
  });
  const db = {
    collection: (name) => ref(name),
    recursiveDelete: async (document) => calls.push(`firestore:${document.path}`),
  };
  const bucket = {
    deleteFiles: async ({ prefix }) => calls.push(`storage:${prefix}`),
    file: (path) => ({
      delete: async () => calls.push(`storage:${path}`),
    }),
  };
  const auth = {
    deleteUser: async (uid) => calls.push(`auth:${uid}`),
  };

  await deleteUserAccountData({ db, auth, bucket, uid: "alice" });

  assert.ok(calls.includes("firestore:users/alice"));
  assert.ok(calls.includes("firestore:innera_free_quota/alice"));
  assert.ok(calls.includes("storage:users/alice/"));
  assert.ok(calls.includes("storage:user_avatars/alice.jpg"));
  assert.equal(calls.at(-1), "auth:alice");
});
