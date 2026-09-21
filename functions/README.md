# Firebase Functions

`index.js` 是部署入口，只匯出公開的 Cloud Function。功能實作放在
`src/`；新增或搬移模組時，維持入口匯出的函式名稱，避免影響 Flutter
呼叫端與 Hosting rewrite。

## 資料夾

```text
functions/
├── index.js                 # 公開函式清單
├── package.json             # Node 版本、相依套件與指令
├── src/
│   ├── account/             # 帳號刪除
│   ├── ai/                  # Pro 驗證、限流、免費額度、用量與每日彙整
│   ├── chat/                # 心域聊天流程、回應格式、安全檢查、歷史與回顧
│   │   └── prompts/         # 聊天提示詞與模式設定
│   ├── clinic/              # 院所人員新增、停用、啟用
│   ├── community/           # 社群入口
│   ├── config/              # Firebase 初始化、Secrets 與環境參數宣告
│   ├── diary/               # 日記擷取、日記回饋、紀錄草稿與正規化
│   ├── follow_up/           # 回診摘要分享、撤銷、清理與回饋
│   ├── health_events/       # 健康事件草稿、概念對照與事件摘要
│   ├── music/               # 音樂推薦、搜尋與 Spotify 工具
│   └── shared/              # 跨功能使用的純資料轉換工具
├── test/                    # 依功能分類的測試；deployment/ 檢查公開入口
├── scripts/                 # 手動管理腳本
└── docs/                    # 部署與維運文件
```

## 常見修改位置

- 聊天流程：`src/chat/handler.js`；Callable 包裝：`src/chat/endpoints.js`。
- 聊天回應 schema：`src/chat/schemas.js`；提示詞：`src/chat/prompts/`。
- 日記擷取：`src/diary/extraction.js`；日記回饋：`src/diary/reflection.js`。
- 對話紀錄草稿整理：`src/diary/record_draft.js`。
- 音樂推薦與搜尋：`src/music/endpoints.js`。
- 院所人員管理：`src/clinic/staff.js`。

`src/config/firebase.js` 統一初始化 Admin SDK，其他模組匯入同一個
`admin` 與 `db`。Secrets 集中在 `src/config/params.js` 宣告，仍由各
Cloud Function 的 `secrets` 選項綁定，並在執行請求時讀取值。
功能模組不要反向匯入根目錄 `index.js`，避免循環引用。

## 測試與部署

在 `functions/` 執行：

```sh
npm test
npm run test:rules
npm run serve
npm run deploy
```

`npm test` 自動探索各子資料夾中的測試，不需要逐一登記新測試檔案。
Firestore / Storage 規則測試需要模擬器，平常會略過；
`npm run test:rules` 會啟動模擬器並執行該測試。

部署來源仍是 `functions/`，入口仍是 `index.js`，不需要額外建置步驟。
安全部署說明見 [SECURITY_DEPLOYMENT.md](docs/SECURITY_DEPLOYMENT.md)。
環境設定檔維持在 `functions/` 根目錄。
