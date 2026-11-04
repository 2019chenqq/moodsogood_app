# Platform clinic deployment guard — F1-D-1

This preparation authorizes local checks only. No deployment or cloud acceptance has been performed. Never use the legacy Innera_platform_admin/functions implementation.

## Exact allowed batches

The wrapper accepts only the original three (createClinic, setClinicStatus, resendInitialAdminInvite), the F1 pair (getClinicDetails, updateClinicOperations), or all five. Every selector must include its codebase. Partial, mixed, duplicate, wildcard and broad selectors are rejected. F1-only release should select the pair to leave existing operations out of the deployment.

| Environment | Project | Config | Source / codebase | Region |
| --- | --- | --- | --- | --- |
| Demo | innera-demo | firebase.demo.json | functions_demo / demo-b2b | asia-east1 |
| Production | moodsogood-9e45b | firebase.json | functions / default | asia-east1 |

The wrapper checks exact project/config/source/codebase, selected exports, and byte equality of clinic and audit business logic across environments. Predeploy requires matching wrapper context. Execution uses --non-interactive, without --force or automatic retries. It does not deploy Rules or other functions. Missing exports are rejected rather than entering a deletion workflow. This is an accident-prevention guard, not an IAM boundary; a person able to modify scripts or forge context can bypass it. Predeploy cannot independently inspect every original CLI argument. Use the wrapper, never the printed Firebase command directly.

## Local checks (no deployment)

```powershell
node D:/QQ_Web/moodsogood_app/functions/scripts/platform-deploy.cjs --check --project innera-demo --config D:/QQ_Web/moodsogood_app/firebase.demo.json --codebase demo-b2b --only functions:demo-b2b:getClinicDetails,functions:demo-b2b:updateClinicOperations
node D:/QQ_Web/moodsogood_app/functions/scripts/platform-deploy.cjs --check --project moodsogood-9e45b --config D:/QQ_Web/moodsogood_app/firebase.json --codebase default --only functions:default:getClinicDetails,functions:default:updateClinicOperations
node --test D:/QQ_Web/moodsogood_app/functions/test/deployment/platform_guard.test.js D:/QQ_Web/moodsogood_app/functions/test/clinic/platform_clinics.test.js D:/QQ_Web/moodsogood_app/functions/test/clinic/clinic_operations.test.js
```

--check validates and prints a command without launching Firebase CLI or making network calls. Tests inspect real callable exports/region and both frontend configurations/script order. For local Rules/transaction verification, start the installed Firestore Emulator in a separate terminal:

```powershell
java '-Djdk.net.unixdomain.tmpdir=D:\QQ_Web\moodsogood_app\functions\test' -jar "$env:USERPROFILE\.cache\firebase\emulators\cloud-firestore-emulator-v1.22.0.jar" --host 127.0.0.1 --port 8187 --rules D:/QQ_Web/moodsogood_app/firestore.rules
```

Then run and stop the emulator with Ctrl+C afterward:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8187'
node --test D:/QQ_Web/moodsogood_app/functions/test/clinic/clinic_operations.emulator.test.js
Remove-Item Env:FIRESTORE_EMULATOR_HOST
```

The emulator suite loads both local Rules files. Neither grants clinicOperations access: the default deny covers direct client get/list/create/update/delete. No F1 Rules permission, Rules deployment, index or data migration is required. The currently deployed cloud Rules have not been inspected in this batch.

## Frontend publishing boundary

Both dashboards load Firebase compat App/Auth/Firestore/Functions, then their own config, admin-core.js, admin-clinics.js, admin-clinic-details.js and admin-create-clinic.js. Demo selects innera-demo; Production selects moodsogood-9e45b. Details initializes via innera:admin-ready, checks project identity and invokes the two exact callable names in asia-east1. Normal dashboards do not load the isolated local mock preview.

Both dashboards share JS and css/admin.css. Replacing these shared paths affects Production as well as Demo, even when only dashboard.demo.html is changed. Backend Demo deployment alone does not publish frontend files. The platform repository has CNAME admin.innerahealthcare.com but no Firebase Hosting target; the live publishing provider, branch, path and cache behavior are not established here. Therefore no frontend publish command is assumed.

Before frontend release, obtain an approved isolated Demo static destination with its required existing environment configuration, or explicit authorization for the shared Production frontend impact. If isolation requires Auth/config changes, stop for a separate scoped review. Do not publish test files or mock preview assets. Do not point Production at Demo or use Demo deployment as approval for Production.

## Future authorized Demo deployment and acceptance

These steps require separate deployment authorization; the --execute command below is documentation only.

1. Freeze and review the exact release artifact, recording file hashes and test results. Include required reviewed untracked Demo source, not all unrelated working files. Preserve a known previous compatible artifact and its configuration for rollback; never use git reset/clean or include credentials.
2. With authorized read-only cloud inspection, confirm project innera-demo, codebase demo-b2b, region asia-east1, deployed function ownership/inventory, deployed Rules denial and existing release revision. Resolve any resource-name/codebase collision before proceeding. Verify the isolated Demo frontend destination and rollback artifact. These cloud facts remain unverified in F1-D-1.
3. Rerun the Demo --check above against the frozen artifact. After explicit deployment approval, run only:

```powershell
node D:/QQ_Web/moodsogood_app/functions/scripts/platform-deploy.cjs --execute --project innera-demo --config D:/QQ_Web/moodsogood_app/firebase.demo.json --codebase demo-b2b --only functions:demo-b2b:getClinicDetails,functions:demo-b2b:updateClinicOperations
```

4. Confirm both selected functions deployed successfully in the expected project/codebase/region. On partial failure, stop; do not automatically retry, broaden selectors, force deletions or publish the frontend.
5. Publish the reviewed frontend only through the separately established isolated Demo publishing procedure. Verify actual loaded config, scripts and request project/region; do not record tokens or credentials.
6. Using approved fictional Demo fixtures and independent authorized accounts, verify: absent operations returns null/revision 0; first save revision 1; subsequent update/clear/readback and server updatedAt; disabled clinic remains disabled; missing clinic is distinct from empty operations; permission/network errors never show success; concurrent revision conflict preserves draft and requires explicit reload; duplicate submit, rapid clinic switching and unsaved-navigation prompts work. Confirm clinics documents remain unchanged and successful update has one safe audit record. Check direct client reads/writes remain denied using approved test tooling. Never use real patient/medical data.
7. Check existing create/status/invitation controls remain present. Actual creation, status changes and invitation email testing require approved disposable fixtures and recipients; do not send to real users casually. Production release remains separately authorized.

Stop on any failed test, environment/config mismatch, unexpected resource/deletion prompt, missing rollback artifact, unknown deployed Rules, unauthorized test data, or shared Production frontend impact without approval. A passing --check proves local selection safety, not deployed readiness.

## Rollback (separate authorization required)

First restore the prior isolated Demo frontend artifact to stop new edits. Do not overwrite shared Production assets or reset the developer working tree. For a backend regression, use the previous compatible reviewed artifact with both F1 exports and the guard, preserving Prod/Demo source parity, then run --check and the same exact Demo F1-pair --execute selection after approval. Do not use legacy platform functions or broad deploy commands.

For the first F1 release there may be no prior backend artifact containing these exports. Do not deploy an old artifact missing them or delete functions automatically: restore the frontend and prepare an approved corrective backend release. Code rollback does not undo saved operations, revisions, invitations or audit records; do not delete or rewrite data as part of rollback. Record acceptance failures and stop before further batches.
