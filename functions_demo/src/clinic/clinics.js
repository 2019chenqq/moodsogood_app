const crypto = require("node:crypto");

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { db, admin } = require("../config/firebase");
const { appendPlatformAudit, platformOperation } = require("./platform_audit");
const { evaluateTrial, trialInput, transitionTrial } = require("./clinic_trial");

const CLINIC_DEFAULTS = {
  active: true,
  status: "active",
  phone: "",
  address: "",
  defaultDepartment: "",
  allowPatientInvite: true,
  sessionSettings: {
    morning: {
      enabled: false,
      start: "",
      end: ""
    },
    afternoon: {
      enabled: false,
      start: "",
      end: ""
    },
    evening: {
      enabled: false,
      start: "",
      end: ""
    }
  }
};

// F1 operations are separate from the clinic's medical settings.
const OPERATION_LIMITS = {
  contactName: 100, contactTitle: 100, contactEmail: 254,
  contactPhone: 50, clinicType: 32, cooperationNotes: 3000,
};
const CLINIC_TYPES = [
  "", "psychiatry_clinic", "other_clinic", "hospital",
  "counseling_center", "psychotherapy_center", "other",
];

function operationsInput(data, updating) {
  const keys = updating ? ["clinicId", "operations", "expectedRevision"] : ["clinicId"];
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).some(key => !keys.includes(key))) {
    throw new HttpsError("invalid-argument", "不支援的請求欄位。");
  }
  const id = data.clinicId;
  if (typeof id !== "string" || !id.trim() || id !== id.trim() ||
      id.includes("/") || id === "." || id === ".." ||
      /^__.*__$/.test(id) || Buffer.byteLength(id, "utf8") > 1500) {
    throw new HttpsError("invalid-argument", "院所識別碼格式不正確。");
  }
  if (!updating) return { clinicId: id };
  if (!Number.isSafeInteger(data.expectedRevision) || data.expectedRevision < 0 ||
      data.expectedRevision >= Number.MAX_SAFE_INTEGER) {
    throw new HttpsError("invalid-argument", "版本格式不正確。");
  }
  const input = data.operations;
  const fields = Object.keys(OPERATION_LIMITS);
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).length !== fields.length ||
      Object.keys(input).some(key => !fields.includes(key))) {
    throw new HttpsError("invalid-argument", "請提供六個營運欄位，不得加入其他欄位。");
  }
  const operations = {};
  for (const key of fields) {
    if (!Object.hasOwn(input, key) || typeof input[key] !== "string" ||
        input[key].length > OPERATION_LIMITS[key]) {
      throw new HttpsError("invalid-argument", "營運欄位型別或長度不正確。");
    }
    operations[key] = input[key].trim();
  }
  if (operations.contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(operations.contactEmail)) {
    throw new HttpsError("invalid-argument", "聯絡 Email 格式不正確。");
  }
  if (!CLINIC_TYPES.includes(operations.clinicType)) {
    throw new HttpsError("invalid-argument", "院所類型不正確。");
  }
  return { clinicId: id, operations, expectedRevision: data.expectedRevision };
}

function operationsRevision(snapshot) {
  if (!snapshot.exists) return 0;
  const data = snapshot.data();
  if (data.schemaVersion !== 1 || !Number.isSafeInteger(data.revision) ||
      data.revision < 1 || data.revision >= Number.MAX_SAFE_INTEGER) {
    throw new HttpsError("failed-precondition", "營運資料版本不支援，請確認資料。");
  }
  return data.revision;
}

function timestampResponse(value) {
  return value instanceof admin.firestore.Timestamp
    ? { seconds: value.seconds, nanoseconds: value.nanoseconds } : null;
}

function trialResponse(trial, evaluatedMillis) {
  const { expiresAtMillis, ...computed } = evaluateTrial(trial, evaluatedMillis);
  return {
    trial: trial === undefined ? null : {
      schemaVersion: trial.schemaVersion, startDate: trial.startDate,
      durationDays: trial.durationDays, timeZone: trial.timeZone, resolution: trial.resolution,
      resolvedAt: timestampResponse(trial.resolvedAt), resolvedBy: trial.resolvedBy,
      resolutionReason: trial.resolutionReason,
      updatedAt: timestampResponse(trial.updatedAt), updatedBy: trial.updatedBy,
    },
    trialComputed: { ...computed, expiresAt: expiresAtMillis === null ? null :
      timestampResponse(admin.firestore.Timestamp.fromMillis(expiresAtMillis)) },
    evaluatedAt: timestampResponse(admin.firestore.Timestamp.fromMillis(evaluatedMillis)),
  };
}

