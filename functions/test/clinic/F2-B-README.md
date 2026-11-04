# F2-B trial backend contract (local implementation only)

No deployment, cloud data mutation, UI or Rules changes are part of this batch.
Both `functions` and `functions_demo` contain the same local implementation.

## Storage and compatibility

`clinicOperations/{clinicId}` retains schemaVersion 1, the six F1 fields,
shared revision and createdAt/createdBy/updatedAt/updatedBy metadata.
Optional `trial` is a map with:

- schemaVersion: 1; startDate: YYYY-MM-DD; durationDays: 84; timeZone: Asia/Taipei.
- resolution: null | converted | terminated.
- resolvedAt: Timestamp|null; resolvedBy: uid|null; resolutionReason: string|null.
- updatedAt: Timestamp; updatedBy: uid.

Absent trial means not_configured; explicit null or malformed core trial fields
fail closed. Reads never initialize data. First trial write initializes missing
F1 fields to empty strings. F1 updates preserve trial and F2 updates preserve F1.

## Callable wire contracts

All functions use asia-east1 and the existing active platform admin authorization,
including a repeat check inside the transaction. No RBAC or Auth changes.

`getClinicDetails({clinicId})` preserves clinic, operations, revision and updatedAt;
adds trial (null when absent), trialComputed and evaluatedAt.

`updateClinicTrial` accepts exactly one of:

```js
{ clinicId, expectedRevision, action: "setStart", startDate: "2026-10-28" }
{ clinicId, expectedRevision, action: "convert", reason: "Cooperation approved" }
{ clinicId, expectedRevision, action: "terminate", reason: "Pilot ended" }
```

Returns `{revision, updatedAt, trial, trialComputed, evaluatedAt}`. All wire
timestamps use `{seconds, nanoseconds}`. Trial timestamps have this format too.
`trialComputed` contains status, endDateExclusive, lastTrialDate, expiresAt and
remainingDays. No derived state or expiry is persisted.

Status: not_configured | scheduled | active | expired | converted | terminated.
Manual resolutions take priority. Start is inclusive, day 84's following midnight
exclusive (start date + 84 calendar days). Taipei day 1 has 84 remaining days,
last day 1, expired 0; scheduled/unconfigured/resolved have null remainingDays.
Example: 2026-10-27 starts; 2027-01-18 is the last day; expires 2027-01-19 00:00 +08.
Accepted date domain: 2000-01-01 through 9998-12-31 (safe four-digit expiry year,
modern Asia/Taipei UTC+08 calendar). Dates must round-trip exactly, without padding.

Each transaction attempt samples backend time once after its reads and uses that
sample for every validation/calculation and evaluatedAt. Retried attempts take a
fresh sample. Commit timestamps are distinct from evaluatedAt; responses describe
the accepted attempt's evaluation, not a later status. The immutable audit commit
timestamp supplies updatedAt/resolvedAt without rereading a potentially newer doc.

setStart allows today/future only, from absent or scheduled, rejects unchanged dates.
Once active/expired, start cannot change. convert/terminate allow scheduled/active/
expired only; reasons are trimmed and must have 1–500 UTF-16 code units (same length
convention as F1). Terminal states cannot be reopened, switched or rescheduled.

Unknown fields/actions/types produce invalid-argument. Unauthorized/not found use
existing error codes. failed-precondition reasons include revision-conflict
(with currentRevision), trial-terminal, trial-already-started, trial-start-in-past,
trial-no-change, trial-not-configured and invalid-trial. Rejected operations do not
write or advance revision. Same expectedRevision cannot commit twice; requestId is
not a cross-invocation idempotency key. If a response is lost or commit time cannot
be confirmed, reread before deciding whether any new action is necessary.

## Audit and isolation

Actions: clinic.trial.set_start, reschedule, convert, terminate (each with the
clinic.trial prefix). targetType is clinicOperations. Before/after whitelist:
revision, startDate, resolution, resolutionReason. Actor/time/request metadata use
the existing audit mechanism. Audit and trial/metadata/revision share one transaction.
Automatic time transitions produce no writes or audit events. No scheduler.

No mutation of clinics or medical records and no authorization dependency on trial.
Client access to operations/audit remains denied by existing Rules. Conversion is
an operational label, not proof of payment. Future extensions, billing and repeated
cooperation records require a separately designed contract; no extra structures now.

## Local verification and F2-D backlog

Run from repository root:

```sh
node --test functions/test/clinic/clinic_trial.test.js functions/test/clinic/clinic_operations.test.js functions/test/clinic/platform_clinics.test.js
```

Uses actual callable bodies with injected in-memory Firestore, no network APIs.
The test double preserves nested Timestamp values and resolves nested serverTimestamp
sentinels. Its retry/failure simulation is NOT proof of Firestore transaction behavior.

F2-D must verify with Emulator: concurrent F1/F2 writes and duplicate requests,
real transaction retry/revocation, audit failure rollback, nested timestamp commit
equality, all client identities denied direct operations/audit access, and actual
doctor/patient medical access unchanged across expiry/convert/terminate. Also test
lost response recovery and simultaneous-tab UI integration after F2-C.

Deployment allowlists remain unchanged and do not yet permit updateClinicTrial;
prepare and authorize deployment separately. No cloud validation is claimed.
