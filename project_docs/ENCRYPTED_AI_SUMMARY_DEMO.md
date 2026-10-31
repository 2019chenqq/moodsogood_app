# Encrypted AI Summary Demo

本輪只使用 innera-demo 的五種已驗證 synthetic encrypted source。沿用既有 KMS version 1、runtime service account、IAM 與 App Check；沒有外部 AI、正式資料、歷史遷移、正式 clinicalShares 或 production 流程切換。

## 正式流程唯讀盤點

- functions/src/clinic/clinical_summary.js：generateClinicalSummary 從 clinicalShares/{uid}/clinics/{clinicId} 讀 healthEvents（timestamp、emotions、symptoms、stateChanges、context、note）、dailyCheckIns（date、overallMood、healthStatus、noSpecialEvent）、sleepRecords（date、durationMinutes）。依 startDate 到 now 查詢，再形成睡眠統計與醫療明文 JSON prompt，送 OpenAI chat.completions。
- 正式臨床輸出 domains 為 drive、cognition、mood、behavior、sleep；每個 domain 為 null 或 status/summary/sourceType。另有 patternSummary、importantEvents（date/category/title/summary）。寫到 clinicalShares/.../aiSummaries/current，包含 periodStart/End/Days、generatedAt、model、summaryVersion、sourceCounts。這個 callable 沒有歷史摘要寫入，也沒有讀 diary/journal；status 是 domain 狀態，沒有獨立頂層生成狀態欄位。
- 該檔 console.log(JSON.stringify(result)) 明確輸出摘要明文。醫療端 js/firebase-service.js 直接讀 current 明文，並透過 callable 生成摘要。本輪不修改這些正式檔案。
- App 回診摘要是另一條流程：FollowUpAiDataAggregator 經既有 repositories 讀 dailyRecords、healthEvents、dailyCheckIns、sleepRecords、bodyMeasurements、medications、medAdjustments、medicationSubjectiveResponses 等（睡眠/量測兼容 dailyRecords），並讀回診資訊與健康資料。FollowUpSummaryPage 可在本次另外同意並選取後，加入 users/{uid}/diary 的 diaryContext。
- FollowUpAiService 將 followUpAiV1、討論內容與補問回答傳 InneraAiService → generateInneraAiChat → functions/src/chat/handler.js → OpenAI。主要輸出 keyChanges、discussionItems、userSharedNotes、dataLimitations、diaryHighlights；也組裝 App 產生的睡眠、用藥、共現與量測資訊。此處不是臨床五個 domains 的同一份 schema。
- FollowUpService 的 users/{uid}/followUpWorkspace/current 與 followUpSummaries/{randomId} 使用 HealthDataEncryptionService 保存；歷史摘要有期間、createdAt/updatedAt/confirmedAt、aiOutput（generatedAt）等。該加密服務仍將 createdAt/updatedAt 作運作欄位保留在 envelope 外。不能把這條 App 加密歷史流程誤說為臨床 current 的明文保存。
- FollowUpAiService._debugParseFailure 在 debug mode 會輸出 response preview（最多 500 字）；正式 chat handler 的錯誤處理會記 SDK error.message 等，需另外審查敏感錯誤內容。沒有據此宣稱所有正式 prompt 都會被 log，但 clinical_summary 的 result log 與 App debug preview 風險已由程式證實。

## Demo 最低 schema 與信任邊界

來源 whitelist：sleepRecords、healthEvents、checkIns、medications、dailyRecords。服務只讀 demoEncryptedShares 下的這五種集合；clinics、clinicStaff、demoEncryptedFixtures、inneraPatients 只作 synthetic 關係/權限確認。不讀 users、正式 clinicalShares、diary 或舊資料。

五種來源逐份 KMS unwrap → memory-only 驗證/解密 → normalize 數量與數值 → deterministic-demo-v1 規則摘要 → fresh AES-256-GCM DEK/nonce + RSA-3072-OAEP-SHA256 wrapped DEK → 保存。生成 API 只回 available/epoch，不回明文；醫師 read API 另外確認授權後自動解密。

