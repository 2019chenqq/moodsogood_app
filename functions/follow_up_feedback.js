"use strict";

const { createHash } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");

const COLLECTION = "followUpSummaryFeedback";
const feedbackId = (uid, summaryId) => createHash("sha256")
  .update(JSON.stringify([uid, summaryId])).digest("hex");

function validateFeedback(data) {
  const allowed = ["summaryId", "shownToDoctor", "surfacedForgottenInfo",
    "hadDeeperDiscussion", "doctorRequestedAgain"];
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowed.includes(key)) ||
      typeof data.summaryId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(data.summaryId) ||
      typeof data.shownToDoctor !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid feedback fields.");
  }
  const answers = {};
  for (const key of allowed.slice(2)) {
    const codes = key === "doctorRequestedAgain"
      ? ["yes", "no", "notMentioned"] : ["yes", "no", "unsure"];
    const value = data[key] ?? null;
    if (data.shownToDoctor ? !codes.includes(value) : value !== null) {
      throw new HttpsError("invalid-argument", "Invalid feedback answer.");
    }
    answers[key] = value;
  }
  return { shownToDoctor: data.shownToDoctor, ...answers };
}

async function submitFeedback(db, request, serverTimestamp) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const answers = validateFeedback(request.data);
  const uid = request.auth.uid;
  const summaryId = request.data.summaryId;
  const summary = db.doc(`users/${uid}/followUpSummaries/${summaryId}`);
  const target = db.collection(COLLECTION).doc(feedbackId(uid, summaryId));
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(summary);
    if (!snapshot.exists) throw new HttpsError("not-found", "Summary not found.");
    // Replacement, not append: one latest response per owned summary.
    transaction.set(target, { ...answers, submittedAt: serverTimestamp() });
  });
  return { saved: true };
}

module.exports = { COLLECTION, feedbackId, validateFeedback, submitFeedback };
