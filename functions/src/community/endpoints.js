const { onCall, HttpsError } = require("firebase-functions/v2/https");

exports.createCommunityPost = onCall(
  { enforceAppCheck: true },
  async () => {
    // Keep the deployed endpoint fail-closed until the community feature has
    // server-side roles, moderation and abuse controls.
    throw new HttpsError(
      "failed-precondition",
      "社群功能尚未開放。",
      { reason: "community_disabled" },
    );
  },
);
