# 醫療分享加密：第一階段（2026-10-06）

本階段是本機可測試的隔離 demo 實作，尚未部署，也沒有建立 KMS、帳號或其他雲端資源。只處理內建假睡眠資料。正式 App 分享入口、正式 Functions、既有 clinicalShares、既有 demo Functions 與他人的修改均未改動。

## 給使用者看的流程

1. 測試患者登入獨立 Flutter 入口，勾選同意，按「同意並分享」。
2. 手機／瀏覽器本機加密三筆固定假睡眠紀錄，伺服器只收到密文。
3. 測試醫師登入獨立醫療端入口，點選患者，資料自動出現，不用操作解密。
4. 患者按撤銷後，後續讀取與解密被拒絕，睡眠密文及 current 摘要被刪除，摘要有效狀態也被清除。
5. 已經顯示的頁面每 10 秒重新確認／讀取；離開分頁、關閉患者或登出立即清除。單次請求起算 30 秒清除，即使請求卡住也不保留舊內容。

已送出的回應、截圖、外部另存資料不能收回。撤銷的保證是交易完成後的新授權請求被拒絕；解密中途撤銷會在回傳前再檢查，丟棄結果。畫面不是遠端抹除工具。

## 本機入口與隔離方式

- 患者：`lib/main_encrypted_sleep_demo.dart`。不 import 正式 firebase_options，也不讀個人健康集合。僅公開設定透過 dart-define 傳入。
- 醫師：另一專案 `D:/QQ_Web/Innera_clinician/encrypted-sleep.demo.html`。獨立入口，不載入舊的患者假資料、明文同步或摘要程式。
- 函式：`functions_encrypted_demo/`，獨立 codebase `encrypted-sleep-demo`。
- 設定：`firebase.encrypted-demo.json`；它不是現有 demo 部署設定，不會自動加入既有部署。
- 資料：`demoEncryptedShares/{uid}/clinics/{clinicId}/sleepRecords/{randomId}`。
- 假患者登記：`demoEncryptedFixtures/{uid}`，只有管理服務可建立。
- 稽核：`demoEncryptedAudit/{randomId}`，記動作、時間、結果及 actor/subject 的領域分離 SHA-256 參照，不記原始 UID、patientId、姓名、token、醫療內容或密文。

保留新路徑是為了避免影響既有 clinicalShares 明文流程、他人的 demo 工作與正式資料；下一階段才討論如何接回正式入口，不能把此版本視為已完成全站加密。

目前 firestore.demo.rules 的預設拒絕已涵蓋上述三種新路徑，所有前端（含患者、doctor、admin）都不能直接讀寫。只能走有 App Check 與授權檢查的 callable。沒有為了試作放寬 Rules。

`firestore.encrypted-demo.indexes.json` 保留建立當下既有索引，並對密文／wrapped key／tag／nonce 加入免索引設定。未部署；後續部署前需重新比較最新的共用索引，避免覆蓋之後新增的索引。

## 加密與授權協定

- 每份文件、每次分享使用新的 32-byte DEK 與 12-byte nonce，AES-256-GCM，16-byte tag 分開保存。
- 院所 RSA-3072 公鑰使用 OAEP SHA-256 / MGF1 SHA-256 / 空 label 包裝 DEK。
- 私鑰只在 Cloud KMS。部署程式沒有本機私鑰、私鑰環境變數或秘密檔案 fallback。
- AAD 是 UTF-8 JSON 陣列：`["innera-demo", uid, clinicId, "sleepRecords", documentId, 1, epoch, keyVersion, "AES-256-GCM", "RSA-OAEP-3072-SHA256"]`。
- 文件欄位白名單：schemaVersion、algorithm、wrappingAlgorithm、keyVersion、epoch、nonce、ciphertext、authenticationTag、wrappedDataKey。
- 日期、睡眠時間、品質、狀況全部在密文內。隨機文件 ID 不暴露日期。UID 路徑仍是可關聯識別，不宣稱匿名。
- KMS key version 必須屬於 innera-demo；不同院所不可共用同一 KMS key。writeVersion 只准新寫入；readVersions 可保留舊版供讀取。停用舊版本會安全拒絕，無明文 fallback。
- callable 強制 App Check；另驗證 ID token 未撤銷／帳號未停用。服務檢查 active doctor、同院所、院所 active、假患者登記、patient UID 綁定與授權 epoch。
- 每次 KMS 操作前，以及明文回傳前，再查授權。最後的授權與稽核交易是此次讀取的授權生效點。稽核失敗不回傳明文。
- 分享與撤銷使用 Firestore transaction。每次更換 epoch；舊 upload 無法把撤銷覆蓋回啟用。重新分享必須再次明確同意。
- 第一階段每次最多 30 份睡眠紀錄，整批替換，不做無限查詢。正式長期資料的分頁／增量發布另外設計。
- JS/Dart 會盡力清除可變的金鑰與 plaintext byte buffer；GC 管理的字串、物件無法保證實體記憶體立即覆寫，不宣稱安全抹除。沒有持久明文快取或 log。

