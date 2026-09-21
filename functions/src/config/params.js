const { defineSecret, defineString } = require("firebase-functions/params");

const openAiApiKey = defineSecret("OPENAI_API_KEY");

const lastFmApiKey = defineSecret("LASTFM_API_KEY");

const spotifyClientId = defineSecret("SPOTIFY_CLIENT_ID");

const spotifyClientSecret = defineSecret("SPOTIFY_CLIENT_SECRET");

const revenueCatSecretApiKey = defineSecret("REVENUECAT_SECRET_API_KEY");

const aiTestProUids = defineString("AI_TEST_PRO_UIDS", { default: "" });

const aiTestProEmails = defineString("AI_TEST_PRO_EMAILS", { default: "" });

const DEFAULT_AI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";

module.exports = {
  DEFAULT_AI_MODEL,
  openAiApiKey,
  revenueCatSecretApiKey,
  aiTestProUids,
  aiTestProEmails,
  lastFmApiKey,
  spotifyClientId,
  spotifyClientSecret,
};
