# 新 synthetic dailyRecords 加密 demo（2026-10-08）

僅 innera-demo。使用者已確認 Sleep / HealthEvent / Check-in / Medication 真實驗收完成；本輪不重做基礎設施。沿用原 KMS version1、runtime identity、custom IAM、App Check；不讀真實users資料、不遷移歷史dailyRecords、不改正式ClinicalShareService/Repository/reader，不執行AI或AI Summary。

## 現行 writer 盤點（A）

來源已唯讀檢查：DailyRecordRepository、daily_record_screen.dart新增頁與經期upsert、edit_record_page.dart、innera_ai_record_draft_service.dart confirmAndMerge、innera_ai_record_draft.dart AiSleepDraft、daily_record_history.dart經期更新、data_sync_diagnostics.dart上傳、test_data_generator.dart。其他dailyRecords引用（timeline/calendar/unified repositories/diary reflection等）為讀取或刪除入口，不以其reader推導新payload。

- 正式document ID通常DateHelper.toId / draft.dateKey，即yyyy-MM-dd；Repository save接受呼叫者提供id。date是當地日界Timestamp，不是獨立事件timestamp。Demo wire日期為UTC ISO-8601毫秒，新doc ID隨機，原id不外露。
- 新增頁direct patch：date、emotions[{name,value}]、symptoms[string]、stateChanges、symptomSectionCompleted、emotionSectionCompleted、stateSectionCompleted、savedAt、periodCycleLength；有情緒時overallMood平均。經期條件寫入isPeriod/periodStartId/periodEndId，另periodNextExpectedStart、periodArrivalDeltaDays。
- Repository隨後仍寫：date、emotions（Map或null）、stateChanges、完成旗標（可選）、bodyMeasurement/sleep（傳入才寫）、bodySymptoms、dailyActivities、medicines、periodData、moodScale、createdAt、updatedAt。新增頁傳moodScale=5及periodData；dailyActivities/medicines新頁不填，為null。它們並非純legacy-only頂層欄位，不能捏造非nullnested schema。
- periodData現行鍵：isPeriod、periodStartId、periodEndId、cycleLength、nextExpectedStart、arrivalDeltaDays（部分upsert僅前四項）。
- AI確認merge（只讀程式，本輪不執行）：date、moodScale=5、emotions列表、overallMood、symptoms/bodySymptoms、stateChanges、完成旗標、可選bodyMeasurement、sleep、updatedAt。保留既有10點資料時不覆寫其情緒。AI確認的日記文字寫diary，非dailyRecords頂層note/text。
- BodyMeasurement現行toJson：weightKg/bodyFatPercent/waistCm、measuredAt、measurementTiming、customMeasurementTime。
- AiSleepDraft新寫入鍵：sleepTime、wakeTime、finalWakeTime、quality、midWakeList、flags、naps；只有meaningful值merge，新空record仍可能sleep={}。
- 主新增/編輯頁睡眠與body量測現改寫到專用sleepRecords/bodyMeasurementRecords；不能把UI欄位一律當成新的dailyRecords欄位。
- 編輯頁直接patch情緒、症狀、stateChanges/旗標/savedAt，後續Repository呼叫未傳moodScale，預設10；因此moodScale10不是完全legacy-only。新增頁明確5；此不一致列為風險、不修改。
- 經期history更新仍寫isPeriod/periodStartId/periodEndId；不是legacy-only。
- Diagnostics仍可能從existing/local record複製date/emotions/symptoms/sleep，加uploadedFromLocal/uploadedAt；此屬資料修復/複製路徑，本輪不呼叫、不加入synthetic clinical payload。
- Test generator經repository寫測試情緒，再加isTestData/isDevSeedOwned/source/testGeneratedAt等測試metadata；本輪不使用該generator。
- 未在上述現行新writer找到dailyRecords頂層timestamp、healthStatus/overallHealth、note/text；不新增。助眠藥名稱/劑量在歷史sleep模型存在，但主新writer現存專用sleepRecords，不能為本demo捏造。

## Legacy-only 與保留相容（B）

確定reader compatibility：bodyMeasurement.measurementTiming的beforeBreakfast/afterMeal舊enum由reader映射other；helper讀emotion item的key/id別名及overall舊項；缺completion flag時由內容推導、缺moodScale時fallback10、缺date時從document ID補日期。

不能誤標為B：emotions Map、bodySymptoms、periodData、moodScale10仍被writer寫入。歷史sleep的estimatedSleepTime/nightAwakenings/tookHypnotic/hypnoticName/hypnoticDose/note等可被existing-map merge或diagnostics複製保留，不能宣稱所有writer都不會寫；本輪新synthetic只採已確認AiSleepDraft的新欄位。沒有製造legacy clinical payload fixture或做normalize/migration；僅memory boolean sentinel驗證未受影響。

