# 加密睡眠 Demo：雲端驗收前準備（2026-10-07）

僅 innera-demo。本輪未部署 Functions / Hosting / Rules / indexes，未修改 IAM、KMS、正式 clinicalShares 或 production，未啟用 AI。

## Runtime 與公開設定

- `firebase.encrypted-demo.json` 的 codebase 是 `encrypted-sleep-demo`，source 是 `functions_encrypted_demo`。
- `functions_encrypted_demo/index.js` 原本已指定 `demo-encrypted-share@innera-demo.iam.gserviceaccount.com`，五個 callable 都 enforceAppCheck，未修改實作。
- 新增本機 `functions_encrypted_demo/.env.innera-demo`，只有 `DEMO_CLINIC_KMS_VERSIONS` 的公開資源名稱。此檔由既有 .gitignore 排除；不含任何憑證。未來需使用明確的 demo config 和 project 才能部署，部署仍需另行核准。
- mapping 的 clinicId 為 `demo-sleep-clinic`，writeVersion 與唯一 readVersion 都是 `projects/innera-demo/locations/global/keyRings/demo-clinical/cryptoKeys/demo-sleep-clinic/cryptoKeyVersions/1`。與 `kms-mapping.example.json` 相同。

## 獨立 Web app / App Check

- Patient app：`1:37801791582:web:9e201b2ea8ea9946fae4cf`。
- Doctor app：`1:37801791582:web:2198fb3d5b08ab4afae4cf`。
- 兩者都是本輪新增的 innera-demo Web app，未替換既有 Web app。
- 新增 Enterprise SCORE site key：`6LdZeuMtAAAAAKiIheW2A-nAbqHsENfyB0W_2qW2`。只允許 `localhost`、`innera-demo.web.app`、`innera-demo.firebaseapp.com`，allowAllDomains=false；未使用固定測試分數或 debug token。
- 兩個新 app 已綁定該 key，token TTL 3600 秒、minimum score 0.5。既有 App Check 設定未變。
- Auth email/password 已啟用；上述網域已在 Auth authorizedDomains。請使用 localhost，不使用 127.0.0.1 URL（新 site key 未允許該網域）。
- 患者公開參數：`tool/encrypted-sleep-demo.public.json`。啟動：

```powershell
flutter run -d chrome -t lib/main_encrypted_sleep_demo.dart --web-hostname localhost --dart-define-from-file=tool/encrypted-sleep-demo.public.json
```

- 醫師入口 `D:/QQ_Web/Innera_clinician/encrypted-sleep.demo.html` 已改用新檔 `js/firebase-config-encrypted-sleep-demo.js`；原有 `firebase-config-demo.js` 未改。以 localhost HTTP server 提供頁面，不用 file://。
- 尚未以瀏覽器取得真實 App Check token；localhost 真實評分是否通過仍需驗收，不能用設定成功取代 attestation 測試，也不能關閉 enforcement。

## 合成測試身分與關聯

- Doctor UID：`demo-encrypted-sleep-doctor`，email：`encrypted-sleep-doctor@example.test`。
- Patient UID：`demo-encrypted-sleep-patient`，email：`encrypted-sleep-patient@example.test`。
- 兩個帳號 enabled，沒有真實人員資料。初始隨機密碼僅在建立請求記憶體，不輸出、不保存。**尚不能交給使用者登入：驗收前需透過安全本機互動流程設定新的密碼，不把密碼貼入對話或程式，也不對 example.test 寄信。**
- 新增 `clinics/demo-sleep-clinic`：status=active。
- 新增 `clinicStaff/demo-encrypted-sleep-doctor`：clinicId=demo-sleep-clinic、role=doctor、active=true、status=active。
- 新增 `inneraPatients/demo-sleep-patient`：clinicId=demo-sleep-clinic、linked=true、firebaseUid=demo-encrypted-sleep-patient。
- 新增 `demoEncryptedFixtures/demo-encrypted-sleep-patient`：synthetic=true、clinicId=demo-sleep-clinic、patientId=demo-sleep-patient。
- 文件以 exists=false 前置條件一次提交；未建立 sleepRecords 或 clinicalShares。

## 驗證與限制

後端單元 9 項、Dart/Node 互通 1 項、Firestore emulator 1 項、醫療端 4 項通過；Dart analyze 無問題。互通測試需在可使用既有 Dart SDK 的本機權限下執行，sandbox 首次執行失敗，未修改測試以掩蓋問題。

本機測試私鑰只在程序記憶體生成；沒有下載 KMS 私鑰或建立 service account JSON credential。公開設定檔沒有醫療內容、DEK、PEM 或登入密碼。

安全事件：本輪讀取 Auth project config 時，工具輸出意外包含密碼雜湊設定參數。未在本文件重複，也未另存 repo；但不能宣稱工具紀錄完全沒有敏感資訊。請限制該對話／工具紀錄存取。沒有自行輪替 Auth 設定；若要處理該暴露，另行核准並評估影響。

後續仍需核准 demo-only 部署，才能執行真實 KMS + App Check + callable 分享／讀取／拒絕／撤銷驗收。外部 AI 摘要維持待確認。
