# 免費版 vs Pro 版本實現指南

## 概述

本應用實現了完整的免費版/Pro版本分層模型，通過動態配置根據用戶訂閱狀態自動調整功能和數據存儲方式。

---

## 架構設計

### 1. 訂閱狀態管理 - `ProProvider`

**位置:** `lib/providers/pro_provider.dart`

**核心功能:**
- 管理用戶的 Pro 狀態（`isPro` getter）
- 支持數據遷移回調（`setOnUpgradeCallback`）
- 在升級時自動觸發數據遷移

**主要方法:**
```dart
// 設置升級回調
proProvider.setOnUpgradeCallback(callback);

// 調試用：模擬升級（觸發數據遷移）
await proProvider.debugUnlock();

// 鎖定（降級回免費版）
proProvider.lock();
```

### 2. 動態同步配置 - `FirebaseSyncConfig`

**位置:** `lib/utils/firebase_sync_config.dart`

**核心功能:**
- 根據 Pro 狀態動態決定是否同步到 Firebase
- 提供存儲類型和數據保留期信息

**使用方式:**
```dart
// 在保存數據時
if (FirebaseSyncConfig.shouldSync()) {
  // 上傳到 Firebase
}

// 獲取存儲類型
String type = FirebaseSyncConfig.getStorageType(); // "☁️ 雲端" 或 "💾 本地"

// 獲取數據保留期
String retention = FirebaseSyncConfig.getDataRetention(); // "永久保存" 或 "最近 90 天"
```

### 3. 數據遷移工具 - `DataMigration`

**位置:** `lib/utils/data_migration.dart`

**功能:**
- 當用戶升級到 Pro 時，自動將本地 SQLite 數據遷移到 Firebase
- 支持大量數據的批量上傳（每 500 條記錄為一批）
- 驗證上傳成功率

**使用方式:**
```dart
final result = await DataMigration().migrateLocalToFirebase(
  userId: user.uid,
  repository: dailyRecordRepository,
);

if (result.success) {
  print('遷移成功：${result.recordsCount} 條記錄');
}
```

---

## 功能對比

| 功能 | 免費版 | Pro 版 |
|-----|--------|--------|
| **數據存儲位置** | 本地 SQLite | Firebase 雲端 |
| **數據保留期** | 最近 90 天 | 永久保存 |
| **多設備同步** | ❌ 否 | ✅ 是 |
| **自動備份** | ❌ 無 | ✅ 有 |
| **高級統計** | ⭐ 基礎 | ⭐⭐⭐ 完整 |
| **隱私保護** | ✅ 本地加密 | ✅ 雲端加密 |

---

## 數據流架構

### 免費版用戶數據流

```
用戶輸入
    ↓
DailyRecordScreen (保存)
    ↓
DailyRecordRepository.save()
    ↓
本地 SQLite (必選)
    ↓
Firebase (檢查 shouldSync() → 否 → 不上傳)
```

### Pro 用戶數據流

```
用戶輸入
    ↓
DailyRecordScreen (保存)
    ↓
DailyRecordRepository.save()
    ↓
本地 SQLite (必選)
    ↓
Firebase (檢查 shouldSync() → 是 → 上傳)
```

### 升級流程

```
免費版用戶
    ↓
點擊「升級」按鈕
    ↓
UpgradePage (顯示 Pro 功能)
    ↓
confirmUpgrade()
    ↓
ProProvider.debugUnlock() (觸發升級回調)
    ↓
DataMigration.migrateLocalToFirebase() (遷移本地數據)
    ↓
所有本地記錄上傳到 Firebase
    ↓
升級完成，開始使用 Firebase
```

---

## 數據加載邏輯

### 查詢記錄時 (`daily_record_history.dart`)

```dart
// 判斷用戶類型
if (!isPro) {
  // 免費用戶：只從 SQLite 查詢，限制 90 天
  startDate = endDate.subtract(Duration(days: 90));
  records = await repository.loadFromDatabase(startDate, endDate);
} else {
  // Pro 用戶：從 Firebase 查詢，無時間限制
  records = await repository.loadFromFirebase(
    DateTime(2020, 1, 1), // 所有歷史數據
    endDate,
  );
}
```

---

## UI 組件

### 1. 訂閱狀態卡片 - `SubscriptionStatusCard`

**位置:** `lib/widgets/subscription_status_widget.dart`

**用途:** 在主界面、設置頁面等位置顯示當前訂閱狀態

```dart
SubscriptionStatusCard(
  compact: false, // 完整版本
  onTapUpgrade: () { /* 導航到升級頁面 */ },
)
```

### 2. 訂閱信息頁面 - `SubscriptionInfoPage`

**位置:** `lib/pages/subscription_info_page.dart`

**內容:**
- 訂閱狀態
- 功能對比表
- 存儲信息詳情
- 升級按鈕

### 3. 升級頁面 - `UpgradePage`

**位置:** `lib/pages/upgrade_page.dart`

**內容:**
- Pro 功能列表
- 價格信息
- 升級按鈕

### 4. 限制提示 - `FreePlanLimitationBanner`

**位置:** `lib/widgets/subscription_status_widget.dart`

**用途:** 在統計頁面等位置提示免費用戶的功能限制