## Demo payload與限制

只有兩筆固定新5點Map：一筆代表新增頁+Repository合併（emotions Map、經期欄位、空活動/medicines）；一筆代表AI確認writer shape（emotions列表、bodyMeasurement、sleep）。只构造Map，不import或執行AI service/Repository。日期、值均合成，不取production/歷史資料。

Validator對本輪選定的新5點subset做欄位白名單与型別/範圍限制。dailyActivities/medicines限null，naps限空array；不是production完整writer adapter，不自動接受未知nested/legacy shape。body測量旧enum、emotion key/id别名、頂層note/timestamp/healthStatus或10點fixture拒絕。

## 加密與獨立授權

- demoEncryptedShares/{uid}/clinics/{clinicId}/dailyRecords/{randomId}
- 獨立scope：同root的scopes/dailyRecords
- AAD type=dailyRecords，其他綁定environment/uid/clinicId/documentId/schemaVersion/epoch/keyVersion/algorithm/wrappingAlgorithm不變。
- 新DEK32/new nonce12、AES256GCM/tag16、RSA3072 OAEP SHA256；原demo-sleep-clinic KMS version1，不新增/輪替/擴權。
- Envelope9欄，無臨床明文；scope獨立active/dailyRecordSharingEnabled/epoch/consentVersion。
- 新callable demoDailyRecordContext/demoPublishDailyRecords/demoReadDailyRecords/demoRevokeDailyRecords，原enforceAppCheck與verifyIdToken(...,true) wrapper及專用SA。
- 撤銷只刪demo dailyRecords與其scope summary=current，active=false/epoch增加；stale upload拒絕。KMS前/回傳前重新驗證，audit失敗不回傳；其他四scope保留。
- 醫師點患者自動讀所有scope，明文只短暫記憶體/DOM，沿用10秒重驗/30秒到期/關頁登出切患者清除、晚到結果丟棄。已釋出內容不能追溯收回。

## 本機驗證

43 backend/interop、1實際Firestore emulator、12醫師UI，共56項通過；Dart analyze無問題、患者release Web build成功。新增legacy-access guard：runtime doc/collection若碰users/即失敗；MemoryDb historical sentinel前後一致。正式writer/reader13份檔案SHA256前後比對完全一致。測試只使用loopback emulator/memory，未寫真實歷史collection。

## 修改檔案

functions_encrypted_demo/{protocol,service,index}.js；test/{endpoints,interop,emulator}.test.js；新增test/daily-record-fixture.js、daily-records.test.js。lib/clinic/demo_sleep_envelope.dart、lib/main_encrypted_sleep_demo.dart；新增lib/clinic/demo_daily_record_share_client.dart。

醫師端encrypted-sleep.demo.html、js/encrypted-sleep-demo.js；新增scripts/encrypted-daily-record-demo.test.js。本文件。

## 雲端驗收

已成功只部署encrypted-sleep-demo codebase與兩個專用Hosting。四個dailyRecords callable均ACTIVE、専用SA正確。缺Auth/AppCheck空請求均401。已在真實瀏覽器確認患者新synthetic分享/撤銷入口與醫師demo更新。

掃描32筆新函式log，敏感標記0；未涵蓋成功解密。核對時demoEncryptedShares假患者dailyRecords為0筆，不能以空集合宣稱密文分享驗收完成。沒有查詢原users集合。真正分享/KMS解密/撤銷/授權負向/成功後storage/log/audit檢查，須既有假帳號人工登入；不能以mock、空集合或401代替。不得重設既有密碼。

## Production切換前風險

ClinicalShareService.syncDailyRecords仍會解密users資料並將_toClinicalDailyRecordMap明文寫clinicalShares。需正式切換設計與授權驗收后才改，本輪保持不變。既有歷史明文share/摘要不會因demo擴充而自動消失。

需先釐清多writer的Map/列表與5/10量表不一致、date日界與時區、savedAt/createdAt/updatedAt semantics、活動/medicines/naps與歷史sleep的完整版本契約、8KiB envelope ciphertext上限與實際payload大小。Demo subset不能直接套用所有歷史紀錄；任何遷移需另行核准。

AI Summary不啟用。先完成dailyRecords真實验收，再確認摘要範圍、解密執行邊界、外部服務是否允許/資料保留、摘要加密與scope撤銷；本輪不決定外部服務。

原Git修改保留，沒有commit/push。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
