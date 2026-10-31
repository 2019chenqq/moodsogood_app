# OpenAI synthetic-only encrypted summary acceptance

## Boundary

Only innera-demo and the existing synthetic fixture UID demo-encrypted-sleep-patient.
No users paths, formal clinicalShares, production functions, history migration or KMS changes.
Existing mock consent remains mock. The patient must explicitly choose provider=openai
through the new synthetic external-processing consent. Revoke clears that scope/current;
the old mock button switches consent back to mock and invalidates current.

## Runtime

OPENAI_ENCRYPTED_DEMO_API_KEY exists in Secret Manager, enabled version 1.
Only the dedicated demo runtime identity has the secret-level Secret Accessor binding.
Only demoGenerateSummary/demoReadSummary bind the secret. No secret value is read by
local tooling, written into repo/env files or displayed. The SDK obtains it in runtime memory.
Responses API, gpt-4.1-mini, store=false/background=false/stream=false/tools=[],
timeout 15000ms, maxRetries=0, explicit logLevel=off and no-op SDK logger.
Actual model access and key/project separation are not inferred from secret existence.

## Minimal payload

schemaVersion, windowDays, domains[type,recordCount,coverageDays,facts].
Each fact is fixed code, numeric/null value, unit and sampleCount.
Only sleep duration/quality means, symptom entry count, check-in mood/health means,
active medication count and dailyRecord mood mean. No heterogeneous symptom averaging.
No arbitrary labels, note/context, medication names/doses, identifiers, paths, exact dates,
provenance or source epochs. Unknown schema/fields/codes fail closed.
All records must span at most 14 days, total <=30, domains <=5, facts/domain <=10,
payload <=32KiB, output <=1500 tokens/16KiB and envelope plaintext <=8192 bytes.
The synthetic period is anchored to the latest supplied source day, not real today.
Medication coverage describes start dates, not administration or adherence.

## Authorization and persistence

Complete active/inactive five-source authorization snapshot remains internal.
Recheck Auth/doctor/clinic/link/summary consent/source epochs before external call,
after it returns, in the save transaction and before release.
Model output is validated after authorization recheck; it cannot choose provenance.
Encrypted payload v3 adds OpenAI model and patternSummary; sources are server-supplied.
Outer envelope/AAD remains unchanged and has only nine ciphertext fields.
Raw provider errors, request/response bodies and normalized data are never logged.
Only numeric latency/input-token/output-token metrics are emitted.

Cross-instance transaction lease at demoEncryptedGenerationLocks/{hashed-routing-ref},
90-second expiry, 60-second cooldown, at most 2 attempts per synthetic patient/clinic
per UTC day (also counts failures and races). Valid current summary is reused.
Crash recovery waits for lease expiry; provider timeout is never automatically retried.
Source changes can be safely unavailable during cooldown/quota; they never revive old data.

## Verification status (2026-10-11)

104 backend/interop tests passed, including 22 new fake-provider tests.
One actual Firestore emulator/Rules integration passed; 16 doctor UI tests passed.
Dart analyze and patient release build passed. Emulator uses the documented local
-Djdk.net.unixdomain.tmpdir=D:/QQ_Web/moodsogood_app/.dart_tool workaround.
Synthetic real OpenAI call, real structured output, cloud revoke race, successful-result
storage/log audit and token/cost evidence are PENDING human demo login and consent.
Do not treat fake provider tests, deployment success or empty logs as external acceptance.

Current cloud source metadata before acceptance: HealthEvent inactive; the other four
active. Patient needs to re-share only the fixed synthetic HealthEvent before five-source
acceptance, and explicitly enable OpenAI synthetic consent. Do not share real data.

## Remaining risks

