const { onSchedule } = require("firebase-functions/v2/scheduler");
const { admin } = require("../config/firebase");

exports.cleanupExpiredAiChatImages = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 1,
    maxInstances: 1,
  },
  async () => {
    const bucket = admin.storage().bucket();
    const [files] = await bucket.getFiles({ prefix: "ai_chat_temp/" });
    const now = Date.now();
    const fallbackCutoff = now - 60 * 60 * 1000;
    const expired = files.filter((file) => {
      const expiresAt = Date.parse(file.metadata?.metadata?.expiresAt || "");
      const createdAt = Date.parse(file.metadata?.timeCreated || "");
      const metadataExpired = !Number.isNaN(expiresAt) && expiresAt <= now;
      const ageExpired =
        !Number.isNaN(createdAt) && createdAt <= fallbackCutoff;
      return metadataExpired || ageExpired;
    });

    for (let index = 0; index < expired.length; index += 50) {
      await Promise.all(
        expired.slice(index, index + 50).map(async (file) => {
          try {
            await file.delete();
          } catch (error) {
            if (Number(error?.code) !== 404) throw error;
          }
        }),
      );
    }

    console.log("Expired AI chat image cleanup completed", {
      scannedCount: files.length,
      deletedCount: expired.length,
    });
  },
);
