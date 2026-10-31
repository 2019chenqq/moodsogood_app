"use strict";
const { randomUUID, createHash } = require("node:crypto");
const { PROJECT, ShareError, requireThat, identifier, decrypt, encryptSummary } = require("./protocol");
const { TYPES, FLAGS, normalize, summarize } = require("./summary-schema");
function stale() { const error = new ShareError("failed-precondition"); error.regenerate = true; throw error; }
function sameSourceVersions(a, b) {
  return TYPES.every(type => a?.[type] && b?.[type] && ["active", "epoch", "consentVersion"].every(field => a[type][field] === b[type][field]));
}

function createSummaryService({ db, projectId, keys, now = () => Date.now(), verifySession = async () => {}, openAiProvider,
  externalPatientUid = "demo-encrypted-sleep-patient", afterProviderResponse = async () => {}, raceTestEnabled = false, raceDoctorUid = "demo-encrypted-sleep-doctor", raceClinicId = "demo-sleep-clinic", raceWait = ms => new Promise(r => setTimeout(r, ms)) }) {
  function caller(request) {
    requireThat(projectId === PROJECT, "failed-precondition");
    requireThat(request.app?.appId, "failed-precondition");
    requireThat(request.auth?.uid && request.auth.token?.firebase?.sign_in_provider !== "anonymous", "unauthenticated");
    return identifier(request.auth.uid);
  }
  const root = (uid, clinic) => `demoEncryptedShares/${uid}/clinics/${clinic}`;
  const scope = (uid, clinic) => db.doc(`${root(uid, clinic)}/scopes/aiSummary`);
  const current = (uid, clinic) => db.doc(`${root(uid, clinic)}/aiSummaries/current`);
  const sourceRef = (uid, clinic, type) => db.doc(`${root(uid, clinic)}${type === "sleepRecords" ? "" : `/scopes/${type}`}`);
  function audit(tx, action, actor, uid, result = "success") {
    const hash = v => createHash("sha256").update(`${PROJECT}:audit:${v}`).digest("hex");
    tx.set(db.doc(`demoEncryptedAudit/${randomUUID()}`), { action, result, actorRef: hash(actor), subjectRef: hash(uid), at: now(), schemaVersion: 1 });
  }
  async function relation(tx, uid, clinic) {
    const fixture = (await tx.get(db.doc(`demoEncryptedFixtures/${uid}`))).data();
    const c = (await tx.get(db.doc(`clinics/${clinic}`))).data();
    requireThat(fixture?.synthetic === true && fixture.clinicId === clinic && c?.status === "active");
    const p = (await tx.get(db.doc(`inneraPatients/${identifier(fixture.patientId)}`))).data();
    requireThat(p?.linked === true && p.firebaseUid === uid && p.clinicId === clinic);
  }
  async function state(tx, actor, uid, clinic) {
    const staff = (await tx.get(db.doc(`clinicStaff/${actor}`))).data();
    requireThat(staff?.role === "doctor" && staff.clinicId === clinic && staff.active !== false &&
      (staff.status === undefined || staff.status === "active") && (staff.active === true || staff.status === "active"));
    await relation(tx, uid, clinic);
    const consent = (await tx.get(scope(uid, clinic))).data();
    requireThat(consent?.active === true && consent.consentVersion === 1 && consent.revokedAt == null);
    const sourceVersions = {};
    for (const type of TYPES) {
      const share = (await tx.get(sourceRef(uid, clinic, type))).data();
      const active = share?.active === true && share[FLAGS[type]] === true && share.revokedAt == null && share.consentVersion === 1;
      requireThat(!active || (Number.isSafeInteger(share.epoch) && share.epoch > 0), "failed-precondition");
      sourceVersions[type] = { active, epoch: share?.epoch || 0, consentVersion: share?.consentVersion || 0 };
    }
    const external = consent.provider === "openai";
    requireThat(!external || uid === externalPatientUid, "permission-denied");
    return { epoch: consent.epoch, sourceVersions, external };
  }
  function same(actual, expected) {
    requireThat(actual.epoch === expected.epoch && actual.external === expected.external && sameSourceVersions(actual.sourceVersions, expected.sourceVersions), "aborted");
  }
  async function check(request, actor, uid, clinic, expected) {
    await verifySession(request);
    return db.runTransaction(async tx => { const actual = await state(tx, actor, uid, clinic); if (expected) same(actual, expected); return actual; });
  }
  async function rejected(actor, uid, stage) {
    // Failure of this audit remains fail-closed; no raw error or plaintext is logged.
    await db.runTransaction(async tx => {
      audit(tx, "summary.rejected", actor, uid, "rejected");
      if (stage) audit(tx, `summary.read.${stage}.rejected`, actor, uid, "rejected");
    });
  }
  async function consent(request) {
    const uid = caller(request), clinic = identifier(request.data?.clinicId);
    requireThat(request.data?.consentVersion === 1, "invalid-argument");
    const external = request.data?.provider === "openai";
    requireThat(request.data?.provider === undefined || external, "invalid-argument");
    requireThat(!external || uid === externalPatientUid, "permission-denied");
    await verifySession(request);
    return db.runTransaction(async tx => {
      await relation(tx, uid, clinic);
      const old = (await tx.get(scope(uid, clinic))).data();
      const epoch = (old?.epoch || 0) + 1;
      tx.set(scope(uid, clinic), { active: true, epoch, consentVersion: 1, revokedAt: null, ...(external ? { provider: "openai" } : {}) });
      tx.delete(current(uid, clinic)); audit(tx, "summary.consent", uid, uid);
      return { epoch };
    });
  }
  async function revoke(request) {
    const uid = caller(request), clinic = identifier(request.data?.clinicId);
    await verifySession(request);
    return db.runTransaction(async tx => {
      const fixture = (await tx.get(db.doc(`demoEncryptedFixtures/${uid}`))).data();
      requireThat(fixture?.synthetic === true && fixture.clinicId === clinic);
      const old = (await tx.get(scope(uid, clinic))).data(), epoch = (old?.epoch || 0) + 1;
      tx.set(scope(uid, clinic), { active: false, epoch, consentVersion: 1, revokedAt: now() });
      tx.delete(current(uid, clinic)); audit(tx, "summary.revoke", uid, uid);
      return { epoch };
    });
  }
  async function generate(request, race = false) {
    const actor = caller(request), uid = identifier(request.data?.uid), clinic = identifier(request.data?.clinicId);
    let sources = {}, normalized, summary, savedEnvelope, lease;
    try {
      await verifySession(request);
      if (race) { await authorizeRace(request); requireThat(uid === externalPatientUid && clinic === raceClinicId, "permission-denied"); }
      else requireThat(!(raceTestEnabled && actor === raceDoctorUid), "failed-precondition");
      // Explicit generate also reuses valid current results, preventing repeated paid calls.
      const initial = await check(request, actor, uid, clinic);
      if (race) requireThat(initial.external && TYPES.every(t => initial.sourceVersions[t].active), "failed-precondition");
      if (initial.external) {
        try { const valid = await readCurrent(request); requireThat(!race, "failed-precondition"); return { epoch: valid.epoch, available: true }; }
        catch (e) { if (e.code !== "failed-precondition" || e.regenerate !== true) throw e; }
      }
      const snapshot = await db.runTransaction(async tx => {
        const authorization = await state(tx, actor, uid, clinic), docs = [];
        for (const type of TYPES) {
          if (!authorization.sourceVersions[type].active) continue;
          const records = await tx.get(db.collection(`${root(uid, clinic)}/${type}`).limit(31));
          requireThat(records.size <= 30, "resource-exhausted");
          docs.push(...records.docs.map(d => ({ type, id: d.id, envelope: d.data() })));
        }
        requireThat(docs.length <= 30 && TYPES.some(t => authorization.sourceVersions[t].active), "failed-precondition");
        return { ...authorization, docs };
      });
      if (snapshot.external) {
        requireThat(typeof openAiProvider === "function", "failed-precondition");
        const hash = createHash("sha256").update(`${PROJECT}:generation:${uid}:${clinic}`).digest("hex");
        const ref = db.doc(`demoEncryptedGenerationLocks/${hash}`), owner = randomUUID();
        await db.runTransaction(async tx => {
          same(await state(tx, actor, uid, clinic), snapshot);
          const old = (await tx.get(ref)).data() || {}, day = Math.floor(now() / 86400000);
          const attempts = old.day === day ? old.attempts : 0;
          requireThat(!(old.expiresAt > now()) && !(old.nextAllowedAt > now()) && attempts < 2, "resource-exhausted");
          tx.set(ref, { owner, expiresAt: now() + 90000, nextAllowedAt: now() + 60000, day, attempts: attempts + 1 });
        });
        lease = { ref, owner };
        if (race) await racePhase(lease, "requesting", 90000);
      }
      for (const type of TYPES) if (snapshot.sourceVersions[type].active) sources[type] = [];
      for (const { type, id, envelope } of snapshot.docs) {
        await check(request, actor, uid, clinic, snapshot);
        requireThat(envelope.epoch === snapshot.sourceVersions[type].epoch && keys.canRead(clinic, envelope.keyVersion), "failed-precondition");
        sources[type].push(await decrypt(uid, clinic, id, envelope, (v, b) => keys.unwrap(clinic, v, b), type));
      }
      if (snapshot.external) {
        const { normalizeExternal, validateOutput, MODEL } = require("./openai-summary");
        normalized = normalizeExternal(sources); sources = null;
        await check(request, actor, uid, clinic, snapshot);
        const untrusted = await openAiProvider(normalized);
        if (race) {
          const deadline = (await racePhase(lease, "waiting_for_revoke", 120000)) + 120000;
          while (now() < deadline) {
            try { await check(request, actor, uid, clinic, snapshot); }
            catch (error) {
              if (error instanceof ShareError && ["aborted", "permission-denied", "unauthenticated", "failed-precondition"].includes(error.code)) throw new ShareError("aborted");
              throw error;
            }
            if (now() >= deadline) break;
            await raceWait(Math.min(1000, deadline - now()));
          }
          // A race run never saves a provider response, even if no revoke arrives.
          const error = new ShareError("deadline-exceeded"); error.raceExpired = true; throw error;
        }
        else await afterProviderResponse({ projectId, uid, clinicId: clinic });
        await check(request, actor, uid, clinic, snapshot);
        const output = validateOutput(untrusted, normalized);
        summary = { schemaVersion: 4, synthetic: true, model: MODEL, generatedAt: new Date(now()).toISOString(),
          sourcePeriod: { start: null, end: null },
          sources: Object.fromEntries(TYPES.filter(t => snapshot.sourceVersions[t].active).map(t => [t, {
            epoch: snapshot.sourceVersions[t].epoch, consentVersion: snapshot.sourceVersions[t].consentVersion }])),
          domains: Object.fromEntries(output.domains.map(d => [d.type, { recordCount: normalized.domains.find(n => n.type === d.type).recordCount,
            summary: `${d.status}: ${d.summary}${d.limitations.length ? `；${d.limitations.join("；")}` : ""}` }])),
          patternSummary: output.patternSummary };
      } else {
        normalized = normalize(sources); sources = null;
        summary = summarize(normalized, snapshot.sourceVersions, new Date(now()).toISOString());
      }
      normalized = null;
      const key = await keys.publicKey(clinic);
      requireThat(keys.canWrite(clinic, key.keyVersion), "failed-precondition");
      const epoch = snapshot.epoch + 1;
      const envelope = encryptSummary(uid, clinic, epoch, key.keyVersion, key.publicKeyPem, summary);
      summary = null;
      await verifySession(request);
      await db.runTransaction(async tx => {
        same(await state(tx, actor, uid, clinic), snapshot);
        tx.set(current(uid, clinic), envelope);
        tx.set(scope(uid, clinic), { active: true, consentVersion: 1, epoch, revokedAt: null, ...(snapshot.external ? { provider: "openai" } : {}) });
        audit(tx, "summary.generate", actor, uid);
      });
      savedEnvelope = envelope;
      await verifySession(request);
      await db.runTransaction(async tx => {
        same(await state(tx, actor, uid, clinic), { ...snapshot, epoch });
        requireThat((await tx.get(current(uid, clinic))).data()?.epoch === epoch, "aborted");
        audit(tx, "summary.generated", actor, uid);
      });
      // Generation never returns plaintext. Physician uses the independently authorized read.
      if (race) await racePhase(lease, "completed", 60000);
      return { epoch, available: true };
    } catch (error) {
      if (savedEnvelope) await db.runTransaction(async tx => {
        const stored = (await tx.get(current(uid, clinic))).data();
        // Remove only this failed generation, never a newer successful generation.
        if (stored?.epoch === savedEnvelope.epoch && stored.ciphertext === savedEnvelope.ciphertext) tx.delete(current(uid, clinic));
        audit(tx, "summary.invalidated", actor, uid, "invalidated");
      });
      if (race && lease) await racePhase(lease, error.raceExpired === true ? "expired" : error.code === "aborted" ? "invalidated" : "rejected", 60000);
      await rejected(actor, uid); throw error;
    }
    finally {
      sources = null; normalized = null; summary = null;
      if (lease) await db.runTransaction(async tx => {
        const stored = (await tx.get(lease.ref)).data();
        if (stored?.owner === lease.owner) tx.set(lease.ref, { ...stored, expiresAt: 0 });
      });
    }
  }
  async function readCurrent(request) {
    const actor = caller(request), uid = identifier(request.data?.uid), clinic = identifier(request.data?.clinicId);
    let summary, stage = "session";
    try {
      await verifySession(request);
      stage = "authorization";
      const snapshot = await db.runTransaction(async tx => {
        const authorization = await state(tx, actor, uid, clinic);
        stage = "envelope";
        const envelope = (await tx.get(current(uid, clinic))).data();
        if (!envelope || envelope.epoch !== authorization.epoch) stale();
        requireThat(keys.canRead(clinic, envelope.keyVersion), "failed-precondition");
        return { ...authorization, envelope };
      });
      stage = "beforeDecrypt";
      await check(request, actor, uid, clinic, snapshot);
      stage = "decrypt";
      summary = await decrypt(uid, clinic, "current", snapshot.envelope, (v, b) => keys.unwrap(clinic, v, b), "aiSummaries");
      stage = "sourceVersions";
      const active = TYPES.filter(t => snapshot.sourceVersions[t].active);
      if (!(summary.schemaVersion === (snapshot.external ? 4 : 2) && Object.keys(summary.sources).length === active.length && active.every(t => summary.sources[t]?.epoch === snapshot.sourceVersions[t].epoch && summary.sources[t]?.consentVersion === snapshot.sourceVersions[t].consentVersion))) stale();
      stage = "finalSession";
      await verifySession(request);
      stage = "finalAuthorization";
      await db.runTransaction(async tx => {
        same(await state(tx, actor, uid, clinic), snapshot);
        requireThat((await tx.get(current(uid, clinic))).data()?.epoch === snapshot.epoch, "aborted");
        audit(tx, "summary.read", actor, uid);
      });
      return { records: [summary], epoch: snapshot.epoch, expiresInSeconds: 30 };
    } catch (error) { summary = null; await rejected(actor, uid, stage); throw error; }
  }
  async function read(request) {
    if (raceTestEnabled && request.auth?.uid === raceDoctorUid) { await authorizeRace(request); return readCurrent(request); }
    try { return await readCurrent(request); }
    catch (error) {
      // Only a missing/stale version is eligible. Auth, corrupt ciphertext and races fail closed.
      if (error.code !== "failed-precondition" || error.regenerate !== true) throw error;
      await generate(request);
      const result = await readCurrent(request);
      return { ...result, updated: true };
    }
  }
  async function authorizeRace(request) {
    const actor = caller(request);
    requireThat(raceTestEnabled && projectId === PROJECT && actor === raceDoctorUid, "permission-denied");
    await verifySession(request);
    await db.runTransaction(async tx => {
      const [staffDoc, fixtureDoc, clinicDoc] = await Promise.all([tx.get(db.doc(`clinicStaff/${actor}`)), tx.get(db.doc(`demoEncryptedFixtures/${externalPatientUid}`)), tx.get(db.doc(`clinics/${raceClinicId}`))]);
      const staff = staffDoc.data(), fixture = fixtureDoc.data(), clinic = clinicDoc.data();
      requireThat(staff?.role === "doctor" && staff.clinicId === raceClinicId && staff.active !== false && (staff.status === undefined || staff.status === "active") && (staff.active === true || staff.status === "active"));
      requireThat(fixture?.synthetic === true && fixture.clinicId === raceClinicId && clinic?.status === "active");
      const patient = (await tx.get(db.doc(`inneraPatients/${identifier(fixture.patientId)}`))).data();
      requireThat(patient?.linked === true && patient.firebaseUid === externalPatientUid && patient.clinicId === raceClinicId);
    });
  }
  async function racePhase(lease, phase, ttl) {
    return db.runTransaction(async tx => { const old = (await tx.get(lease.ref)).data(); requireThat(old?.owner === lease.owner, "aborted"); const phaseAt = now(); const stamp = phase === "requesting" ? "requestingAt" : phase === "waiting_for_revoke" ? "waitingAt" : "finishedAt"; tx.set(lease.ref, { ...old, racePhase: phase, raceExpiresAt: phaseAt + ttl, ...(phase === "waiting_for_revoke" ? { expiresAt: phaseAt + ttl + 30000 } : {}), [stamp]: phaseAt }); return phaseAt; });
  }
  async function raceOperation(request) {
    await authorizeRace(request);
    const op = request.data?.raceOperation;
    if (op === "config") return { enabled: true };
    if (op === "run") return generate(request, true);
    requireThat(op === "status", "invalid-argument");
    const hash = createHash("sha256").update(`${PROJECT}:generation:${externalPatientUid}:${raceClinicId}`).digest("hex");
    const value = await db.runTransaction(async tx => (await tx.get(db.doc(`demoEncryptedGenerationLocks/${hash}`))).data());
    const valid = value?.raceExpiresAt > now() && ["requesting", "waiting_for_revoke", "invalidated", "rejected", "completed", "expired"].includes(value.racePhase);
    return { phase: valid ? value.racePhase : "idle", expiresInMs: valid ? Math.min(120000, value.raceExpiresAt - now()) : 0, ...Object.fromEntries(["requestingAt", "waitingAt", "finishedAt"].map(k => [k, valid && Number.isSafeInteger(value[k]) ? value[k] : null])) };
  }
  return { consent, revoke, generate, read, readCurrent, raceOperation };
}
module.exports = { createSummaryService };