摘要 payload：schemaVersion=1、synthetic=true、model=deterministic-demo-v1、generatedAt、sourcePeriod(start/end)、sourceVersions（五種 scope 的 active/epoch/consentVersion）、domains（五種 type，各為 null 或 recordCount/summary）。未授權來源既不讀文件也不解密，對應 domain=null。不作診斷、因果或治療建議；同 normalized input、版本和生成時間會得到相同內容。

期間、時間、來源數量、domain 内容與來源授權引用都可能透露健康資料/活動，所以全部放進 ciphertext。Firestore summary 文件只有既有九個 envelope 欄位：schemaVersion、algorithm、wrappingAlgorithm、keyVersion、epoch、nonce、ciphertext、authenticationTag、wrappedDataKey。type/path 与 envelope 版本仍是路由所需資訊，不能宣稱所有存取模式都被隱藏。

摘要路徑：demoEncryptedShares/{uid}/clinics/{clinicId}/aiSummaries/current。
獨立患者同意 scope：同一 clinic 根目錄下 scopes/aiSummary。
AAD 固定 JSON array 綁 innera-demo、uid、clinicId、aiSummaries、current、schemaVersion=1、summary epoch、keyVersion、AES-256-GCM、RSA-OAEP-3072-SHA256。

## 有效性與競態

- patient consent 與自身 revoke 都遞增 summary epoch、刪 current。只有有效醫師能明確 generate/read；每次成功生成也遞增 summary epoch。患者同意不會生成，也不會復活旧摘要。
- 五種既有 source 的 share/revoke transaction 同步刪除根目錄 aiSummaries/current，並記低敏 invalidated audit；不改其他 source consent/文件。source epoch 單調遞增，重新分享後必須明確生成。
- 生成起始 transaction 拍下五種 active/epoch/consentVersion；每份來源解密前、save transaction、回傳前都比較完整 vector 和 summary epoch，重新確認 doctor/clinic/link/fixture。inactive 也保留版本引用，避免後來啟用繞過舊摘要檢查。
- summary read 在 KMS 前、解密後、最後 transaction 比較來源 vector、摘要 epoch 與 current 是否仍存在。Audit failure 不釋出明文。SDK error 不原樣回傳或 log。
- summary checkpoints 重新 verifyIdToken(checkRevoked=true)，處理 disabled/revoked Auth。生成保存後、回傳前失敗時，只清除這次生成的 envelope，避免刪掉另一次新摘要。
- 有效性以最後授權 transaction 為線性化點；已釋出的明文不能收回。醫療端每 10 秒重查、最長 30 秒到期，切換/關閉/隱藏/登出清除記憶體視圖；沒有默默重新生成。JS immutable strings/GC 不能保證物理 RAM 立即覆寫；DEK 與 plaintext Buffer 主動清零。
- 無新增 authorization-change trigger；doctor/clinic/link 失效時每次後端讀取都拒絕。失效期間尚未讀取、之後又恢復相同關係的永久失效策略，仍需正式方案使用關係授權 revision 或事件 invalidation，不能宣稱本 demo 已觀測所有過去變更。

## 入口與測試

患者：五種假資料分享 → 另外勾選同意模擬摘要；可只撤銷摘要而保留五種分享。
醫師：點患者自動讀 current；「產生／更新模擬摘要」為明確生成操作，沒有解密按鈕。

本機涵蓋五來源加密互通/摘要 round-trip、AAD 搬移/篡改、有效與無效權限、inactive source 不解密、五 scope revoke/re-share、不復活、來源與摘要解密/保存競態、Auth revocation、audit failure、無正式路徑存取、九欄位保存、無應用 log/外部 AI、Rules 直接讀寫拒絕與五類 regression。醫師 UI mock 阻止 Local/Session/IndexedDB/Cache 操作與 log，驗證自動讀取、到期/登出清除及不自動生成。

tool/encrypted-demo-storage-audit.js 是兩個 demo origin 專用唯讀驗收工具；只在點按時掃描四種 storage，畫面只回欄位/摘要標記是否出現。Auth/App Check token 可有 SDK 自己的儲存，工具不回傳值/名稱或 credentials。此標記掃描不是任意明文字串的完整 DLP 證明。Build 中注入此工具；正式 web/index.html 不變。

## 雲端驗收

