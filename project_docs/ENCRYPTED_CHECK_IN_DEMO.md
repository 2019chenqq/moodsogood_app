# Check-in 加密 demo（2026-10-08）

僅 innera-demo，沿用已完成的 KMS version 1、專用 runtime identity、custom IAM 與 App Check。未更動 production、正式 clinicalShares 或既有資料，未啟用 Medication / dailyRecords / AI Summary。

## 實際模型

來源：lib/models/daily_check_in.dart、lib/daily/daily_check_in_service.dart、lib/clinic/clinical_share_service.dart 的 syncDailyCheckIns。正式來源 documents 為 users/{uid}/dailyCheckIns/{yyyy-MM-dd}。

Payload 六欄：date、overallMood（整數1–5）、healthStatus（整數1–5）、noSpecialEvent（boolean）、createdAt、updatedAt。日期轉為 UTC ISO-8601 毫秒字串；createdAt / updatedAt 可為 null。沒有另外加入 note / symptom 等字段。Demo 由 DailyCheckIn 模型建立兩筆固定假資料，不讀取 repository。

## Scope 與加密

- Envelopes：demoEncryptedShares/{uid}/clinics/{clinicId}/checkIns/{randomId}
- 授權：demoEncryptedShares/{uid}/clinics/{clinicId}/scopes/checkIns
- 狀態：active、checkInSharingEnabled、epoch、consentVersion；分享需患者明確同意。
- AAD type 為 checkIns，綁定 environment、uid、clinicId、documentId、schemaVersion、epoch、keyVersion、algorithm、wrappingAlgorithm。
- 每文件新32-byte DEK、新12-byte nonce、AES-256-GCM、16-byte tag、RSA-OAEP-3072-SHA256。沿用既有 demo-sleep-clinic key version 1，不新增金鑰或權限。
- Envelope 固定9欄；不保存模型明文。撤銷刪除 checkIns 文件與該 scope 的 aiSummaries/current，active=false、epoch 增加。Sleep / HealthEvent scope 不受影響。
- 每次解密前及回傳前交易重查授權；稽核失敗不釋出明文。已釋出到醫師畫面的資料無法追溯收回；沿用10秒重驗、30秒到期、關頁／登出／切患者清除。

新增 callable：demoCheckInContext、demoPublishCheckIns、demoReadCheckIns、demoRevokeCheckIns。全部沿用 enforceAppCheck 與 verifyIdToken(..., true) / 專用 service account wrapper。醫师選患者後自動讀取三種資料，各自清除或拒絕，沒有解密按鈕。

## 本機驗證

26項 backend / Dart-Node interop、1項實際 Firestore emulator、8項醫師 UI 測試，共35項通過。Dart analyze 無問題、患者 release web build 成功。涵蓋AAD跨type、identity/doc/epoch/tag/schema/algorithm串改、權限與患者關聯、disabled/revoked Auth wrapper、撤銷競態與stale upload、Rules直接讀寫拒絕、checkIn撤銷保留sleep/health、稽核欄位、UI不呼叫持久storage、無application log以及晚到明文丟棄。

## 雲端驗收

已成功僅部署 encrypted-sleep-demo codebase 與兩個專用 Hosting（innera-demo-encrypted-patient / innera-demo-encrypted-doctor）。四個 Check-in callable 為 ACTIVE、identity 正確，缺 Auth / App Check 的四項請求均為401。掃描32筆新函式log，敏感標記0筆；尚未涵蓋成功解密。核對時三個 demo 集合均為0筆，因此不能以空集合宣稱已完成分享後密文驗收。真正 Check-in 分享／KMS 解密／撤銷，以及成功解密後 browser storage / log 查核尚待既有 synthetic 帳號人工登入。不能用本機 mock 或未登入401代替真實雲端驗收。不重設既有測試密碼。

沒有 commit / push，保留原有 Git 修改。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