API request already transmitted cannot be remotely erased by later revocation.
Account ZDR/MAM/BAA/retention qualification remains unconfirmed. store=false is not ZDR.
Production plaintext summary/log migration is outside this task.
Dependency audit reports existing firebase-admin/node-forge high and seven moderate
advisories; no automatic dependency upgrade or production package change was performed.
Strict JSON format does not guarantee clinical correctness or de-identification of arbitrary
generated text; input deliberately has no identity/free text and output gets bounded checks.
Clinical field semantics, clinical quality evaluation and account controls remain prerequisites
for real health data. Only synthetic data is authorized here.

## 2026-10-11 semantic hardening acceptance (in progress)

- Demo-only external summary payload revision 4; older revision 3 is stale and must regenerate. Mock revision 2 is unchanged.
- Provider response is restricted to domain, status, fact-code references and an exact server-generated period label. Free-text observations/patterns are rejected. Server renders observations from normalized values; no provider prose reaches stored or displayed summaries.
- Numeric normalization validates domain/code/unit, nonnegative finite values, score bounds and duplicate fact codes. Medication active count uses isActive === true and describes records, never administration or adherence. Health symptom count is an item count, never severity. Date-span/coverage wording explicitly does not imply complete continuous coverage or recency.
- Semantic violations fail closed with sanitized data-loss; no correction retry and no invalid response persistence. SDK maxRetries=0, store=false, background=false, stream=false, logger disabled.
- Local verification: 27 OpenAI fake-provider cases, 16 clinician cases, full five-source/summary/interop regression, real Firestore emulator transaction/Rules case, Dart analyze and release Web build passed. WebAssembly dry-run compatibility warnings remain; JavaScript Web build succeeded.
- Existing successful-call Cloud Logging sample: 92 entries; no medical-JSON, credential or DEK markers found. Marker scanning is not a guarantee of comprehensive DLP. Existing current Firestore summary has exactly the nine envelope fields, no unexpected fields.
- Current real-call daily lock: two attempts already used. Counter and quota have NOT been changed. Revised real-provider positive acceptance, real-provider in-flight revoke race and browser storage inspection remain pending quota availability and authenticated browser access. Browser automation inventory currently exposes no authenticated Chrome tabs.
- No controlled race hook has been enabled. No production, KMS, IAM, official clinical summary or Chat Completions changes.
- Do not label this round fully accepted until the remaining real-provider and browser checks are recorded.
- Deployment completed: innera-demo demoGenerateSummary and demoReadSummary (encrypted-sleep-demo codebase), plus innera-demo-encrypted-doctor Hosting. No patient Hosting, Rules, KMS, IAM or other Functions deployment in this round. Runtime state ACTIVE and dedicated service identity verified after deployment.
- Final full backend suite: 109 passed, one emulator-only case skipped in unit run; that emulator case passed separately. Clinician suite: 16 passed. Total 126 passing cases across the suites, zero failures.

## 2026-10-13 explicit race mode preparation (NOT DEPLOYED)

- Server opt-in: DEMO_RACE_TEST_ENABLED=true, absent by default. getService rejects projects other than innera-demo. Dedicated test doctor UID and synthetic fixture/clinic authorization are revalidated for config/status/run. No request can enable server opt-in. Production codebase does not import these files.
- Existing demoGenerateSummary handles config/status/run; no new callable/resource/role/quota. Existing demoReadSummary for the opted-in test doctor uses readCurrent only, never regeneration. Ordinary generate is blocked for that test doctor while race opt-in is enabled.
- A run preserves the original lock, cooldown and two-attempt daily cap, requires five active sources and OpenAI consent, and rejects an already valid summary instead of reusing it as a test result.
- After the real provider returns, lock metadata carries waiting_for_revoke with a 15-second logical expiry. Provider payload is never stored in status. Response is rechecked against source epochs after waiting; invalidated/rejected terminal state expires after 60 seconds. Only phase and remaining TTL are returned. Expiry does not create a new Firestore TTL policy.
- UI has an authorized enable button and one-shot run button. Race mode does not auto-read summaries, does not schedule ten-second refresh, does not retry run after failure or visibility return, clears source plaintext using existing controllers, and never renders run response as a summary. Status-only polling uses a 500ms delay between completed checks.
- Old unconditional demo-race-delay hook is disabled and no longer wired into index.
- Audit expectation remains summary.rejected/result=rejected with no successful generate/generated actions during rejected race; audit conventions unchanged.
- Verification: full backend suite 112 pass, one emulator-only skip; final additional authorization case verified in the OpenAI suite (31 pass). Clinician suite 18 pass, including no retries for aborted and resource-exhausted. Fake race covers waiting TTL, epoch change, no save, no resurrection, cooldown and daily cap. No real OpenAI calls made.
- Deployment blocked by the user's instruction to stop for additional cloud costs: status polling adds callable invocations and approximately five Firestore document reads per completed status check (plus authentication checks). No new IAM is needed. Await approval before setting demo opt-in and deploying only the two summary Functions and doctor demo Hosting. No deployment or environment opt-in performed in this preparation round.