本機測試後只部署 encrypted-sleep-demo codebase 与兩個専用 Hosting。當輪實測結果應在驗收後更新，不能用 unit/mock/emulator、匿名 401 或空集合宣稱真實 KMS 摘要分享驗收完成。

2026-10-08 當輪進度：已通過 75 項後端/互通、1 項實際 Firestore emulator 整合與 Rules、15 項醫師 UI/診斷測試（共 91），demo Dart analyze 無問題，Flutter release build 成功。完整後端/互通測試也在部署後重跑通過。

已成功部署 encrypted-sleep-demo 全 25 個 callable（原 21 個只更新本轮 source invalidation，新增 demoSummaryConsent、demoRevokeSummary、demoGenerateSummary、demoReadSummary）與 innera-demo-encrypted-patient / innera-demo-encrypted-doctor 兩個専用 Hosting。未部署 Rules、索引或正式入口。四個新函式 ACTIVE，runtime identity 正確；匿名空請求全部 401，這不代表有效 App Check 的正向流程已通過。

假患者五種來源及 aiSummaries 集合目前都是 0 筆。新函式 32 筆部署/匿名拒絕 log 的敏感標記為 0；兩個實際 origin 的 Local/Session/IndexedDB/Cache 標記掃描未發現醫療欄位，屬尚未登入/生成的 baseline。真正生成、KMS 摘要解密、來源撤銷/重新分享不復活及成功後 storage/log/audit 檢查，仍待既有假帳號人工登入；未重設或索取密碼。兩個 Codex 瀏覽器分頁已保留作驗收交接。

新增摘要服務/validator/mock：functions_encrypted_demo/summary-service.js、summary-schema.js；擴充 protocol/service/index；測試增加 summary.test.js 並擴充 endpoints/interop/emulator。患者增加 demo_summary_share_client.dart、main_encrypted_sleep_demo.dart 同意/撤銷，envelope 增加摘要 AAD 互通 type（患者 UI 不生成摘要）。醫師 encrypted-sleep.demo.html、encrypted-sleep-demo.js 增加自動讀與明確生成；增加 encrypted-summary-demo.test.js。storage 工具 canonical 檔案在 App tool/encrypted-demo-storage-audit.js，同步副本在醫師 js/encrypted-demo-storage-audit.js；release 只在 demo build 注入患者入口。

Git：App 原 7 個 tracked 修改（82 insertions / 85 deletions）保留，本輪只修改/新增原本 untracked demo 範圍。醫師端原有 untracked 檔案保留。沒有切換 branch、reset、commit、push；沒有改 production、KMS、runtime IAM、App Check 或正式 AI 流程。

驗收順序：五種 synthetic 分享、獨立摘要同意、醫師明確生成、檢查 envelope 欄位、醫師重新點患者自動讀、HealthEvent revoke → current消失/後續拒絕、HealthEvent re-share → 舊摘要不復活、明確重生成功、摘要自身 revoke → source不變/summary拒絕；成功讀取後檢查 Functions logs、audit 與兩個origin storage。

正式 AI provider 下一階段需另外決定患者同意的範圍、provider/地區、保留/訓練政策、資料最小化、日記是否可納入、prompt/response tracing 關閉、供應商 error/log 過濾、撤銷期間跨 API race/cancellation、摘要版本/授權 revision、保存/刪除政策與臨床品質責任。本輪沒有做這些外部選擇。

## 2026-10-08 雲端讀取問題排查

使用者完成五種 synthetic 分享與摘要同意/生成後，雲端記錄顯示 demoGenerateSummary HTTP 200，但 18 秒後 demoReadSummary HTTP 400。REST 唯讀核對 current envelope 九欄位有效、KMS version 正確，current 與 aiSummary scope epoch 相符且 active。沒有讀取或輸出摘要明文。此證據確認生成/保存成功，尚不能宣稱摘要讀取成功。

將 sourceVersions 比對從 JSON.stringify 字串比較改為逐項 active/epoch/consentVersion 比較，避免語義相同但欄位排序不同誤判；新增加密 payload 欄位反序回歸測試。read 失敗另記固定 stage action（session/authorization/envelope/beforeDecrypt/decrypt/sourceVersions/finalSession/finalAuthorization）與既有 hashed actor/subject/result/time 六欄位，不記 payload、原始錯誤或 keys。這是診斷與防禦修正；尚未由新成功請求證明原 HTTP 400 的根因。

