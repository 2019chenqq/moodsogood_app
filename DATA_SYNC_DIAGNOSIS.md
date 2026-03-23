## 🔴 數據同步問題診斷報告

您的應用存在以下主要問題導致紀錄出現和消失：

### 問題根源：

#### 1️⃣ **Firebase 同步被禁用**
📍 位置：`lib/utils/firebase_sync_config.dart`
```dart
static const bool kEnableFirebaseSync = false;  // ⚠️ 禁用狀態
```
**影響**：
- 所有新數據只保存到本地 SQLite
- 不同設備無法同步
- 卸載應用會丟失本地數據

#### 2️⃣ **混合數據源導致查詢邏輯混亂**
📍 位置：`lib/daily/daily_record_history.dart` 第 145-196 行

代碼先從本地加載，再從 Firebase 加載：
```dart
// 1. 先從本地 SQLite 加載
final localRecords = await repo.getDailyRecordsByDateRange(...);

// 2. 再從 Firebase 加載
final snapshot = await FirebaseFirestore.instance.collection('users')...
```

**問題**：
- 如果 Firebase 同步禁用，本地和 Firebase 的數據會不一致
- 有時只顯示本地數據，有時顯示合併後的數據
- Firebase 中的舊數據可能出現在查詢中

#### 3️⃣ **日期查詢範圍限制**
📍 位置：`lib/daily/daily_record_history.dart` 第 147 行
```dart
final startDate = endDate.subtract(const Duration(days: 90));
```
**問題**：只查詢最近 90 天的數據，超過 90 天的紀錄不會顯示

#### 4️⃣ **本地數據庫查詢可能失敗**
📍 位置：`lib/daily/daily_record_screen.dart` 第 145-155 行
```dart
final repo = DailyRecordRepository();
final localRecord = await repo.getDailyRecordByDateRange(...);
```

沒有足夠的錯誤處理，如果本地數據查詢失敗會無聲地失敗

---

### 🛠️ 解決方案：

#### 方案 A：啟用 Firebase 同步（推薦用於正式版）
✅ 優點：多設備同步、雲端備份、永久保存
❌ 缺點：Firebase 配額消耗

```dart
// lib/utils/firebase_sync_config.dart
static const bool kEnableFirebaseSync = true;  // 改為 true
```

#### 方案 B：純本地存儲（推薦用於測試版）
✅ 優點：無 Firebase 配額、快速、隱私
❌ 缺點：卸載應用會丟失、無多設備同步

保持現有設置，但修復查詢邏輯

#### 方案 C：混合模式（最佳實踐）
✅ 優點：本地快速、雲端備份、離線支持
需要改進同步邏輯確保數據一致性

---

### 🔍 快速診斷步驟：

1. **檢查 Firebase 同步狀態**
   - 打開設置頁面
   - 查看是否有 Firebase Sync 的狀態指示

2. **查看調試日誌**
   - 運行應用，打開 Flutter 調試控制台
   - 搜索關鍵字：`🔍 Loading records from`
   - 觀察顯示本地還是 Firebase 的數據

3. **手動測試**
   - 添加新紀錄
   - 關閉應用再打開
   - 卸載應用再安裝看數據是否還在

---

### 📋 建議的修改清單：

□ 決定使用本地還是雲端存儲策略
□ 修改 `kEnableFirebaseSync` 配置
□ 改進 `_loadAllRecords()` 查詢邏輯
□ 添加數據同步狀態指示
□ 在 UI 中顯示「本地」或「雲端」標籤
□ 實現手動同步按鈕
□ 添加數據一致性檢查和修復功能
