# 心域 AI 每日免費額度

四個聊天模式各提供每個登入帳號每日 3 則免費訊息，台灣時間 00:00 換日。
Pro 維持既有訂閱驗證與速率限制，不套用免費額度；尚未啟用每月點數制。
本次僅開放 `generateInneraAiChat`，其他 AI 整理 API 的 Pro 驗證不變。

## 後端

- `functions/innera_free_quota.js`：`DAILY_LIMIT = 3`，四模式白名單、交易保留額度、成功確認與失敗釋放。
- `getInneraAiFreeQuota`：回傳可信的 Pro 狀態、台灣日期與各模式剩餘額度。
- 路徑：`innera_free_quota/{uid}/days/{yyyy-MM-dd}_{mode}`。現有 Firestore 預設拒絕規則禁止客戶端讀寫，僅 Admin SDK 可維護。
- 計次紀錄只存雜湊訊息 ID 與狀態，不保存聊天內容。跨裝置共用，刪除對話不會清除額度。
- 進行中的請求佔用額度；失敗釋放，非正常中止的保留額度在 5 分鐘後失效。
- 相同 request ID 不會重複執行；已完成的重試回傳 `already-exists`，不再次扣額。因不另存明文回覆，網路中斷後不能透過此額度紀錄取回遺失的回覆。
- 本機固定安全提醒不呼叫 AI；後端成功回傳固定安全提醒也會釋放保留額度。
- 訂閱驗證故障時沿用既有拒絕／Pro 快取寬限策略，不授予未驗證的 Pro 權限。

## 上線

先將以下兩個 Functions 部署至 App 使用的 Firebase 專案，再發布更新後的 App：

```text
firebase deploy --only functions:generateInneraAiChat,functions:getInneraAiFreeQuota
```

沿用現有 `OPENAI_API_KEY`、`REVENUECAT_SECRET_API_KEY` 與 App Check 設定。
不需要額外 Firestore 索引或每日重置排程。
舊版 App 的入口仍可能擋住免費用戶，必須更新 App 才能使用新入口。

## 驗證

`node --test functions/test/innera_free_quota.test.js` 驗證每日邊界、四模式與帳號隔離、併發、失敗退額、重試去重、Pro 與失效保留額度。