醫師 UI 在生成期間暫停自動 refresh，避免同時重開患者取消本次讀取；恢復後仍只讀、不自動生成。離開/隱藏頁面仍清除明文，但提示改為重新點患者；讀取失敗只顯示 allowlisted functions code，不輸出 SDK message。保留所有授權、Auth/App Check、來源版本與撤銷防護。只部署 demoReadSummary 與 demo 醫師 Hosting；不用重新分享來源或再次同意摘要。

更新已成功只部署 demoReadSummary 與 innera-demo-encrypted-doctor Hosting（患者入口與其他 24 個 Functions 未部署）。使用者依指示不重新分享/同意，直接再次點患者並回報有資料。最新摘要讀取 HTTP 200（兩次已核對），summary.read 成功稽核 3 筆；成功讀取的 16 筆 log 敏感標記 0。既有密文可被新讀取函式正常授權解密，沒有更改 KMS/IAM 或放寬檢查。新回歸測試為 76 項後端/互通、16 項醫師端通過，emulator 本次未重跑。

仍待這次雲端流程的 HealthEvent revoke → 舊摘要失效 → re-share 不復活 → 明確 regenerate，以及摘要自身 revoke 保留原始資料與成功後 browser storage 檢查；不可將已成功讀取誤報為所有撤銷驗收已完成。

HealthEvent 來源撤銷雲端驗收已確認：使用者回報醫師摘要無法讀取；唯讀 metadata 顯示 healthEvents scope active=false、epoch=6，aiSummaries/current 不存在；撤銷後 demoReadSummary 持續 HTTP 400，撤銷前為 HTTP 200。重新分享不復活、明確重生、摘要自身撤銷與成功後 storage 檢查仍待驗收。


## 2026-10-08 部分來源自動更新（取代前述「明確生成才恢復」行為）

本輪僅修改 encrypted demo。demoReadSummary 先做嚴格授權讀取；只有明確標記的 missing/stale 摘要可觸發一次 generate，再獨立授權 read。permission/Auth/App Check/未知 KMS version/密文損壞/競態失敗不觸發自動修復，也沒有無限重試。摘要同意仍獨立且必須有效，至少一個來源 active 才生成。此自動更新在有效醫師讀取時執行，沒有增加背景觸發器或 IAM。

新版 encrypted payload schemaVersion=2：synthetic、model、generatedAt、sourcePeriod、sources、domains。sources 只含當下 active 的實際納入來源，各值為 {epoch, consentVersion}；domains 只有相同來源鍵，不保留 inactive 的 null 欄位或 sourceVersions。來源 active 但沒有文件時記錄 0 筆。既有外層 envelope schemaVersion=1/AAD/九欄位不變，provenance 全部位於 ciphertext。舊 payload v1 僅能被 validator 辨識，嚴格讀取判為 stale，再依現在授權生成 v2，不回傳舊摘要，未遷移歷史資料。

內部完整五來源 snapshot 只在記憶體保存，包含 inactive epoch 作競態防護。來源 share/revoke 仍原子刪除 current；解密前、保存前、回傳前比對 snapshot，讀取還檢查 provenance 是否精確等於當下 active 來源及 epoch/consentVersion。來源重新分享使 B 失效，新 C 才納入新 epoch；不復活 A 或 B。醫師 UI 自動讀取新版，提示「摘要已依目前授權資料更新」，只列實際涵蓋內容，不列缺少或撤銷的類型。

本輪本機：81 項後端/六型 Dart 互通/五來源 regression、1 項實際 Firestore emulator transaction/Rules、16 項醫師 UI/storage/log 測試通過；demo Dart analyze 無問題。新增 A/B/C、Medication 撤銷、單一來源/全撤銷、strict stale 拒絕、自動生成競態、損壞/未知版本/缺 consent 不自動修復測試。Java 21 loopback 啟動問題以本機短 socket 暫存路徑排除，未改雲端設定。

