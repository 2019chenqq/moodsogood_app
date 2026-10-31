# Encrypted sleep demo：部署完成，雲端驗收待登入（2026-10-07）

## 本輪部署範圍

開始時 Google Cloud 與 Firebase CLI active project 均確認為 innera-demo。只使用 `firebase.encrypted-demo.json`，部署 `functions:encrypted-sleep-demo,hosting`；未部署 Firestore Rules / indexes。未操作 production、正式 clinicalShares、資料遷移或 AI 摘要，未 commit / push。

五個 Gen2 Node 24 callable 已 ACTIVE：demoSleepContext、demoPublishSleep、demoRevokeSleep、demoReadSleep、demoListSleepPatients。逐一核對 runtime service account 為 `demo-encrypted-share@innera-demo.iam.gserviceaccount.com`，公開 mapping 指向指定 CryptoKey version 1；enforceAppCheck=true。

新增並部署兩個獨立 Hosting site，沒有修改共用 innera-demo site 的 route：

- 患者：https://innera-demo-encrypted-patient.web.app
- 醫师：https://innera-demo-encrypted-doctor.web.app

App Check 的 encrypted demo 專用 Enterprise key 加入上述 site 的 web.app / firebaseapp.com 精確網域；allowAllDomains 仍為 false，既有 provider、風險分數與 TTL 未改。

## 已驗證

- 患者 Flutter Web release build 成功，只有 demo 公開設定。
- 五個已部署 callable 的 state / service identity / KMS version mapping 核對成功。
- 合成 doctor 帳號以 Auth REST 登入成功；token 和密碼只在程序記憶體。
- 使用有效 Auth token 但沒有 App Check 呼叫 demoReadSleep，被 401 UNAUTHENTICATED 拒絕。
- 未帶 Auth / App Check 的 context 與 read 請求皆被 401 拒絕。
- 30 筆指定 demo Functions log 掃描未發現醫療欄位、私鑰／key material 或 credential 標記；只輸出統計與布林值，未輸出原始 log。
- 雲端測試患者 sleepRecords 數量為 0，尚未成功發布資料。
- 部署後 backend + interop 共 10 項、emulator 1 項、clinician 4 項，總計 15 項通過；Dart analyze 無問題。

## 尚未通過的驗收

真實瀏覽器登入尚未完成。工具讀取 masked 密碼欄位時會遮蔽值，不能將該值當作可用密碼；沒有繞過遮蔽。醫師頁面另出現 `appCheck/fetch-network-error`。因此尚不能宣稱真實 App Check / KMS decrypt / 分享讀取撤銷端到端成功。

嘗試在不擴權的前提 impersonate runtime SA 做直接 KMS 驗證，被 `iam.serviceAccounts.getAccessToken` 權限拒絕。沒有新增 Token Creator 或任何 runtime 權限；應透過已附掛身分的 callable 驗證 KMS，不需要為此放寬 IAM。

瀏覽器 evaluate 的唯讀範圍未提供 localStorage/sessionStorage，故未完成 storage 檢查；IndexedDB 也未檢查。尚未發生醫療資料讀取，不能以此替代讀取後的持久化檢查。

非 doctor、inactive、跨院所、未授權、disabled / revoked Auth 與解密途中撤銷已由本機測試覆蓋；它們的真實雲端驗收仍待有效 App Check 與登入。pilot summary 刪除、epoch 更新、頁面清除、Firestore envelope 白名單與 audit 白名單的雲端結果尚未驗證。

## 人工接續

在本機 PowerShell 執行 `tool/set-encrypted-demo-test-passwords.ps1`，隱藏輸入兩個合成帳號的臨時密碼，再於上述頁面登入：

- doctor：encrypted-sleep-doctor@example.test
- patient：encrypted-sleep-patient@example.test

不要把密碼或 token 貼入對話。先前隨機密碼不保存，Auth 負向測試也已更新 doctor 密碼；以腳本最後設定值為準。腳本只操作 innera-demo 的兩個指定 UID，不輸出 API response。暫存 loopback 密碼 server 已關閉，瀏覽器工具中的暫存密碼也已清除。

本輪未再次讀取或輸出 Auth hash config。前一輪紀錄暴露的事件尚未處置，本輪未自行輪替。

目前只完成 demo 部署與部分安全驗證；不具備 production 實作放行條件。需完成真實 App Check 與 KMS 分享／讀取／撤銷流程和安全檢查後，再評估 production 設計。

## 2026-10-14 最終狀態補記

本項既有synthetic雲端驗收已由使用者確認完成；前述待驗收段落是歷史進度。最終五來源、真實OpenAI、語意/race/security範圍與收尾限制，請以 ENCRYPTED_OPENAI_SYNTHETIC_DEMO.md 的「2026-10-14 最終驗收與 Demo 收尾」為準。本輪不重播來源測試或處理production資料。
