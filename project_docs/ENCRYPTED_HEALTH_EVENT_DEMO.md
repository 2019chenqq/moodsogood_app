# HealthEvent 加密 Demo（2026-10-08）

僅 innera-demo，沿用已有 KMS / runtime service account / custom roles / App Check，未新增金鑰或擴權。只使用合成資料，不讀取 HealthEventRepository，不改正式 clinicalShares 或原始 healthEvents，不處理 Check-in / Medication / dailyRecords / AI。

## 實際 schema 來源

- App：`lib/models/health_event.dart`、`lib/utils/state_change_normalizer.dart`、`lib/daily/health_event_repository.dart`。
- 既有分享：`lib/clinic/clinical_share_service.dart` 的 syncHealthEvents。
- 醫療端：`D:/QQ_Web/Innera_clinician/js/firebase-health-sync.js` 的快速紀錄顯示。

原模型有 id（文件識別）、timestamp、symptoms、emotions、stateChanges、timePrecision、context、note、createdAt、updatedAt。沒有獨立 date / eventType / description 欄位，不另造字段。

Encrypted payload 固定包含 timestamp（UTC ISO-8601 毫秒）、symptoms（name + optional severity，1–5）、emotions（name + intensity，1–5）、stateChanges（鍵名對應 1–5 整數）、timePrecision、context、note、createdAt、updatedAt。最後五項可為 null；日期欄位若有值為 UTC ISO。doc id 為新隨機值，不另保存原始 id。

醫療端舊程式將 symptoms 讀成 intensity；本 demo 依 App 模型讀 severity，不修改舊同步程式。

## 加密與授權

沿用每文件新 DEK / nonce、AES-256-GCM、RSA-OAEP-3072-SHA256 及既有 clinic version 1。AAD 陣列的 type 明確為 healthEvents，其餘欄位與 sleep 協定相同，不能跨 type 搬移。

- Envelopes：`demoEncryptedShares/{uid}/clinics/{clinicId}/healthEvents/{randomId}`。
- 事件同意與 epoch：`demoEncryptedShares/{uid}/clinics/{clinicId}/scopes/healthEvents`。
- 事件 pilot 摘要失效位置：該 scope 的 `aiSummaries/current`；本輪沒有產生摘要。
- 稽核：原 demoEncryptedAudit，action 前綴 healthEvent；欄位白名單不變。

HealthEvent 使用相同 createService 授權交易機制，但 scope / epoch 獨立。睡眠沿用原 path / epoch，不因事件分享或撤銷而被刪除或啟用。事件分享不接受舊 epoch；撤銷刪除密文及 scope 摘要，標為 inactive。每次 KMS 操作前及回傳前重新確認授權；稽核失敗不回傳明文。

新增 callable：demoHealthEventContext、demoPublishHealthEvents、demoReadHealthEvents、demoRevokeHealthEvents。與既有五個 callable 使用同一個 App Check / revoked-token / 專用 identity wrapper。

患者入口新增獨立 HealthEvent 勾選、分享與撤銷，僅由 HealthEvent 模型構造兩筆固定假資料。醫師點患者時，sleep 與 HealthEvent 分別自動讀取；各自處理未授權，不互相清除授權。沿用 10 秒重查、30 秒到期、登出／離頁／關閉清除與晚到回應丟棄。

## 本機驗證

Backend / interop 17 項、emulator 1 項（同時包含兩種資料）、醫師 UI 6 項，共 24 項通過。Dart analyze 無問題，患者 release Web build 成功。測試 key 只在程序記憶體，interop 管線資料不寫檔或印報告。

涵蓋模型、正常分享讀取、權限拒絕、App Check、AAD 搬移、tag 串改、撤銷競態、stale upload、Rules 拒絕直接讀寫、audit 白名單、實際 UI script 不呼叫 persistent storage、明文到期清除與無 application log。真實 browser storage 與雲端 log 檢查仍須人工登入後完成，不能以 VM 測試替代。

## 雲端驗收狀態

Demo-only 部署已成功，四個新增 callable 為 ACTIVE 且使用既有專用 runtime service account。兩個專用 Hosting 入口已發布；未部署 Rules / indexes，未更動 KMS / IAM / App Check。

四個新 callable 的缺 Auth / App Check 請求均被 401 拒絕。掃描 24 筆新增 Functions 的 log 未發現合成事件內容或 key / credential 標記；此結果尚未涵蓋成功解密後的 log。核對時 HealthEvent 文件數量為 0，不能以空集合宣稱已驗證成功分享的 envelope。

等待既有假帳號的人工登入／同意／分享。需先分享並讓醫師看到兩筆假事件，暫不撤銷，以便核對 envelope 欄位；接著驗證撤銷與後續拒絕。真實非授權角色、競態、解密後 log / browser storage 尚未驗收，不以本機測試取代。不得重設既有測試密碼以方便自動化。

新增／修改檔案：

- `functions_encrypted_demo/protocol.js`、`service.js`、`index.js`。
- `functions_encrypted_demo/test/helpers.js`、`endpoints.test.js`、`interop.test.js`、`emulator.test.js`；新增 `health-event-fixture.js`、`health-events.test.js`。
- `lib/clinic/demo_sleep_envelope.dart`、`lib/main_encrypted_sleep_demo.dart`、`tool/demo_sleep_interop.dart`；新增 `lib/clinic/demo_health_event_share_client.dart`。
- 醫療端 `encrypted-sleep.demo.html`、`js/encrypted-sleep-demo.js`；新增 `scripts/encrypted-health-event-demo.test.js`。

既有 Git 修改全部保留，沒有 commit / push。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
