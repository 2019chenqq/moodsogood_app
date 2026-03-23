# 看不到刪除按鈕 - 診斷指南

## 可能的原因

### 1️⃣ 沒有看板存在
**症狀**: 看板管理頁面顯示「沒有看板」

**解決**:
1. 檢查是否有通過「申請開設看板」創建過看板
2. 或者先在 Firebase Console 中手動創建一個測試看板

### 2️⃣ Firestore 權限問題
**症狀**: 看不到看板列表，顯示「無法加載看板列表」

**解決**:
1. 檢查 Logcat 中的錯誤訊息
2. 確認 Firestore 規則已部署（最後部署時間）
3. 確認用戶已登入

### 3️⃣ 頁面沒有加載完成
**症狀**: 看到轉圈圈（loading indicator）

**解決**:
1. 等待 5-10 秒
2. 返回社區首頁再進入
3. 檢查網絡連接

## 診斷步驟

### 步驟 1: 檢查用戶 UID
看板管理頁面的 AppBar 副標題會顯示當前用戶。如果看到：
```
用戶: xxx@example.com
```
說明已成功登入。

### 步驟 2: 檢查看板列表
如果看到「沒有看板」或顯示看板列表，說明 Firestore 連接正常。

### 步驟 3: 檢查刪除按鈕
在看板卡片的右側，應該看到一個垃圾桶圖標（🗑️）。

如果看不到：
- 嘗試左右滾動看板卡片
- 檢查設備屏幕寬度是否足夠顯示按鈕
- 嘗試旋轉屏幕

### 步驟 4: 查看 Logcat 調試信息
打開 Logcat，搜索以下關鍵字：

```
📊 Rooms management snapshot state: # 顯示加載狀態
📊 Current user: # 顯示當前用戶 UID
✅ Rooms loaded: # 顯示加載了多少看板
❌ Rooms query error: # 顯示錯誤信息
```

## 創建測試看板

如果沒有看板可以刪除，可以：

### 方法 1: 通過 App 創建
1. 進入社區首頁
2. 點擊「申請開設看板」卡片中的「提出申請」
3. 填寫看板名稱和簡述
4. 點擊「送出申請」
5. 等待審批（自己審批）

### 方法 2: 通過 Firebase Console 直接創建
1. 打開 [Firebase Console](https://console.firebase.google.com/)
2. 選擇 `moodsogood-9e45b` 項目
3. 進入 Firestore Database
4. 找到 `community_rooms` 集合
5. 點擊「新建文檔」
6. 添加以下字段：
   ```
   name: "測試看板"
   description: "用於測試刪除功能"
   createdAt: (當前時間)
   createdBy: (你的 UID)
   ```

## 快速檢查清單

- [ ] 已登入 App
- [ ] 進入社區首頁
- [ ] 點擊管理員圖標（⚙️）
- [ ] 進入審核頁面
- [ ] 點擊看板管理按鈕（📁）
- [ ] 看板管理頁面已加載（沒有顯示「加載中」或錯誤）
- [ ] 看板列表不為空（至少有一個看板）
- [ ] 能看到看板卡片
- [ ] 卡片右側有垃圾桶圖標

## 如果還是看不到

請提供以下信息：
1. 你看到的是什麼屏幕？（加載、錯誤訊息、或空白）
2. Logcat 中的錯誤信息是什麼？
3. Firebase Console 中是否有看板數據？

## 代碼位置

看板管理頁面代碼：
[rooms_management_page.dart](lib/community/pages/rooms_management_page.dart)

相關 Firestore 規則：
[firestore.rules](firestore.rules#L47-L53)
