# 每日紀錄儲存和歷程查詢修復

## 問題描述

用戶報告的問題：
- 每日紀錄右上角的儲存按鈕和下方的「儲存全部」按鈕沒有將記錄保存到歷程中
- 點擊儲存後顯示「已儲存成功！」，但記錄無法在歷程頁面看到

## 根本原因分析

### 問題 1: 日期格式不一致
在 `lib/daily/daily_record_repository.dart` 中：
- **儲存時**：使用 `date.toIso8601String()` 保存完整的 ISO8601 格式（例如：`2025-02-05T14:30:00.000Z`）
- **查詢時**：在 `getDailyRecord()` 和 `getDailyRecordsByDateRange()` 中使用日期範圍比較（`>=` 和 `<=`）
- **問題**：完整 ISO8601 字符串包含時間部分，使用字符串比較時，因為保存可能在不同時間發生，可能導致查詢失敗或不匹配

### 問題 2: 日期查詢邏輯過於複雜
- `getDailyRecord()` 使用 `startOfDay` 到 `endOfDay` 的範圍查詢，但儲存時使用完整時間戳
- SQLite 的字符串比較可能無法正確處理時間戳的邊界情況

## 解決方案

### 修改 1: 統一日期格式（只保存日期部分）
在 `saveDailyRecord()` 函數中：
```dart
// 之前：date.toIso8601String() 會包含時間
// 現在：只使用日期部分（YYYY-MM-DD）
final dateOnly = DateTime(date.year, date.month, date.day);
final dateStr = dateOnly.toIso8601String();  // 格式：2025-02-05
```

### 修改 2: 簡化和統一查詢邏輯
在 `getDailyRecord()` 函數中：
```dart
// 之前：複雜的日期範圍比較（startOfDay 到 endOfDay）
// 現在：精確匹配日期字符串
final dateOnly = DateTime(date.year, date.month, date.day);
final dateStr = dateOnly.toIso8601String();
final results = await _db.query(
  'daily_records',
  where: 'userId = ? AND date = ?',  // 精確匹配
  whereArgs: [userId, dateStr],
  limit: 1,
);
```

在 `getDailyRecordsByDateRange()` 函數中：
```dart
// 統一使用日期部分（YYYY-MM-DD）進行範圍查詢
final start = DateTime(startDate.year, startDate.month, startDate.day);
final end = DateTime(endDate.year, endDate.month, endDate.day);
```

## 文件修改

### 修改的文件
- `lib/daily/daily_record_repository.dart`

### 修改的函數
1. `saveDailyRecord()` - 第 70-114 行
   - 改為只保存日期部分（YYYY-MM-DD）
   
2. `getDailyRecord()` - 第 116-145 行
   - 改為精確匹配日期字符串而非範圍比較
   
3. `getDailyRecordsByDateRange()` - 第 147-177 行
   - 統一使用日期部分進行範圍比較，移除時間戳

## 測試方案

### 如何驗證修復
1. 打開應用，導航到「每日紀錄」頁面
2. 填寫情緒、症狀、睡眠等信息
3. 點擊右上角的儲存按鈕或底部的「儲存全部」按鈕
4. 應該看到「已儲存成功！」提示
5. 導航到「歷程」頁面（底部導航欄或左側菜單）
6. 驗證今天的記錄是否顯示在列表中

### 預期結果
- ✅ 記錄應該被保存到本地數據庫
- ✅ 記錄應該在歷程頁面的列表中可見
- ✅ 記錄的日期、情緒、症狀等信息應該正確顯示
- ✅ 對於免費用戶，應該從本地數據庫加載（2 年內）
- ✅ 對於 Pro 用戶，應該從 Firebase 同步加載

## 相關的數據流

### 免費用戶的數據流（本地存儲）
```
用戶填寫記錄
↓
點擊儲存
↓
DailyRecordRepository.saveDailyRecord()
  ↓
  保存到本地 SQLite 數據庫（date 字段為 YYYY-MM-DD 格式）
  ↓
  如果 Firebase 同步啟用，也同步到 Firebase
↓
用戶查看歷程
↓
DailyRecordHistory._loadAllRecords()
  ↓
  DailyRecordRepository.getDailyRecordsByDateRange()
    ↓
    從本地 SQLite 查詢記錄（使用日期範圍）
    ↓
    返回列表
  ↓
  轉換為 DailyRecord 對象
  ↓
  顯示在歷程頁面
```

### Pro 用戶的數據流（Firebase 同步）
```
用戶填寫記錄
↓
點擊儲存
↓
DailyRecordRepository.saveDailyRecord()
  ↓
  保存到本地 SQLite 數據庫（備份）
  ↓
  同步到 Firebase Cloud Firestore
↓
用戶查看歷程
↓
DailyRecordHistory._loadAllRecords()
  ↓
  直接從 Firebase 查詢記錄（使用 Cloud Firestore）
  ↓
  返回列表
  ↓
  顯示在歷程頁面
```

## 調試技巧

如果仍然無法看到記錄，請檢查以下幾點：

### 1. 檢查本地數據庫初始化
- 在 `main.dart` 中，`DailyRecordRepository().init()` 應該在應用啟動時被調用
- 查看 debug 日誌是否有 `✅ Daily Record Repository initialized` 消息

### 2. 查看儲存日誌
- 儲存時應該看到 `📝 saveDailyRecord called` 日誌
- 成功時應該看到 `✅ Record inserted successfully with rowid=X` 日誌
- 如果失敗，會看到 `❌ Error saving daily record` 日誌

### 3. 查看查詢日誌
- 歷程頁面加載時應該看到 `🔍 getDailyRecordsByDateRange` 日誌
- 成功時應該看到 `✅ Query returned X records` 日誌
- 查看是否有 `❌ Failed to load local records` 或 `❌ Failed to load Firebase records` 日誌

### 4. 檢查用戶狀態
- 確認用戶已登入（否則無法保存）
- 對於免費用戶，確認沒有過期（查看 `ProProvider.isPro`）

## 相關文件參考

- [DailyRecordScreen](lib/daily/daily_record_screen.dart) - 每日紀錄主頁面
- [DailyRecordHistory](lib/daily/daily_record_history.dart) - 歷程查詢頁面
- [DailyRecordRepository](lib/daily/daily_record_repository.dart) - 本地數據庫操作（已修改）
- [DateHelper](lib/utils/date_helper.dart) - 日期格式化工具

## 提交信息建議

```
fix: 修復每日紀錄儲存和歷程查詢的日期格式不一致問題

- 統一日期存儲格式為 YYYY-MM-DD（只保存日期部分）
- 簡化 getDailyRecord() 的查詢邏輯（使用精確匹配）
- 統一 getDailyRecordsByDateRange() 的日期比較方式

Fixes: 每日紀錄右上角和底部儲存按鈕無法將記錄保存到歷程
```

---

**修改日期**：2025 年 2 月 5 日
**修改者**：AI Assistant
**影響範圍**：每日紀錄的儲存和查詢功能