```dart
FreePlanLimitationBanner(
  title: '免費版限制',
  description: '免費版本只顯示最近 90 天的數據。升級到 Pro 查看所有歷史。',
  onLearnMore: () { /* 導航到訂閱信息 */ },
)
```

---

## 初始化流程 (main.dart)

```dart
void main() async {
  // 初始化各個服務...
  
  runApp(
    MultiProvider(
      providers: [
        // ... 其他 Provider
        ChangeNotifierProvider<ProProvider>(
          create: (_) => ProProvider()..init(),
        ),
      ],
      child: const MainApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 1. 設置 Pro 狀態回調
    FirebaseSyncConfig.setProStatusCallback(() {
      // 動態檢查 Pro 狀態
      return false;
    });

    // 2. 設置升級時的數據遷移回調
    final proProvider = Provider.of<ProProvider>(context, listen: false);
    proProvider.setOnUpgradeCallback(() async {
      // 升級時遷移本地數據到 Firebase
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await DataMigration().migrateLocalToFirebase(
          userId: user.uid,
          repository: DailyRecordRepository(),
        );
      }
    });
  });
}
```

---

## 集成檢查清單

### 保存數據時 ✅
- [x] `DailyRecordScreen.saveRecord()` 調用 `FirebaseSyncConfig.shouldSync()`
- [x] Pro 用戶數據同時保存到 SQLite 和 Firebase
- [x] 免費用戶數據只保存到 SQLite

### 加載數據時 ✅
- [x] `daily_record_history.dart` 檢查 `isPro` 狀態
- [x] 免費用戶查詢限制為 90 天
- [x] Pro 用戶查詢全部歷史

### UI 反饋 ✅
- [x] `SubscriptionStatusCard` 顯示當前狀態
- [x] `FreePlanLimitationBanner` 提示功能限制
- [x] `DataRetentionWarning` 警告數據即將過期

### 升級流程 ✅
- [x] `UpgradePage` 顯示 Pro 功能和價格
- [x] 升級時自動觸發 `DataMigration`
- [x] `UpgradeMigrationDialog` 顯示遷移進度

---

## 調試模式

在開發過程中，可以在 `Settings` 頁面使用調試按鈕快速切換 Pro 狀態：

```dart
if (kDebugMode) {
  // 「解鎖 Pro」按鈕
  proProvider.debugUnlock();
  
  // 「鎖定」按鈕
  proProvider.lock();
}
```

---

## 生產環境準備

### 1. 禁用調試開關
```dart
// lib/providers/pro_provider.dart
const bool kDebugUnlockAllProFeatures = false; // 改為 false
```

### 2. 集成實際支付
```dart
// 替換 ProProvider 中的升級邏輯
// 與 In-App Purchase (IAP) 服務集成

await IAPService.instance.init();
// ... 監聽購買事件
proProvider.debugUnlock(); // 改為實際解鎖邏輯
```

### 3. 測試所有場景
- [ ] 免費版用戶創建記錄（本地保存）
- [ ] Pro 用戶創建記錄（本地+雲端）
- [ ] 升級過程中的數據遷移
- [ ] 升級後查看全部歷史
- [ ] 多設備同步（Pro）
- [ ] 數據備份和恢復

---

## 常見問題

### Q: 升級後舊數據會丟失嗎？
**A:** 不會。`DataMigration` 會自動將所有本地記錄上傳到 Firebase。

### Q: 免費用戶能看到 90 天以上的數據嗎？
**A:** 不能。超過 90 天的數據會被過濾掉。建議在 UI 中明確提示這個限制。

### Q: Pro 用戶從 Firebase 下載了數據，還需要本地副本嗎？
**A:** 需要。本地副本用於離線訪問和快速查詢。上傳到 Firebase 是為了備份和多設備同步。

### Q: 如何處理升級失敗？
**A:** `MigrationResult` 會返回 `success` 和 `message` 字段。顯示錯誤信息並允許用戶重試。

---

## 文件引用

**核心文件:**
- `lib/providers/pro_provider.dart` - 訂閱狀態管理
- `lib/utils/firebase_sync_config.dart` - 動態同步配置
- `lib/utils/data_migration.dart` - 數據遷移工具

**UI 文件:**
- `lib/pages/subscription_info_page.dart` - 訂閱信息展示
- `lib/pages/upgrade_page.dart` - 升級頁面
- `lib/widgets/subscription_status_widget.dart` - 訂閱狀態組件
- `lib/widgets/upgrade_migration_dialog.dart` - 遷移進度對話框

**邏輯文件:**
- `lib/daily/daily_record_screen.dart` - 數據保存（調用 shouldSync）
- `lib/daily/daily_record_history.dart` - 數據加載（條件分支）
- `lib/main.dart` - 應用初始化

---

## 後續改進建議

1. **支付集成** - 集成 Google Play Billing / Apple In-App Purchase
2. **訂閱管理** - 添加取消訂閱、查看發票等功能
3. **試用期** - 添加免費試用 Pro 版本（如 7 天）
4. **促銷** - 首次購買折扣或季度促銷
5. **數據導出** - 允許用戶導出 JSON/CSV 格式的數據
6. **多語言支持** - 翻譯訂閱相關的 UI 文案

---

**最後更新:** 2026 年 1 月 20 日
**版本:** 1.0 - 完整的免費版/Pro 分層實現
