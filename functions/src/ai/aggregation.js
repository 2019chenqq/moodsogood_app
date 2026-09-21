const { onSchedule } = require("firebase-functions/v2/scheduler");
const { previousTaipeiDayRange, summarizeAiUsageEvents } = require("./ai_usage_aggregation");
const { db, admin } = require("../config/firebase");

exports.aggregateDailyAiUsage = onSchedule(
  {
    schedule: "0 1 * * *",
    timeZone: "Asia/Taipei",
    region: "us-central1",
    retryCount: 3,
    maxInstances: 1,
  },
  async (event) => {
    const scheduledAt = new Date(event?.scheduleTime || Date.now());
    const referenceTime = Number.isNaN(scheduledAt.getTime())
      ? new Date()
      : scheduledAt;
    const range = previousTaipeiDayRange(referenceTime);
    const snapshot = await db
      .collection("ai_usage_events")
      .where(
        "createdAt",
        ">=",
        admin.firestore.Timestamp.fromDate(range.start),
      )
      .where(
        "createdAt",
        "<",
        admin.firestore.Timestamp.fromDate(range.end),
      )
      .select(
        "feature",
        "status",
        "quotedPoints",
        "estimatedCostMicroUsd",
        "inputTokens",
        "cachedInputTokens",
        "outputTokens",
        "totalTokens",
      )
      .get();
    const summary = summarizeAiUsageEvents(
      snapshot.docs.map((doc) => doc.data()),
      range.dateKey,
    );

    await db.collection("ai_usage_daily").doc(range.dateKey).set({
      ...summary,
      periodStart: admin.firestore.Timestamp.fromDate(range.start),
      periodEnd: admin.firestore.Timestamp.fromDate(range.end),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("Daily AI usage summary updated", {
      date: range.dateKey,
      eventCount: summary.eventCount,
      succeededCount: summary.succeededCount,
      failedCount: summary.failedCount,
      estimatedCostMicroUsd: summary.estimatedCostMicroUsd,
      quotedPoints: summary.quotedPoints,
    });
  },
);