exports.getClinicDetails = onCall(
  { region: "asia-east1" },
  platformOperation("getClinicDetails", async request => {
    if (!request.auth) throw new HttpsError("unauthenticated", "請先登入平台管理端。");
    await assertPlatformAdmin(request.auth.uid);
    const { clinicId } = operationsInput(request.data, false);
    return db.runTransaction(async transaction => {
      await assertPlatformAdmin(request.auth.uid, transaction);
      const clinicSnap = await transaction.get(db.collection("clinics").doc(clinicId));
      if (!clinicSnap.exists) throw new HttpsError("not-found", "找不到院所。");
      const snapshot = await transaction.get(db.collection("clinicOperations").doc(clinicId));
      const revision = operationsRevision(snapshot);
      const source = clinicSnap.data();
      const clinic = {};
      for (const key of ["name", "clinicName", "clinicCode", "code", "status", "phone", "address", "defaultDepartment"]) {
        if (typeof source[key] === "string") clinic[key] = source[key];
      }
      // Explicit wire format; never serialize arbitrary fields or a whole document.
      clinic.createdAt = source.createdAt instanceof admin.firestore.Timestamp
        ? { seconds: source.createdAt.seconds, nanoseconds: source.createdAt.nanoseconds } : null;
      let operations = null;
      if (snapshot.exists) {
        const stored = snapshot.data();
        operations = Object.fromEntries(Object.keys(OPERATION_LIMITS).map(key => [
          key, typeof stored[key] === "string" ? stored[key] : "",
        ]));
      }
      const evaluatedMillis = Date.now();
      return { clinic, operations, revision, updatedAt: timestampResponse(snapshot.exists ? snapshot.data().updatedAt : null),
        ...trialResponse(snapshot.exists ? snapshot.data().trial : undefined, evaluatedMillis) };
    });
  })
);

exports.updateClinicOperations = onCall(
  { region: "asia-east1" },
  platformOperation("updateClinicOperations", async (request, audit) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "請先登入平台管理端。");
    const uid = request.auth.uid;
    await assertPlatformAdmin(uid);
    const { clinicId, operations, expectedRevision } = operationsInput(request.data, true);
    const result = await db.runTransaction(async transaction => {
      await assertPlatformAdmin(uid, transaction);
      const clinicSnap = await transaction.get(db.collection("clinics").doc(clinicId));
      if (!clinicSnap.exists) throw new HttpsError("not-found", "找不到院所。");
      const ref = db.collection("clinicOperations").doc(clinicId);
      const snapshot = await transaction.get(ref);
      const previousRevision = operationsRevision(snapshot);
      if (expectedRevision !== previousRevision) {
        throw new HttpsError("failed-precondition", "營運資料已更新，請重新讀取後再編輯。", {
          reason: "revision-conflict", currentRevision: previousRevision,
        });
      }
      const revision = previousRevision + 1;
      const now = admin.firestore.FieldValue.serverTimestamp();
      const data = { ...operations, schemaVersion: 1, revision, updatedAt: now, updatedBy: uid };
      if (snapshot.exists) transaction.update(ref, data);
      else transaction.create(ref, { ...data, createdAt: now, createdBy: uid });
      appendPlatformAudit(transaction, audit, {
        action: "clinic.operations.update", targetId: clinicId, targetClinicId: clinicId,
        before: snapshot.exists ? { revision: previousRevision } : null,
        after: { revision },
      });
      return { operations, revision };
    });
    // This immutable audit belongs to this request. Its serverTimestamp has the
    // same commit time as operations.updatedAt, even if another writer has
    // already advanced the operations document to the next revision.
    const committedAudit = await audit.auditRef.get();
    const updatedAt = timestampResponse(committedAudit.data()?.createdAt);
    if (!updatedAt) throw new HttpsError("internal", "已提交儲存，但無法確認修改時間，請重新讀取確認。");
    return { ...result, updatedAt };
  })
);

