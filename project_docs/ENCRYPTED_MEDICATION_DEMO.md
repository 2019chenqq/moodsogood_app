# Medication 加密 demo（2026-10-08）

僅 innera-demo；使用者已確認 Sleep / HealthEvent / Check-in 真實雲端驗收完成，本輪不重做。沿用既有 KMS version 1、runtime identity、custom IAM 與 App Check；不碰 production / clinicalShares / migration / dailyRecords / AI Summary。

## 實際 schema 與來源

正式 medication 是 Map，沒有独立 Medication class。來源：lib/meds/add_medication_page.dart medicationData、edit_medication_page.dart medicationData、medication_local_db.dart _toCloudMedication / _fromCloud、medication_actions.dart、medication_home_page.dart、record_adjustment_page.dart。原路徑 users/{uid}/medications/{documentId}；id 由文件路徑提供，雲端原文 Map 去掉 id。

既有 clinical_share_service.dart 投影只保留部分字段；本 demo 使用 App 完整新增／編輯 Map，不改該正式投影。

Payload 必須欄位（皆正式寫入欄位）：
name、dose、dosePerUnit、pillCount、concentrationMg、concentrationMl、intakeMl、unit、type、drugForm、compoundType、drugConcentration、packageAmount、packageUnit、ingredientLines、intervalDays、scheduleType、scheduleIntervalDays、scheduleAnchorDate、weekdays、times、purposes、note、startDate、isActive、bodySymptoms、purposeOther、createdAt、updatedAt、lastChangeAt。

可選：nameEn（正式流程有值才寫）、resumedAt（恢復使用流程寫入）。日期統一 UTC ISO-8601 毫秒字串；可空日期保持 null。新 envelope ID 為随机值，不保存原始 id / medicationId；UID/clinic 由 path/AAD 綁定。

- name / nameEn 是名稱；ingredientLines 是成分文字字串陣列，沒有獨立 genericName / brandName。clinical 讀取的 brandName 等是相容 fallback，不是新增流程標準字段。
- 劑量 dose / dosePerUnit / pillCount；unit，液體 concentrationMg / concentrationMl / intakeMl。
- type 為 tablet / injection / drops；drugForm 為文字；其他成分、濃度與包裝資訊如上。
- scheduleType 為 daily / intervalDays / weekdays；scheduleIntervalDays / scheduleAnchorDate / weekdays 對應排程。
- times 包含早上、中午、下午、晚上、睡前、需要時；PRN 以「需要時」表示，沒有獨立 prn flag。
- injection 的 intervalDays 為注射間隔，未找到獨立 LAI / 長效針旗標。
- startDate、isActive、lastChangeAt；沒有獨立 stopDate / endDate / discontinued 狀態字串，停用使用 isActive=false 與變更時間。
- LocalDB 另相容轉換 lastChangedAt，但未找到該欄位實際寫入，未加入 payload。

患者僅構造三筆固定 synthetic Map：口服、需要時口服、注射，不匯入 medication repository 或真正新增藥物 UI，不讀取使用者 medication collection。

## 加密、授權與撤銷

- Envelopes：demoEncryptedShares/{uid}/clinics/{clinicId}/medications/{randomId}
- Scope：demoEncryptedShares/{uid}/clinics/{clinicId}/scopes/medications
- AAD type=medications，綁定environment、uid、clinicId、documentId、schemaVersion、epoch、keyVersion、algorithm、wrappingAlgorithm。
- 每文件獨立32-byte DEK、新12-byte nonce、AES-256-GCM/16-byte tag、RSA-OAEP-3072-SHA256；沿用 demo-sleep-clinic version 1。
- Envelope固定9欄，不保存 clinical payload。獨立active/medicationSharingEnabled/epoch/consentVersion。
- 撤銷刪除密文及該 scope aiSummaries/current，active=false、epoch增加；舊epoch publish拒絕。不產生摘要。
- 權限由原 server-side transaction 驗證有效doctor、active staff/clinic、同院所、patient link/synthetic fixture、有效scope/epoch。每次KMS前與釋出前再查，audit失敗不釋出明文。
- 新callable：demoMedicationContext、demoPublishMedications、demoReadMedications、demoRevokeMedications，enforceAppCheck=true、verifyIdToken(...,true)，專用SA不变。
- 醫師點患者自動讀取各scope，無解密按鈕；只存短暫記憶體/DOM，沿用10秒重驗、30秒到期、關閉/離頁/登出/切患者清除及晚到回應丟棄。已釋出的資料不能追溯收回。

## 本機測試

34 backend/interop + 1實際Firestore emulator + 10醫師UI，共45項通過；Dart analyze無問題，患者release Web build成功。

涵蓋schema變體（PRN、注射、液體、排程、停用）、Node/Dart interop、AAD跨type/identity/document/epoch/algorithm/schema/key/tag/ciphertext搬移串改、正常分享自動讀取、非doctor/inactive/cross-clinic/clinic/patient link/未同意/AppCheck拒絕、disabled/revoked Auth wrapper、撤銷競態/stale upload、Rules直接讀寫拒絕、audit欄位、UI不呼叫persistent storage/不log/晚到明文丟棄。Medication revoke保留另三scope的狀態及可讀性。

## 修改檔案

App：functions_encrypted_demo/protocol.js、service.js、index.js；test/endpoints.test.js、interop.test.js、emulator.test.js；新增test/medication-fixture.js、medications.test.js。lib/clinic/demo_sleep_envelope.dart、main_encrypted_sleep_demo.dart；新增lib/clinic/demo_medication_share_client.dart。

Clinician：encrypted-sleep.demo.html、js/encrypted-sleep-demo.js；新增scripts/encrypted-medication-demo.test.js。

## 雲端驗收

Demo-only 部署已成功：encrypted-sleep-demo codebase，專用 Hosting innera-demo-encrypted-patient / innera-demo-encrypted-doctor。四個 Medication callable 都為 ACTIVE 且使用 demo-encrypted-share@innera-demo.iam.gserviceaccount.com。缺 Auth / App Check 空請求全部401。患者與醫師部署後頁面已檢查，Medication consent / share / revoke入口存在。

掃描32筆 Medication Functions log，敏感標記0；尚未成功解密，因此不能推論成功解密後亦無明文。核對時四種資料集合均0筆；不以空集合 envelopeOnly=true 宣稱成功分享後已驗收。真正Medication分享、KMS解密、拒絕/撤銷、三種scope雲端regression及成功解密後Firestore/log/audit/browser storage仍待人工登入驗證；本機結果不代替真實驗收。使用既有synthetic帳號、不重設密碼、不輸出tokens/credentials。

原有Git修改保留，沒有commit/push。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
