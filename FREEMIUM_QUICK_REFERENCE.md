# 免費版/Pro 版本快速參考指南

## 🚀 快速開始

### 1. 查看訂閱狀態
```dart
// 在任何 Widget 中
final proProvider = context.watch<ProProvider>();
if (proProvider.isPro) {
  // Pro 用戶
} else {
  // 免費用戶
}
```

### 2. 決定是否同步到 Firebase
```dart
// 保存數據時
if (FirebaseSyncConfig.shouldSync()) {
  await uploadToFirebase(data);
}
```

### 3. 條件性加載數據
```dart
// 加載數據時
if (isPro) {
  // Pro: 從 Firebase 加載（全部）
  records = await repository.loadFromFirebase(startDate, endDate);
} else {
  // 免費: 從 SQLite 加載（90 天）
  records = await repository.loadFromDatabase(startDate, endDate);
}
```

---

## 📱 UI 組件使用

### 顯示訂閱狀態卡片
```dart
SubscriptionStatusCard(
  compact: false, // 完整版本
  onTapUpgrade: () {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => const UpgradePage(),
    ));
  },
)
```

### 顯示功能限制提示
```dart
FreePlanLimitationBanner(
  title: '免費版限制',
  description: '您正在使用免費版本，僅限查看最近 90 天的數據。',
  onLearnMore: () {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => const SubscriptionInfoPage(),
    ));
  },
)
```

### 顯示數據過期警告
```dart
DataRetentionWarning(
  daysRemaining: 7, // 距離數據過期的天數
)
```

---

## 🔄 升級流程

### 用戶點擊升級按鈕時
```dart
onPressed: () async {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (context) => const UpgradePage()),
  );
}
```

### 升級頁面確認購買
```dart
// 在 UpgradePage._handleUpgrade() 中
final proProvider = context.read<ProProvider>();
await proProvider.debugUnlock(); // 或實際支付邏輯

// 這會自動觸發：
// 1. 設置 _isPro = true
// 2. 調用升級回調
// 3. 自動遷移本地數據到 Firebase
```

---

## 📊 數據流總結

| 操作 | 免費版 | Pro 版 |
|-----|--------|--------|
| **保存** | SQLite | SQLite + Firebase |
| **加載** | SQLite (90 天) | Firebase (全部) |
| **升級時** | - | 自動遷移本地→Firebase |

---

## 🔧 調試和測試

### 在 Settings 頁面切換 Pro 狀態（Debug Mode）
```dart
// 在調試模式下，會看到兩個按鈕
ElevatedButton(
  onPressed: () => proProvider.debugUnlock(),
  child: const Text('解鎖 Pro'),
)

ElevatedButton(
  onPressed: () => proProvider.lock(),
  child: const Text('鎖定'),
)
```

### 測試場景清單
- [ ] 免費用戶創建記錄 → 只存本地
- [ ] Pro 用戶創建記錄 → 本地+Firebase
- [ ] 免費用戶升級 → 自動遷移數據
- [ ] 升級後查看全部歷史 → 顯示所有數據
- [ ] 數據超過 90 天 → 免費版隱藏

---

## 📁 關鍵文件位置

```
lib/
├── providers/
│   └── pro_provider.dart ..................... 訂閱狀態管理
├── utils/
│   ├── firebase_sync_config.dart ............ 動態同步配置
│   └── data_migration.dart ................. 數據遷移工具
├── pages/
│   ├── subscription_info_page.dart ......... 訂閱信息展示
│   └── upgrade_page.dart ................... 升級頁面
├── widgets/
│   ├── subscription_status_widget.dart .... 訂閱狀態組件
│   └── upgrade_migration_dialog.dart ...... 遷移進度對話框
└── FREEMIUM_MODEL_IMPLEMENTATION.md ....... 完整實現指南
```

---

## ⚙️ 配置和常數

### 啟用/禁用調試模式
```dart
// lib/providers/pro_provider.dart
const bool kDebugUnlockAllProFeatures = false; // 正式上線改為 false
```

### 免費版數據保留期
```dart
// lib/daily/daily_record_history.dart
const int FREE_VERSION_DAYS = 90;
```

---

## ❓ 常見問題速查

### Q: 如何添加新的 Pro 功能？
1. 在 UI 中添加 `if (proProvider.isPro)` 檢查
2. 或使用 `FreePlanLimitationBanner` 提示免費版限制
3. 添加「升級」按鈕導向 `UpgradePage`

### Q: 升級失敗如何處理？
- `DataMigration.migrateLocalToFirebase()` 返回 `MigrationResult`
- 檢查 `result.success` 確認升級成功
- 顯示 `result.message` 給用戶

### Q: 免費用戶能否臨時看到超過 90 天的數據？
- 不能。90 天限制寫在數據加載邏輯中
- 超過 90 天的數據在查詢時被過濾

### Q: Pro 用戶降級會怎樣？
- 本地 SQLite 保留所有數據（已遷移上來的副本）
- 無法訪問 Firebase
- 重新升級時直接使用 Firebase（無需再次遷移）

---

## 📝 生產環境檢查清單

- [ ] 禁用 `kDebugUnlockAllProFeatures`
- [ ] 集成實際支付 API (Google Play / App Store)
- [ ] 測試所有升級場景
- [ ] 添加支付失敗重試機制
- [ ] 國際化訂閱文案
- [ ] 設置訂閱取消/管理界面
- [ ] 備份/恢復流程
- [ ] 監控遷移成功率

---

## 🌐 API 端點參考

### Firebase 集合結構
```
users/{userId}/daily_records/{dateId}
```

### 本地 SQLite 表
```sql
CREATE TABLE daily_records (
  id TEXT PRIMARY KEY,
  userId TEXT,
  date TEXT,
  data TEXT (JSON),
  ...
);
```

---

## 🔐 安全考慮

- ✅ 本地數據始終加密存儲（SQLite 支持）
- ✅ Firebase 數據 TLS 傳輸
- ✅ 用戶認證必須成功才能升級
- ✅ 數據遷移使用批量 write（原子性）
- ✅ 敏感字段不記錄到日誌

---

## 📈 監控和分析

建議追蹤的指標：
- 免費版 vs Pro 版用戶數
- 免費版→Pro 的轉換率
- 數據遷移成功率
- 升級失敗原因
- 平均升級完成時間

---

**版本:** 1.0  
**最後更新:** 2026 年 1 月 20 日  
**維護者:** 心域開發團隊
