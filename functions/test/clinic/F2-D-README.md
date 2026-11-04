# F2-D local integration and safety acceptance — 2026-10-27

Local acceptance passed. No product code, backend schema, callable contract, UI
styling, Firestore Rules or deployment allowlist was changed in this batch.
No cloud data, deployment, commit/push or OpenAI API was used.

## Changes

- Added clinic_trial.emulator.test.js: actual Firestore transactions, fault
  injection at audit create preconditions and SDK retry boundaries, and actual
  client Rules tests against both existing Rules files and backend source copies.
- Extended Innera_platform_admin/test/clinic-details.test.cjs: four F2-D browser
  integration cases using the existing localhost HTTP handler bridge, in addition
  to the existing F1 integration case. Trial requests now reach the actual
  Callable handler backed by Firestore Emulator.
- Test-only fixes: reset synthetic per-clinic audit fixtures for repeat runs;
  distinguish Chromium's embedded data: calendar icon from external networking.
  CSP and external-origin restrictions were not loosened.

## Final executed results

| Group | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Firestore Emulator transactions / Rules | 62 | 0 | 0 |
| Backend unit tests | 58 | 0 | 0 |
| Frontend environment/invitation unit tests | 48 | 0 | 0 |
| Browser suite | 36 | 0 | 0 |

The 62 Emulator cases comprise 38 F2-D and 24 existing F1 cases. Both functions
and functions_demo source variants are exercised. Browser tests comprise 5 actual
handler/Firestore integrations (4 F2-D + 1 F1) and 31 mock/UI regression cases.
Final local logs: clinic/f2d-emulator.log and
Innera_platform_admin/test/f2d-ui-integration.log (ignored generated logs).

## Evidence

- **Revision/concurrency:** actual simultaneous F2/F2 and F1/F2 transactions at
  the same expectedRevision yield one success and one revision-conflict. The
  stored revision advances once and exactly one new success audit is committed.
  Stale revisions and illegal/duplicate terminal transitions preserve storage.
- **F1 compatibility:** deterministic nonempty six-field fixtures survive F2
  setup and closure; subsequent F1 updates preserve the trial map exactly,
  including Timestamp values. Simultaneous F1/F2 updates are also tested.
- **Audit atomicity:** pre-create the exact audit document before the actual
  transaction so its create precondition fails at Firestore commit. Both initial
  trial creation and closure roll back completely, preserving revision/metadata.
  Trial updatedAt/resolvedAt, operations updatedAt and audit createdAt match the
  same actual commit timestamp. Post-commit timestamp read failure returns an
  uncertain result; reread recovers the committed record without a second write.
- **Authorization:** actual handlers reject absent auth, non-admin/doctor and
  inactive platform admin. Revocation after entry authorization is rejected in
  the transaction. For retry-time revocation, the first real transaction queues
  writes then receives an injected SDK ABORTED; the principal is disabled before
  the real SDK's second attempt. No pending business/audit write is committed.
  This is controlled retry fault injection, not a claim that revocation can
  retroactively invalidate an already committed authorized transaction.
- **Direct client access:** actual Rules reject get/list/create/replace/update/
  delete for clinicOperations and auditLogs for unauthenticated, ordinary,
  active/inactive platform admin, doctor, nurse and patient identities.
- **Medical isolation:** across not_configured, scheduled, active, expired,
  converted and terminated, actual Rules continue allowing the same clinic's
  active doctor to read authorized sleep, health-event, check-in, medication and
  synthetic AI-summary records. Doctor writes remain denied. Patient reads and
  permitted writes remain allowed; patient AI-summary writes remain denied.
  Other-clinic doctors, disabled doctors, nurses, platform-only admins, other
  patients and unauthenticated users remain denied. Revoked patient sharing and
  private patient data remain inaccessible to doctors. Clinic activation and
  patient sharing documents remain byte-for-byte equivalent as data objects.
- **UI integration:** initial missing trial does not create operations; setStart,
  reschedule, convert and terminate persist through actual handlers. F1/F2
  writes send revisions 0/1/2/3 in order. A concurrent handler write produces a
  real revision conflict with browser input preserved. A test transport error
  after a real termination commit produces uncertainty, no resend, and a
  confirmed reload matching the persisted terminal record and audit count.
  All six states, dates, expiry timestamps and remaining days match actual
  getClinicDetails output from synthetic Emulator fixtures.

## Reproduction (local only)

Java 21.0.12 and the cached Firestore Emulator v1.22.0 were used. The default
Windows TEMP short path produced a UnixDomainSockets connect error. Reading the
installed JDK source identified the supported per-process socket-directory
override; using a real workspace path resolved startup without system changes.

Start in moodsogood_app (keep this process running during tests):

```powershell
New-Item -ItemType Directory -Path functions/test/.tmp-f2d -Force | Out-Null
java '-Djdk.net.unixdomain.tmpdir=D:\QQ_Web\moodsogood_app\functions\test\.tmp-f2d' -jar "$env:USERPROFILE\.cache\firebase\emulators\cloud-firestore-emulator-v1.22.0.jar" --host 127.0.0.1 --port 8187 --rules firestore.rules --project_id demo-innera-f2d
```

In a separate terminal, also in moodsogood_app:

```powershell
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8187'
node --test functions/test/clinic/clinic_trial.emulator.test.js functions/test/clinic/clinic_operations.emulator.test.js
node --test functions/test/clinic/clinic_trial.test.js functions/test/clinic/clinic_operations.test.js functions/test/clinic/platform_clinics.test.js
```

In Innera_platform_admin, with the same Emulator environment variable:

```powershell
node --test test/clinic-details.test.cjs
node --test test/environment-isolation.test.cjs test/invitation-flow.test.cjs
```

Emulator tests require 127.0.0.1 explicitly and use demo-innera-* project IDs.
No cloud fallback. Browser profiles and test HTTP servers are isolated and closed
after the suite. No export/import of cloud data is involved.

## Limits and Demo release readiness

Local F2-D acceptance is satisfied. This does not establish cloud readiness.
Handler invocation uses synthetic request.auth through the existing test harness;
Functions/Auth Emulator JWT verification, Firebase callable network protocol,
App Check, CORS, cloud IAM and actual Demo Hosting behavior were not exercised.
Rules test identities are synthetic authenticated Rules contexts. No clinical AI
generation is called; AI summaries are synthetic stored records.

The existing deployment guard still only permits the reviewed legacy/F1 batches;
it does not permit updateClinicTrial. Therefore deployment is not currently
executable through the approved guard. A subsequent explicitly authorized release
preparation must review that allowlist and environment/artifact checks; this batch
does not change it or bypass it.

Planned minimal Demo scope, only after separate authorization:

1. Functions in innera-demo / asia-east1: update getClinicDetails; add
   updateClinicTrial, using functions_demo and its trial/audit helper dependencies.
   The existing updateClinicOperations handler remains compatible; no functional
   F2 change requires redeploying it by itself.
2. Then rebuild and publish only Hosting target admin-demo from the existing
   dist/admin-demo allowlisted artifact. Functional changes are shared
   js/admin-clinic-details.js and css/admin.css. Never include tests, mocks or
   logs, and never publish the repository root.
3. No Rules, Auth/IAM, medical authorization, data migration or scheduler scope.

F2-D stops here. No deployment or later phase is authorized by these results.