修改 summary-schema.js、summary-service.js、test/summary.test.js、test/emulator.test.js；醫師 encrypted-sleep.demo.html、js/encrypted-sleep-demo.js、scripts/encrypted-summary-demo.test.js；storage marker 工具增加 sources 辨識並同步醫師副本。未改正式摘要或來源寫入流程、KMS/IAM/App Check。部署目標限定 demoReadSummary、demoGenerateSummary 與 innera-demo-encrypted-doctor Hosting；實際雲端結果待後續驗收補記，不能以本機測試代替。

部署結果：demoReadSummary、demoGenerateSummary 與 innera-demo-encrypted-doctor Hosting 成功，兩個函式 ACTIVE 且 runtime identity 未變。五種來源共 12 份文件與 current 摘要均只有九欄位 envelope，最近 50 筆 audit 均符合既定六欄位；部署後目前僅 1 筆基礎 log，敏感標記 0，尚未取得新版有效醫師請求，不能宣稱 A/B/C 真實雲端驗收完成。已請使用者以既有測試密碼登入並先確認五來源 A。追加 legacy v1 → v2 自動更新測試通過，摘要測試共 38 項；本輪總計 99 項已通過（完整後端 81 項加追加測試 1 項、emulator 1 項、醫師端 16 項）。成功讀取後的 browser storage 檢查仍待人工操作。原 7 個 tracked 修改維持 82 insertions / 85 deletions，無 commit/push/production 操作。

新版雲端驗收 A：使用者確認點患者後自動出現摘要 A；innera-demo 最近 15 分鐘 demoReadSummary 有 5 次 HTTP 200，21 筆 log 的敏感標記為 0。已請使用者只撤銷 HealthEvent 再點患者，驗證四來源 B 自動生成；B/C 與成功後 storage 仍待回覆，尚未宣稱全流程完成。

新版雲端驗收 B：使用者回報摘要 B 生成成功；唯讀核對 HealthEvent scope active=false、epoch=9，current 與 aiSummary scope epoch=10，摘要同意仍有效，current 僅九個 envelope 欄位。最近 10 分鐘 demoReadSummary 11 次 HTTP 200，39 筆 log 的敏感標記 0。已請使用者確認 B 不含 HealthEvent，重新分享後驗證 C 並執行兩頁 storage 掃描；這些項目仍待回覆。

雲端驗收 C：使用者確認 B/C 需關閉患者再重開才顯示，不能宣稱原地自動更新已通過。唯讀確認 HealthEvent active=true、epoch=10，current summary epoch=11，僅九 envelope 欄位；使用者另回報患者/醫師 storage 掃描皆未發現醫療欄位（標記掃描範圍）。排查醫師 visibilitychange 原先 close 會取消 selected，改為隱藏時清空所有明文視圖、作廢遲到回應，但只保留記憶體 routing selection；返回可見且已登入時重新執行六類授權讀取。手動關閉/登出/pagehide 仍完整取消 selection。生成完成後重啟目前視圖的輪詢，避免分頁切換中止後沒有輪詢。更新的 16 項醫師端測試通過（涵蓋 hide-clear/return-read、close/logout 不自動重開、storage/log 禁止）。只部署 innera-demo-encrypted-doctor Hosting 成功，未部署 Functions 或正式入口。已請使用者載入修正並驗證直接返回分頁自動更新，尚待回覆。

分頁返回自動更新雲端驗收完成：使用者回報修正後成功自行更新，不需關閉患者再開。唯讀確認 HealthEvent active=false、epoch=13，current summary epoch=14，僅九欄位 envelope。最近 15 分鐘 demoReadSummary 11 次 HTTP 200、1 次 HTTP 409（版本/競態中止狀態），37 筆 log 敏感標記 0；不將衝突請求當成功，後續新版已成功顯示。此前 A、B、C、兩頁 storage 標記掃描皆已有使用者回報；provenance 新 epoch 精確比對與 race/單一/全撤銷等細節由本機測試證明，不宣稱另行下載或雲端獨立解密檢查 provenance。原 tracked 修改仍為 7 檔、82 insertions / 85 deletions。未 commit/push/production 操作，未接第三方 AI。可進入真實 provider 的設計評估，串接仍需另行確認。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