本機測試臨時產生 RSA 私鑰，只存在測試程序記憶體，結束即丟棄，沒有寫到檔案。互通測試以 stdin/stdout 管線交換公鑰與假資料密文，不把內容輸出到測試報告。

## 已提供的測試與執行方式

本次驗證結果：後端／互通／模擬器共 11 個測試通過，醫療端 4 個測試通過；Dart 靜態分析無問題；Flutter JavaScript Web build 成功（`build/encrypted_sleep_demo`）。既有相依套件的 Wasm dry-run 有相容性警告，未聲稱支援 Wasm。Build 未提供雲端公開參數，開啟時會顯示設定提示；實際聯線驗收須先完成下方設定。

App 根目錄：

```powershell
node --test functions_encrypted_demo/test/share.test.js functions_encrypted_demo/test/kms.test.js functions_encrypted_demo/test/endpoints.test.js
node --test functions_encrypted_demo/test/interop.test.js
dart analyze lib/clinic/demo_sleep_envelope.dart lib/clinic/demo_sleep_share_client.dart lib/main_encrypted_sleep_demo.dart
```

互通測試 Windows 預設 Dart 路徑為此機的 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe`；其他電腦可設定 `DART_EXECUTABLE`。

醫療端根目錄：

```powershell
node --test scripts/encrypted-sleep-demo.test.js
```

模擬器整合測試必須連本機 `127.0.0.1:8185`，不接受其他 host。它會清空該專用模擬器的 innera-demo 資料，請勿與其他測試共用此埠。啟動專用 Firestore emulator 後，在 App 根目錄：

```powershell
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8185'
node --test functions_encrypted_demo/test/emulator.test.js
```

測試使用 `functions/node_modules` 已存在的 Rules 測試套件；新函式自己的依賴在 `functions_encrypted_demo/package-lock.json`。執行前分別完成 npm ci。Windows Java 的預設暫存路徑若無法建立 socket，可在啟動 Java 時指定無空白的 `-Djdk.net.unixdomain.tmpdir=D:/QQ_Web/moodsogood_app/.dart_tool`。

測試範圍：完整分享／讀取／撤銷、角色與跨院所拒絕、缺 App Check、非假患者拒絕、錯專案、文件串改／AAD 搬移、rotation、撤銷競態、稽核失敗、Rules 拒絕直接讀寫、UI 到期／關閉／登出後丟棄晚到回應。

沒有連線測試真實 KMS、真實 App Check attestation、真實已部署 callable 或雙端人工瀏覽器操作。這些仍是雲端驗收項目，不以 mock 成功取代。

## 下一次核准後才需要的雲端設定

目前不用執行下面步驟，也未代為執行。

1. **隔離專案**：所有操作先確認 Google Cloud / Firebase 畫面上是 `innera-demo`，不能是 production。不能複製 production 患者、帳號、資料或 key。
2. **金鑰保管**：在該專案啟用 Cloud KMS，建立 `demo-clinical` key ring；建立 `demo-sleep-clinic` key，用途選非對稱解密，演算法 RSA 3072 / OAEP SHA-256。位置需和下方設定一致（範例是 global）。不用匯出私鑰。
3. **專用服務帳號**：建立 `demo-encrypted-share@innera-demo.iam.gserviceaccount.com`，只用附掛服務身分，不下載 JSON key。
4. **最少權限**：該服務帳號需要 demo Firestore 資料存取、查驗 Auth 帳號狀態，以及該 KMS key 的 `cloudkms.cryptoKeyVersions.viewPublicKey`、`cloudkms.cryptoKeyVersions.useToDecrypt`。可用 demo 的 Datastore User、Firebase Authentication Viewer 與限定在該 key 的自訂 KMS role。一般管理後台與其他 Functions 不授予 KMS 解密權限。能改 IAM／部署程式的管理者仍是信任邊界，這不是防雲端最高管理權限的端到端加密。
5. **公開版本設定**：參考 `functions_encrypted_demo/kms-mapping.example.json`，將實際版本路徑設定為該 codebase 的 `DEMO_CLINIC_KMS_VERSIONS`。這裡只放 key 資源名稱，不放 PEM 私鑰或 DEK。院所增加時各用自己的 key。
6. **App Check**：在 demo Firebase 登記患者測試 Web app 與醫師 Web app，設定 reCAPTCHA Enterprise 與測試網址；不要關掉 enforceAppCheck。患者入口所需公開 Firebase API key、appId、senderId 與 site key 必須取自 demo。
7. **假帳號與關聯**：只建立假的 patient、doctor、admin/nurse 測試帳號。Firestore 建立下列假資料（UID 換成測試 Auth UID）：
   - `clinics/demo-sleep-clinic`：`status: "active"`。
   - `clinicStaff/{doctorUid}`：`clinicId: "demo-sleep-clinic", role: "doctor", active: true, status: "active"`。
   - `inneraPatients/demo-sleep-patient`：`clinicId: "demo-sleep-clinic", linked: true, firebaseUid: patientUid`。
   - `demoEncryptedFixtures/{patientUid}`：`synthetic: true, clinicId: "demo-sleep-clinic", patientId: "demo-sleep-patient"`。
   不需也不應手動建立明文 sleepRecords。此 fixture 設定只限試作，不取代正式邀請與患者同意。
8. **部署與網址**：上述準備確認後，再另行核准只部署這個 demo codebase 與測試入口；本階段沒有部署。生效後執行「患者分享→醫師讀取→非醫師拒絕→患者撤銷→醫師再次讀取被拒絕」人工驗收。

患者入口啟動範例（公開設定的值由 demo Firebase Console 取得）：

```powershell
flutter run -d chrome -t lib/main_encrypted_sleep_demo.dart --dart-define=DEMO_FIREBASE_API_KEY=公開APIKey --dart-define=DEMO_FIREBASE_APP_ID=DemoWebAppID --dart-define=DEMO_FIREBASE_SENDER_ID=DemoSenderID --dart-define=DEMO_APP_CHECK_SITE_KEY=公開SiteKey
```

醫師入口沿用醫療端 `js/firebase-config-demo.js` 的 demo 公開設定。須透過允許的 HTTPS／localhost 網址提供頁面，不以 file:// 執行。不是在正式頁面加一個解密按鈕。

## 下一階段待確認

- 用藥、健康事件、Check-in、dailyRecords 尚未加密分享；正式臨床摘要流程與正式 log 尚未改動。
- 外部 AI 是否可接收醫療明文未決定。本階段沒有 AI 呼叫或新摘要產生功能；撤銷與重新分享會刪除 pilot current 摘要並標為失效，所有 pilot 摘要前端直接讀寫皆被拒絕。
- 患者是否需能解密院所摘要、多院所 key 管理、正式邀請整合、長期分頁、rotation/rewrap 編排與舊資料遷移另行確認。
- 稽核雜湊參照可供受限管理者比對，不是匿名化；正式版需再確認拒絕事件、保留期限、告警與院所可查詢介面。

官方參考：Cloud KMS 非對稱加解密 https://docs.cloud.google.com/kms/docs/encrypt-decrypt-rsa；App Check callable enforcement https://firebase.google.com/docs/app-check/cloud-functions。
