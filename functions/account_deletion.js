"use strict";

const RECENT_SIGN_IN_SECONDS = 10 * 60;

function hasRecentSignIn(auth, nowSeconds = Math.floor(Date.now() / 1000)) {
  const authTime = Number(auth?.token?.auth_time);
  return Number.isFinite(authTime) && authTime > 0 &&
    nowSeconds - authTime >= 0 &&
    nowSeconds - authTime <= RECENT_SIGN_IN_SECONDS;
}

async function deleteQueryDocuments(db, collectionName, field, uid) {
  const snapshot = await db.collection(collectionName).where(field, "==", uid).get();
  for (const document of snapshot.docs) {
    await db.recursiveDelete(document.ref);
  }
  return snapshot.size;
}

async function deleteUserAccountData({ db, auth, bucket, uid }) {
  // Recursive deletion removes every current and future subcollection below the
  // user root, avoiding a fragile client-maintained collection allowlist.
  await db.recursiveDelete(db.collection("users").doc(uid));

  for (const collectionName of [
    "server_entitlements",
    "ai_rate_limits",
    "innera_free_quota",
  ]) {
    await db.recursiveDelete(db.collection(collectionName).doc(uid));
  }

  for (const [collectionName, field] of [
    ["followUpSummaryShares", "ownerUid"],
    ["follow_up_summary_shares", "ownerUid"],
    ["ai_usage_events", "uid"],
    ["feedback", "userId"],
    ["drug_dictionary", "userId"],
  ]) {
    await deleteQueryDocuments(db, collectionName, field, uid);
  }

  for (const prefix of [
    `users/${uid}/`,
    `user_photos/${uid}/`,
    `ai_chat_temp/${uid}/`,
  ]) {
    await bucket.deleteFiles({ prefix, force: true });
  }
  await bucket.file(`user_avatars/${uid}.jpg`).delete({ ignoreNotFound: true });

  // Authentication is deleted last so a partial failure remains retryable by
  // the same signed-in user.
  await auth.deleteUser(uid);
}

module.exports = {
  RECENT_SIGN_IN_SECONDS,
  deleteUserAccountData,
  hasRecentSignIn,
};
