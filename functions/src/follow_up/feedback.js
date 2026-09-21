const { onCall } = require("firebase-functions/v2/https");
const { submitFeedback, COLLECTION: feedbackCollection, feedbackId } = require("./follow_up_feedback");
const { db, admin } = require("../config/firebase");
const { onDocumentDeleted } = require("firebase-functions/v2/firestore");

exports.submitFollowUpSummaryFeedback = onCall({ enforceAppCheck: true }, (request) =>
  submitFeedback(db, request, () => admin.firestore.FieldValue.serverTimestamp()));

exports.deleteFollowUpSummaryFeedback = onDocumentDeleted(
  "users/{uid}/followUpSummaries/{summaryId}",
  async (event) => {
    await db.collection(feedbackCollection)
      .doc(feedbackId(event.params.uid, event.params.summaryId)).delete();
  },
);
