"use strict";

const { randomUUID } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");

const events = {
  ...Object.fromEntries(["set_start", "reschedule", "convert", "terminate"].map(action => [
    `clinic.trial.${action}`, { type: `clinic_trial_${action}`, fields: ["revision", "startDate", "resolution", "resolutionReason"] },
  ])),
  "clinic.operations.update": { type: "clinic_operations_updated", fields: ["revision"] },
  "clinic.create": { type: "clinic_and_invitation_created", fields: ["status", "clinicCode", "inviteId"] },
  "clinic.disable": { type: "clinic_status_changed", fields: ["status"] },
  "clinic.enable": { type: "clinic_status_changed", fields: ["status"] },
  "clinic.initial_admin_invite.resend": { type: "invitation_rotated", fields: ["status", "resendCount", "expiresAt"] },
};

function stateSnapshot(state, fields) {
  if (state == null) return null;
  const result = {};
  for (const field of fields) {
    const value = state[field];
    if (field === "status") {
      result.status = ["active", "inactive", "pending"].includes(value) ? value : null;
    } else if (field === "resendCount" || field === "expiresAt" || field === "revision") {
      result[field] = Number.isSafeInteger(value) && value >= 0 ? value : null;
    } else if (value === null || typeof value === "string") {
      result[field] = value;
    }
  }
  return result;
}

// Only queue writes on the caller's transaction. Never catch an audit failure here.
function appendPlatformAudit(transaction, context, { action, targetId, targetClinicId, before, after }) {
  const event = events[action];
  if (!event || !context.actorUid || !targetId || !targetClinicId) {
    throw new Error("Invalid platform audit metadata");
  }
  transaction.create(context.auditRef, {
    action,
    eventType: event.type,
    actorUid: context.actorUid,
    actorRole: "platform_admin",
    actorClinicId: "platform",
    targetType: action === "clinic.initial_admin_invite.resend" ? "staffInvite" :
      action === "clinic.operations.update" || action.startsWith("clinic.trial.") ? "clinicOperations" : "clinic",
    targetId,
    targetClinicId,
    requestId: context.requestId,
    before: stateSnapshot(before, event.fields),
    after: stateSnapshot(after, event.fields),
    result: "success",
    source: "cloud_function",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// Per invocation, not a cross-request idempotency key. Allocate before any retry.
function platformOperation(operation, handler) {
  return async request => {
    const requestId = randomUUID();
    const context = {
      requestId,
      auditRef: db.collection("auditLogs").doc(requestId),
      actorUid: request.auth?.uid || null,
    };
    try {
      return await handler(request, context);
    } catch (error) {
      const code = error instanceof HttpsError ? error.code : "internal";
      const denied = ["unauthenticated", "permission-denied", "failed-precondition", "invalid-argument", "not-found", "already-exists"].includes(code);
      // Deliberately omit error objects/messages, request data, email and tokens.
      // This is an independent attempt event, never a successful commit event.
      console.warn("[Platform security]", {
        operation, requestId, actorUid: context.actorUid,
        result: denied ? "denied" : "failure", code,
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "無法完成院所管理操作，請確認結果後再試。");
    }
  };
}

module.exports = { appendPlatformAudit, platformOperation };