exports.updateClinicTrial = onCall(
  { region: "asia-east1" },
  platformOperation("updateClinicTrial", async (request, audit) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "請先登入平台管理端。");
    const uid = request.auth.uid;
    await assertPlatformAdmin(uid);
    const input = trialInput(request.data);
    const { clinicId } = operationsInput({ clinicId: input.clinicId }, false);
    const result = await db.runTransaction(async transaction => {
      await assertPlatformAdmin(uid, transaction);
      const clinic = await transaction.get(db.collection("clinics").doc(clinicId));
      if (!clinic.exists) throw new HttpsError("not-found", "找不到院所。");
      const ref = db.collection("clinicOperations").doc(clinicId);
      const snapshot = await transaction.get(ref);
      const previousRevision = operationsRevision(snapshot);
      if (input.expectedRevision !== previousRevision) {
        throw new HttpsError("failed-precondition", "營運資料已更新，請重新讀取後再編輯。", {
          reason: "revision-conflict", currentRevision: previousRevision,
        });
      }
      // One clock sample per transaction attempt; retries revalidate against their own current time.
      const evaluatedMillis = Date.now();
      const previous = snapshot.exists ? snapshot.data().trial : undefined;
      const next = transitionTrial(previous, input, evaluatedMillis);
      const stamp = admin.firestore.FieldValue.serverTimestamp();
      const trial = { ...next, updatedAt: stamp, updatedBy: uid };
      if (input.action !== "setStart") Object.assign(trial, { resolvedAt: stamp, resolvedBy: uid });
      const revision = previousRevision + 1;
      const data = { trial, schemaVersion: 1, revision, updatedAt: stamp, updatedBy: uid };
      if (snapshot.exists) transaction.update(ref, data);
      else transaction.create(ref, {
        ...Object.fromEntries(Object.keys(OPERATION_LIMITS).map(key => [key, ""])),
        ...data, createdAt: stamp, createdBy: uid,
      });
      appendPlatformAudit(transaction, audit, {
        action: `clinic.trial.${input.action === "setStart" ? previous ? "reschedule" : "set_start" : input.action}`,
        targetId: clinicId, targetClinicId: clinicId,
        before: { revision: previousRevision, startDate: previous?.startDate ?? null,
          resolution: previous?.resolution ?? null, resolutionReason: previous?.resolutionReason ?? null },
        after: { revision, startDate: trial.startDate, resolution: trial.resolution,
          resolutionReason: trial.resolutionReason },
      });
      return { trial, revision, evaluatedMillis };
    });
    // Use this invocation's immutable audit commit time, not a potentially newer operations document.
    const committed = (await audit.auditRef.get()).data()?.createdAt;
    if (!timestampResponse(committed)) throw new HttpsError("internal", "已提交儲存，請重新讀取確認。");
    result.trial.updatedAt = committed;
    if (input.action !== "setStart") result.trial.resolvedAt = committed;
    return { revision: result.revision, updatedAt: timestampResponse(committed),
      ...trialResponse(result.trial, result.evaluatedMillis) };
  })
);

async function assertPlatformAdmin(uid, transaction) {
  const ref = db
    .collection("platformAdmins")
    .doc(uid);
  const snap = transaction ? await transaction.get(ref) : await ref.get();

  if (!snap.exists) {
    throw new HttpsError(
      "permission-denied",
      "你不是平台管理員。"
    );
  }

  const data = snap.data();

  if (
    data.role !== "platform_admin" ||
    data.status !== "active"
  ) {
    throw new HttpsError(
      "permission-denied",
      "平台管理員帳號目前不可用。"
    );
  }

  return data;
}

function validateInput(data) {
  const clinicName =
    String(data.clinicName || "").trim();

  const adminName =
    String(data.adminName || "").trim();

  const email =
    String(data.email || "")
      .trim()
      .toLowerCase();

  if (!clinicName) {
    throw new HttpsError(
      "invalid-argument",
      "請輸入院所名稱。"
    );
  }

  if (!adminName) {
    throw new HttpsError(
      "invalid-argument",
      "請輸入院所管理員姓名。"
    );
  }

  if (!email) {
    throw new HttpsError(
      "invalid-argument",
      "請輸入 Email。"
    );
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError(
      "invalid-argument",
      "Email 格式不正確。"
    );
  }

  return {
    clinicName,
    adminName,
    email,
  };
}

function createInviteToken() {
  return crypto
    .randomBytes(32)
    .toString("base64url");
}


function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}


function createInviteId(clinicId, email) {
  return crypto
    .createHash("sha256")
    .update(`${clinicId}:${email}`)
    .digest("hex");
}

