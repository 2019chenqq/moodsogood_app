# PDF 導出系統 - 集成檢查清單

## ✅ 前置準備

- [ ] Dart SDK >= 3.3.0
- [ ] Flutter >= 3.10.0
- [ ] Android API >= 21
- [ ] iOS 支援（可選）

## 📦 依賴安裝

### Step 1: 更新 pubspec.yaml
```yaml
dependencies:
  pdf: ^3.10.0
  printing: ^5.11.0
  share_plus: ^7.2.0
  collection: ^1.17.0
  # 其他現有依賴...
```

- [ ] 已添加上述依賴
- [ ] 已運行 `flutter pub get`

### Step 2: 驗證依賴
```bash
flutter pub get
flutter pub outdated  # 檢查版本兼容性
```

- [ ] 依賴安裝成功
- [ ] 沒有版本衝突

## 🔧 Android 配置

### Step 1: 更新 AndroidManifest.xml
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

- [ ] 已添加存儲權限
- [ ] 已配置 targetSdkVersion >= 31（如需要）

### Step 2: 運行時權限（可選）
```dart
import 'package:permission_handler/permission_handler.dart';

if (await Permission.storage.request().isGranted) {
  // 有權限，可以導出
}
```

- [ ] 已考慮運行時權限（Android 6.0+）

## 📂 代碼集成

### Step 1: 複製文件到項目
```
lib/PDF/
├── export_config.dart                    ✅
├── export_metrics.dart                   ✅
├── export_metrics_calculator.dart        ✅
├── summary_rule_engine.dart              ✅
├── pdf_page_builder.dart                 ✅
├── pdf_export_service.dart               ✅
├── pdf_generator_impl.dart               ✅
├── pdf_export_provider.dart              ✅
├── pdf_export_examples.dart              ✅
├── README.md                             ✅
└── PDF_EXPORT_GUIDE.md                   ✅
```

- [ ] 所有文件已複製到 `lib/PDF/` 目錄

### Step 2: 檢查導入
```dart
// 在相關文件中驗證導入是否正確
import 'models/daily_record.dart';
import 'PDF/export_config.dart';
// ... 其他導入
```

- [ ] 所有導入都已正確解決
- [ ] 沒有「找不到符號」的錯誤

### Step 3: 驗證編譯
```bash
flutter analyze
flutter pub get
flutter pub upgrade
```

- [ ] `flutter analyze` 無嚴重錯誤
- [ ] 項目能成功編譯

## 🎯 UI 集成

### Step 1: 在 main.dart 中設置 Provider
```dart
import 'PDF/pdf_export_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PDFExportProvider()),
        // ... 其他 providers
      ],
      child: const MyApp(),
    ),
  );
}
```

- [ ] PDFExportProvider 已添加到 main.dart

### Step 2: 在頁面中使用

#### 方式 A: 使用 PDFExportButton（推薦）
```dart
import 'PDF/pdf_export_provider.dart';

PDFExportButton(
  records: myRecords,
  medications: ['藥物1'],
  onSuccess: () => print('成功'),
  onError: (error) => print('失敗: $error'),
)
```

- [ ] 已在至少一個頁面中添加 PDFExportButton

#### 方式 B: 手動調用
```dart
final provider = context.read<PDFExportProvider>();
await provider.exportWithDefaultConfig(
  records: records,
  outputDir: outputDir,
  medications: medications,
  context: context,
);
```

- [ ] 已在相關頁面中實現導出邏輯

### Step 3: 測試基本功能
```bash
flutter run
```

- [ ] 應用成功啟動
- [ ] 沒有運行時錯誤
- [ ] PDFExportButton 正確顯示

## 🧪 功能測試

### 測試 1: 簡單導出
- [ ] 點擊導出按鈕
- [ ] PDF 生成成功
- [ ] 檔案已保存到指定目錄
- [ ] 檔名格式正確 (心域_醫師摘要_YYYYMMDD-YYYYMMDD.pdf)

### 測試 2: 自訂配置
- [ ] 可以選擇自訂日期範圍
- [ ] 可以選擇包含/不包含選項
- [ ] 導出結果符合配置

### 測試 3: 數據完整性
- [ ] PDF 包含所有 5-6 頁面
- [ ] 頁面 1: 總覽摘要（情緒、睡眠、用藥）
- [ ] 頁面 2: 情緒趨勢分析
- [ ] 頁面 3: 睡眠紀錄
- [ ] 頁面 4: 藥物×症狀×情緒關聯
- [ ] 頁面 5-6: 每日詳細摘要

### 測試 4: 指標計算
- [ ] 情緒平均分正確
- [ ] 睡眠時數計算準確
- [ ] 症狀重疊比例計算正確
- [ ] AI 摘要邏輯合理

### 測試 5: 錯誤處理
- [ ] 沒有數據時顯示適當提示
- [ ] 權限不足時提示用戶
- [ ] 導出失敗時顯示錯誤訊息
- [ ] 能優雅地恢復

### 測試 6: 性能
- [ ] 導出 28 天數據 < 2 秒
- [ ] UI 在導出期間不卡頓
- [ ] 進度條正常工作

