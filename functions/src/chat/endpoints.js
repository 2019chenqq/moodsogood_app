const { onCall } = require("firebase-functions/v2/https");
const { openAiApiKey, revenueCatSecretApiKey } = require("../config/params");
const { withFreeQuota } = require("../ai/innera_free_quota");
const { db } = require("../config/firebase");
const { requireAiProAccess } = require("../ai/access");
const { generateInneraAiChatResponse } = require("./handler");

exports.generateInneraAiChat = onCall(
  { secrets: [openAiApiKey, revenueCatSecretApiKey], enforceAppCheck: true },
  (request) => withFreeQuota({
    db, request, verifyPro: requireAiProAccess, run: generateInneraAiChatResponse,
  }),
);