exports.createClinic = onCall(
  {
    region: "asia-east1"
  },
  platformOperation("createClinic", async (request, audit) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入平台管理端。"
      );
    }

    const callerUid =
      request.auth.uid;

    await assertPlatformAdmin(
      callerUid
    );

    const {
      clinicName,
      adminName,
      email
    } =
      validateInput(
        request.data || {}
      );

      const clinicRef =
        db
          .collection("clinics")
          .doc();

      const clinicId =
        clinicRef.id;

      const inviteId =
        createInviteId(
          clinicId,
          email
        );

      const inviteRef =
        db
          .collection("staffInvites")
          .doc(inviteId);

      const rawToken =
        createInviteToken();

      const tokenHash =
        hashToken(rawToken);

      const expiresAt =
        admin.firestore.Timestamp.fromMillis(
          Date.now() +
            7 * 24 * 60 * 60 * 1000
        );

      // Firestore retries only this callback, not the entire create request.
      // A separately retried HTTP request can still create another clinic.
      const clinicCode = await db.runTransaction(
        async (transaction) => {
          await assertPlatformAdmin(callerUid, transaction);
          const counterRef =
            db
              .collection("inneraCounters")
              .doc("clinic");

          const counterSnap =
            await transaction.get(
              counterRef
            );

          let current = 0;

          if (counterSnap.exists) {
            current =
              Number(
                counterSnap.data().value || 0
              );
          }

          const next =
            current + 1;

          const clinicCode =
            "CL" +
            String(next)
              .padStart(5, "0");

          transaction.set(
            counterRef,
            {
              value: next,
              updatedAt:
                admin.firestore
                  .FieldValue
                  .serverTimestamp()
            },
            {
              merge: true
            }
          );

          const now =
            admin.firestore
              .FieldValue
              .serverTimestamp();

          transaction.create(
            clinicRef,
            {
              ...CLINIC_DEFAULTS,

              name:
                clinicName,

              clinicName,

              clinicCode,

              primaryAdminUid:
                null,

              initialAdminInviteId:
                inviteId,

              createdBy:
                callerUid,

              createdAt:
                now,

              updatedAt:
                now
            }
          );

          transaction.create(
            inviteRef,
            {
              clinicId,

              email,

              emailNormalized:
                email,

              displayName:
                adminName,

              role:
                "admin",

              department:
                "",

              inviteType:
                "initial_admin",

              status:
                "pending",

              tokenHash,

              createdByUid:
                callerUid,

              createdAt:
                now,

              expiresAt,

              acceptedAt:
                null,

              acceptedByUid:
                null,

              revokedAt:
                null,

              revokedByUid:
                null,

              version:
                1
            }
          );
          appendPlatformAudit(transaction, audit, {
            action: "clinic.create", targetId: clinicId, targetClinicId: clinicId,
            before: null, after: { status: "active", clinicCode, inviteId },
          });
          return clinicCode;
        }
      );

      return {
        success:
          true,

        clinicId,

        clinicCode,

        adminEmail:
          email,

        inviteId,

        token:
          rawToken,

        expiresAt:
          expiresAt.toMillis()
      };

  })
);