## 📱 不同設備測試

### Android 測試
- [ ] Android 6.0 (API 23)
- [ ] Android 8.0 (API 26) - 儲存權限改變
- [ ] Android 10 (API 29)
- [ ] Android 12 (API 31+)

### 目錄位置測試
```dart
// 測試不同的輸出目錄
'/storage/emulated/0/Documents'           // 公開
getApplicationDocumentsDirectory()         // 應用特定
getExternalStorageDirectory()              // 外部
```

- [ ] 已測試至少 2 個不同目錄
- [ ] PDF 能成功保存到各目錄

## 🔍 代碼審查

### 檢查清單
- [ ] 所有 import 語句正確
- [ ] 沒有未使用的變數
- [ ] 錯誤處理完善
- [ ] 日誌輸出足夠詳細
- [ ] 註釋清晰易懂
- [ ] 命名符合 Dart 規範
- [ ] 沒有硬編碼的魔法數字

### 運行分析工具
```bash
flutter analyze
flutter format lib/PDF/
dart fix --apply
```

- [ ] 分析完成，無嚴重問題
- [ ] 代碼已格式化
- [ ] Fix 工具無需改動

## 📚 文檔檢查

- [ ] 已閱讀 PDF_EXPORT_GUIDE.md
- [ ] 已閱讀 README.md
- [ ] 理解 7 步流程
- [ ] 了解各主要類別的功能
- [ ] 有問題時知道去哪裡查找

## 🚀 上線準備

### Pre-Release 檢查
- [ ] 已在多台設備上測試
- [ ] 已測試所有 UI 流程
- [ ] 已驗證 PDF 內容質量
- [ ] 已處理所有已知 bug
- [ ] 已更新版本號 (pubspec.yaml)

### Release 檢查
- [ ] 已運行 `flutter build apk` 或 `flutter build ios`
- [ ] 已驗證簽名配置
- [ ] 已進行最終功能測試
- [ ] 已準備用戶文檔/幫助

## 📋 常見問題排查

### 問題: PDF 無法保存
```
排查步驟:
1. [ ] 檢查 Android 權限配置
2. [ ] 檢查輸出目錄是否存在
3. [ ] 檢查磁盤空間是否足夠
4. [ ] 查看 logcat 中的詳細錯誤
5. [ ] 驗證檔案路徑格式
```

### 問題: 數據計算不準確
```
排查步驟:
1. [ ] 檢查原始 DailyRecord 數據格式
2. [ ] 驗證日期範圍計算
3. [ ] 檢查 ExportConfig 參數
4. [ ] 追蹤 ExportMetricsCalculator 輸出
5. [ ] 手動驗證計算公式
```

### 問題: UI 卡頓
```
排查步驟:
1. [ ] 確認使用了 async/await
2. [ ] 檢查 isExporting 狀態更新
3. [ ] 驗證 Provider.notifyListeners() 調用
4. [ ] 查看 Flutter DevTools 性能分析
5. [ ] 檢查是否有長時間同步操作
```

### 問題: 中文亂碼
```
排查步驟:
1. [ ] 檢查 PDF 字體配置
2. [ ] 驗證文本編碼為 UTF-8
3. [ ] 確認 Dart 文件編碼為 UTF-8
4. [ ] 使用 pw.TextStyle 指定中文字體
```

## 📊 測試覆蓋率目標

```
目標: 核心功能 >= 80% 覆蓋率

┌─────────────────────────────┐
│ 計算模塊                    │
├─────────────────────────────┤
│ ExportMetricsCalculator     │ 90%
│ SummaryRuleEngine           │ 85%
│ PDFPageBuilder              │ 80%
│ PDFGeneratorImpl             │ 75%
└─────────────────────────────┘
```

- [ ] 已編寫單元測試
- [ ] 已運行測試覆蓋率檢查
- [ ] 核心功能測試完整

## ✨ 優化建議

### 短期（第一周）
- [ ] 添加導出進度顯示
- [ ] 實現分享功能集成
- [ ] 優化 PDF 樣式

### 中期（第二周）
- [ ] 添加圖表支持
- [ ] 實現導出歷史管理
- [ ] 添加數據驗證

### 長期（第三周+）
- [ ] 支持多語言
- [ ] 實現雲端備份
- [ ] 用戶反饋收集

## 📞 技術支持聯繫

如遇到問題，請參考:
1. PDF_EXPORT_GUIDE.md - 詳細指南
2. README.md - 快速參考
3. 代碼註釋 - 具體實現
4. 使用示例 - 實際用法

---

## 🎯 完成標準

所有項目完成後，可認為 PDF 導出系統已：

✅ **成功集成** - 所有文件部署完畢  
✅ **功能完整** - 7 步流程全部實現  
✅ **經過測試** - 所有功能驗證通過  
✅ **文檔齊全** - 提供詳細指南和示例  
✅ **生產就緒** - 可用於實際應用  

---

**檢查日期**: ____________  
**檢查人員**: ____________  
**最後驗證**: ____________  

---

**版本**: 1.0  
**最後更新**: 2024年