## 2026-10-13 approved race-mode deployment

- User approved the small status-query invocation/read costs. Deployed ONLY encrypted-sleep-demo:demoGenerateSummary, encrypted-sleep-demo:demoReadSummary, and innera-demo-encrypted-doctor Hosting.
- Demo-only .env.innera-demo opts in the server capability. Browser race mode remains false until the authorized enable button is clicked. No production configuration opt-in.
- Both Functions ACTIVE under demo-encrypted-share@innera-demo.iam.gserviceaccount.com. Generate timeout 120 seconds (and manual race client timeout 120 seconds) to avoid the previous 60-second cutoff; read remains 60 seconds. Provider timeout/retry, two attempts per UTC day, 60-second cooldown, 90-second lock, KMS/IAM/App Check unchanged.
- Preflight: doctor Hosting HTTP200 contains enable/run controls; unauthenticated status probe returns401. Generation quota unchanged, today remaining2. No real OpenAI request triggered. Authorized deployed config/status confirmation still requires the human's authenticated test browser; local fake-provider covers the positive config/status and waiting transition.
- Relevant backend72 and clinician18 cases passed after timeout/UI changes. Existing tracked changes preserved, no commit/push. HealthEvent was inactive at preflight and must be shared before one-shot run. Do not trigger run until authorized UI status check succeeds.

## 2026-10-13 minimal status synchronization fix deployed

- Status failures get at most three retries across one run; generation is never retried. Retry exhaustion or patient close latches the interruption message, which generation success/failure cannot overwrite. Polling stops after interruption.
- Lock stage metadata now records requestingAt/waitingAt/finishedAt, returned only while the existing logical status TTL is valid; expired status returns null timestamps. No provider/source content is stored.
- Related backend72 and summary/race UI9 tests passed, including transient status recovery, exactly three retries (four failed checks total), patient clear, late completed result preserving interruption, and single generation for each case. No full-suite rerun or real provider call.
- Deployed only demoGenerateSummary/demoReadSummary and innera-demo-encrypted-doctor Hosting; no production/IAM/quota changes. Quota last verified remaining1, attempts1. Existing valid current summary must be invalidated by patient re-consenting to OpenAI before another fresh race, without generation. All existing workspace changes retained, no commit/push.

## 2026-10-13 waiting-until-revoke patch (local only, NOT DEPLOYED)

- Race-only provider response handling now waits for source/authorization snapshot changes for up to120s, checking authorization between short sleeps. Changes abort and discard the response; deadline discards it with expired, never falling through to summary encryption/save. Normal mock/OpenAI summary flow is unchanged outside race.
- Waiting status TTL120s; terminal status TTL60s. requestingAt/waitingAt/finishedAt remain low-sensitivity metadata. The current lease extends to waiting deadline plus30s grace to prevent another generation entering mid-wait; daily attempts and60s cooldown unchanged.
- Demo opted-in generation/client timeout240s, default function/read timeout60s. Expiry transports only fixed racePhase=expired details; no medical/provider content. UI retains bounded status retries and interruption latch; expired is explicit and generation is never retried.
- Related backend77 and summary/race UI10 cases pass. Fake provider covers revocation at1s/30s/119s, no-revoke120s expiry, no summary save, one provider invocation, status transient recovery/exhaustion, patient clear, expired UI and client/function timeout contracts. No full-suite rerun, cloud operation, deployment or real OpenAI call.
- Necessary future deployment: only demoGenerateSummary/demoReadSummary and innera-demo-encrypted-doctor Hosting. Existing deployed cloud version still uses15s waiting until explicitly approved deployment of this patch.