exports.resendInitialAdminInvite = onCall(
  {
    region: "asia-east1"
  },
  platformOperation("resendInitialAdminInvite", async (request, audit) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入平台管理端。"
      );
    }

    const callerUid =
      request.auth.uid;

    await assertPlatformAdmin(
      callerUid
    );

    const clinicId =
      String(
        request.data?.clinicId || ""
      ).trim();

    if (!clinicId || clinicId.includes("/") || clinicId === "." || clinicId === "..") {
      throw new HttpsError(
        "invalid-argument",
        "缺少 clinicId。"
      );
    }

    const clinicRef =
      db
        .collection("clinics")
        .doc(clinicId);

    const rawToken =
      createInviteToken();

    const tokenHash =
      hashToken(rawToken);

    const expiresAt =
      admin.firestore.Timestamp.fromMillis(
        Date.now() +
          7 * 24 * 60 * 60 * 1000
      );

    const result =
      await db.runTransaction(
        async (transaction) => {
          await assertPlatformAdmin(callerUid, transaction);
          const clinicDoc =
            await transaction.get(
              clinicRef
            );

          if (!clinicDoc.exists) {
            throw new HttpsError(
              "not-found",
              "找不到院所。"
            );
          }

          const clinic =
            clinicDoc.data();

          if (clinic.status !== "active") {
            throw new HttpsError("failed-precondition", "此院所目前未啟用。");
          }

          if (clinic.primaryAdminUid) {
            throw new HttpsError(
              "failed-precondition",
              "此院所已經有主要管理員。"
            );
          }

          const inviteId =
            String(
              clinic.initialAdminInviteId || ""
            ).trim();

          if (!inviteId || inviteId.includes("/") || inviteId === "." || inviteId === "..") {
            throw new HttpsError(
              "failed-precondition",
              "院所缺少初始管理員邀請資料。"
            );
          }

          const inviteRef =
            db
              .collection("staffInvites")
              .doc(inviteId);

          const inviteDoc =
            await transaction.get(
              inviteRef
            );

          if (!inviteDoc.exists) {
            throw new HttpsError(
              "not-found",
              "找不到初始管理員邀請。"
            );
          }

          const invite =
            inviteDoc.data();

          if (
            String(invite.clinicId || "") !==
            clinicId
          ) {
            throw new HttpsError(
              "failed-precondition",
              "初始管理員邀請與院所資料不一致。"
            );
          }

          if (
            invite.inviteType !==
            "initial_admin"
          ) {
            throw new HttpsError(
              "failed-precondition",
              "邀請類型不正確。"
            );
          }

          if (
            String(invite.role || "") !==
            "admin"
          ) {
            throw new HttpsError(
              "failed-precondition",
              "初始管理員邀請角色設定不正確。"
            );
          }

          if (invite.status !== "pending") {
            throw new HttpsError(
              "failed-precondition",
              "此初始管理員邀請已無法重新寄送。"
            );
          }

          const email =
            String(
              invite.email || ""
            )
              .trim()
              .toLowerCase();

          if (
            !email ||
            !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
          ) {
            throw new HttpsError(
              "failed-precondition",
              "初始管理員 Email 資料不完整。"
            );
          }

          const previousCount = Number(invite.resendCount ?? 0);
          if (!Number.isSafeInteger(previousCount) || previousCount < 0 || previousCount >= Number.MAX_SAFE_INTEGER) {
            throw new HttpsError("failed-precondition", "邀請重寄次數資料不正確。");
          }
          const resendCount = previousCount + 1;

          transaction.update(
            inviteRef,
            {
              tokenHash,

              expiresAt,

              lastResentAt:
                admin.firestore
                  .FieldValue
                  .serverTimestamp(),

              lastResentByUid:
                callerUid,

              resendCount
            }
          );

          appendPlatformAudit(transaction, audit, {
            action: "clinic.initial_admin_invite.resend",
            targetId: inviteId, targetClinicId: clinicId,
            before: { status: "pending", resendCount: previousCount, expiresAt: invite.expiresAt?.toMillis?.() },
            after: { status: "pending", resendCount, expiresAt: expiresAt.toMillis() },
          });
          return { inviteId, email, resendCount };
        }
      );

    return {
      success:
        true,

      clinicId,

      inviteId:
        result.inviteId,

      adminEmail:
        result.email,

      token:
        rawToken,

      expiresAt:
        expiresAt.toMillis(),

      resendCount:
        result.resendCount
    };
  })
);

exports.setClinicStatus = onCall(
  {
    region: "asia-east1"
  },
  platformOperation("setClinicStatus", async (request, audit) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "請先登入平台管理端。"
      );
    }

    const callerUid =
      request.auth.uid;

    await assertPlatformAdmin(
      callerUid
    );

    const clinicId =
      String(
        request.data?.clinicId || ""
      ).trim();

    const status =
      String(
        request.data?.status || ""
      ).trim();

    if (!clinicId || clinicId.includes("/") || clinicId === "." || clinicId === "..") {
      throw new HttpsError(
        "invalid-argument",
        "缺少 clinicId。"
      );
    }

    if (
      status !== "active" &&
      status !== "inactive"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "不支援的院所狀態。"
      );
    }

    const clinicRef =
      db
        .collection("clinics")
        .doc(clinicId);

    const changed = await db.runTransaction(async transaction => {
      await assertPlatformAdmin(callerUid, transaction);
      const clinicSnap = await transaction.get(clinicRef);
      if (!clinicSnap.exists) {
        throw new HttpsError("not-found", "找不到院所。");
      }
      const previousStatus = clinicSnap.data().status;
      if (previousStatus === status) return false;
      transaction.update(clinicRef, {
        status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: callerUid,
      });
      appendPlatformAudit(transaction, audit, {
        action: status === "inactive" ? "clinic.disable" : "clinic.enable",
        targetId: clinicId, targetClinicId: clinicId,
        before: { status: previousStatus }, after: { status },
      });
      return true;
    });

    return {
      success: true,
      clinicId,
      status,
      changed
    };
  })
);