## 2026-10-13 approved 120-second revoke-wait deployment

- Successfully deployed only encrypted-sleep-demo demoGenerateSummary/demoReadSummary and innera-demo-encrypted-doctor Hosting. No other Hosting/codebase deployed.
- generate ACTIVE timeout240s; read ACTIVE timeout60s; dedicated service identity retained. Published doctor JS matches tested local source, uses client240s timeout, bounded status retry and expired UI.
- Uploaded tested backend uses120s waiting TTL/deadline, maintains lease through deadline plus30s, and discards on authorization changes or expiry before encryption/save. No live generation was invoked to verify wait; behavior is covered by the prior77 backend/10 UI tests. No tests rerun because code unchanged.
- Pre/post deployment quota reads show today attempts2, remaining0. No reset or quota bypass. Wait for normal next UTC-day reset before real manual race. All workspace changes preserved, no commit/push; no KMS/IAM/production change.

## 2026-10-14 最終驗收與 Demo 收尾

本節是最終狀態；先前各輪的「待驗收／未部署」保留為歷史進度，不代表目前仍未完成。

### 已完成的 synthetic 雲端驗收

| 項目 | 結果與證據範圍 |
|---|---|
| Sleep、HealthEvent、Check-in、Medication、dailyRecords | 既有患者分享、Firestore envelope、醫師讀取、各 scope 撤銷雲端操作已完成，使用者確認通過。本輪不重播，也不接觸真實/legacy 資料。 |
| KMS/IAM/App Check | innera-demo 真實 KMS 解密、專用 runtime identity、既有最小角色及 App Check 已驗收；本輪不重建或改權限。 |
| Encrypted AI Summary | 明確同意、加密保存、有效醫師自動解密、來源 epoch/provenance stale 檢查、partial-source A/B/C regeneration 已驗收。 |
| 真實 OpenAI Responses | 五來源 synthetic 正向摘要與語意驗證已通過；HealthEvent 數量不作 severity、用藥紀錄不作實際服藥/依從性、期間由 server 固定文字產生。Provider 僅傳最小化統計，不傳身份或 raw notes。 |
| 真實 revoke race | 2026-10-14，使用者按單次 race，收到 provider response 後才撤銷 HealthEvent。後端等待階段時間与撤銷對齊，回應丟棄，current=404，醫師畫面 invalidated。 |

真實 race 低敏時間證據（台灣時間）：requesting 09:18:39.685；provider 回應 log 09:19:12.143；waiting 09:19:12.334；HealthEvent revoked 09:19:24.033，epoch=23；finished invalidated 09:19:27.387。稽核 action 包含 healthEvent.revoke、summary.invalidated、summary.rejected；本次沒有 summary.generate/generated。重新分享不復活此前已另行驗證，本次不重新呼叫 provider。

### 測試與安全檢查範圍

- 2026-10-11 語意 hardening 累計126項（含當輪互通/emulator/UI）。2026-10-13 的120s race patch：相關後端77、summary/race UI10通過。
- 2026-10-14 收尾重跑相關後端77與醫師UI23，共100項通過；包含預設關閉的 config/status/run 拒絕、無測試控制項、正常摘要 reuse/regenerate、partial-source、撤銷、有限 quota/cooldown、顯示到期/頁面隱藏清除。這些測試有重疊，不把各輪數量累加為獨立覆蓋數。
- 五來源文件與 summary 的 Firestore 檢查以 envelope 欄位及 synthetic 實測為範圍，不下載/保存醫療明文。最後 race 的 current 回傳404。
- 最後真實 race 的81筆生成 Functions log：medical/credential/DEK 標記計數均0；audit 欄位符合既定六個低敏欄位。檢查沒有輸出原始 logs、provider response 或 tokens。
- 患者/醫師 browser storage 標記掃描涵蓋 Local Storage、Session Storage、IndexedDB、Cache Storage；既有成功摘要後人工檢查通過。這不是全面DLP，不證明不存在所有未知形式的洩漏。
- OpenAI adapter store=false、background=false、SDK logger off/maxRetries0。未假設帳號有ZDR、MAM或BAA。

### 收尾變更及界線

- demo .env.innera-demo 的 DEMO_RACE_TEST_ENABLED=false；原15s helper ENABLED=false且未接入正常 runtime；正常 provider 回應不加測試等待。
- 醫師公開頁移除啟用/單次race/狀態控制項，public JS hard-disables race handlers。既有 race 測試以VM-only opt-in保留；雲端 config/status/run 由後端開關拒絕。
- 一般 Demo 恢復 read→缺失/stale時 generate→重新授權讀取，以及UI每10s重新驗證/30s清除。正常有效摘要重用，2次UTC-day attempts、60s cooldown與generation lock保留。一般自動更新失敗仍可能消耗生成嘗試；日上限不會無限呼叫 provider。
- 本輪正常流程以fake provider與UI VM驗證，雲端僅驗部署/公開入口/開關與quota。沒有為收尾新增真實OpenAI呼叫或已登入醫師端E2E；不可把設定檢查說成新的登入實測。
- 既有repo修改/未追蹤檔案保留，不commit/push。不得部署正式入口、遷移/修改正式clinicalShares或歷史dailyRecords。

### 尚未涵蓋與 Production 前工作

1. Demo 完成僅證明synthetic鏈路，不代表production可直接切換；正式金鑰/院所配置、rotation、備援/復原、停用及稽核營運需另案驗證。
2. Firestore Console資料密文不等於可對抗持有部署/KMS/service-identity管理權的攻擊者；有權修改解密服務的人可能取得runtime明文。需最小權限、職責隔離、變更審核與監控。
3. 撤銷阻擋後续讀取/保存，不能收回醫師先前看過/截圖的內容，也不能遠端抹除已送外部provider的請求。
4. 正式OpenAI資料處理條件、retention、ZDR/MAM/BAA資格未確認。正式患者同意及資料最小化/輸出語意規則需正式審查；demo未涵蓋所有真實症狀/用藥/語言情境。
5. 正式ClinicalShareService目前仍有明文同步風險，clinical summary依赖与legacy遷移/刪除/備份留存、索引/Rules、相容/回滾應先設計，不在本輪實作。
6. 更全面的DLP、攻擊面/負載/費用/分散式競態與失敗演練、Auth/App Check失效及長時間醫師頁行為仍需production前測試。

部署結果與收尾雲端開關另在本節後附記。

### 2026-10-14 收尾部署完成

已成功只部署 demoGenerateSummary、demoReadSummary 与 innera-demo-encrypted-doctor Hosting。兩個Functions為ACTIVE，雲端DEMO_RACE_TEST_ENABLED=false，timeout均恢復60s，專用runtime service account不變。公開doctor HTML不存在race控制項；JS hard-disable且與本機測試版本一致。原15s helper保持false、正常runtime未接入。每日generation attempts仍1，lock expiresAt=0，本輪沒有額外provider呼叫。

本次首次CLI discovery10s逾時，沒有完成雲端更新；僅延長本機FUNCTIONS_DISCOVERY_TIMEOUT到30s重試成功，未改應用程式/雲端權限。未重新建立KMS、改IAM/App Check/Rules/indexes/正式Hosting，也未commit/push或遷移資料。正常流程本輪以fake-provider/UI驗證，不宣稱新增已登入醫师雲端E2E。Synthetic OpenAI demo驗收与收尾完成，production保持未切換。
