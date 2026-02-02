# 🔧 PDF 導出系統 - 快速排查指南

## 🚨 常見問題快速解決

### ❌ 問題 1: 編譯錯誤 - 找不到文件

**症狀**:
```
Error: Could not find file 'lib/PDF/export_config.dart'
```

**解決方案**:
```bash
# 1. 確認文件已複製到正確位置
ls lib/PDF/

# 2. 檢查 pubspec.yaml 中是否有誤
flutter pub get

# 3. 清空緩存並重新編譯
flutter clean
flutter pub get
flutter run
```

**檢查清單**:
- [ ] 文件在 `lib/PDF/` 目錄中
- [ ] 文件名拼寫正確（大小寫敏感）
- [ ] 已執行 `flutter pub get`

---

### ❌ 問題 2: 編譯錯誤 - 導入失敗

**症狀**:
```
Error: Target of URI doesn't exist: 'package:moodsogood_app/PDF/export_config.dart'
```

**解決方案**:
```dart
// 確認導入路徑正確
import 'PDF/export_config.dart';           // ❌ 錯誤（相對路径）
import 'package:moodsogood_app/PDF/export_config.dart';  // ✅ 正確（絕對路徑）
```

**檢查清單**:
- [ ] 使用 `package:` 前綴的絕對路徑
- [ ] 應用名稱正確 (`moodsogood_app`)
- [ ] 模塊路徑正確 (`PDF/export_config.dart`)

---

### ❌ 問題 3: 運行時錯誤 - Provider 未初始化

**症狀**:
```
Error: Could not find the correct Provider<PDFExportProvider> above this widget
```

**解決方案**:
```dart
// ❌ 錯誤：在 main.dart 中沒有添加 Provider
void main() {
  runApp(const MyApp());  // 缺少 Provider
}

// ✅ 正確：使用 MultiProvider 包裝
void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PDFExportProvider()),
      ],
      child: const MyApp(),
    ),
  );
}
```

**檢查清單**:
- [ ] main.dart 中已導入 `PDFExportProvider`
- [ ] 使用 `MultiProvider` 或 `ChangeNotifierProvider`
- [ ] Provider 包裝了整個應用

---

### ❌ 問題 4: 運行時錯誤 - 權限拒絕

**症狀**:
```
Exception: Permission denied (os error 13)
FileSystemException: Cannot write file, path = '/storage/emulated/0/Documents/heart.pdf'
```

**解決方案**:

#### Android 6.0+ 運行時權限
```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> requestPermission() async {
  final status = await Permission.storage.request();
  if (status.isGranted) {
    // 有權限，可以導出
  } else {
    // 無權限，向用戶說明
  }
}
```

#### AndroidManifest.xml 配置
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

**檢查清單**:
- [ ] AndroidManifest.xml 已添加權限聲明
- [ ] Android 6.0+ 請求運行時權限
- [ ] 輸出目錄路徑正確

---

### ❌ 問題 5: PDF 無法生成 - 依賴缺失

**症狀**:
```
Error: Cannot import 'package:pdf/pdf.dart'
Error: Cannot import 'package:printing/printing.dart'
```

**解決方案**:
```bash
# 1. 添加依賴
flutter pub add pdf printing share_plus

# 2. 檢查 pubspec.yaml
cat pubspec.yaml | grep -E "pdf:|printing:|share_plus:"

# 3. 重新獲取依賴
flutter pub get

# 4. 重新編譯
flutter run
```

**檢查清單**:
- [ ] pubspec.yaml 中已添加 4 個依賴
- [ ] 版本號合理（不是 0.0.0）
- [ ] 已執行 `flutter pub get`

---

### ❌ 問題 6: PDF 生成失敗 - 輸出目錄不存在

**症狀**:
```
Exception: Cannot open file, path = '/invalid/path/to/pdf'
FileSystemException: Cannot create file, path = '/missing/directory/heart.pdf'
```

**解決方案**:
```dart
// ✅ 正確：生成之前創建目錄
final dir = Directory(outputPath);
if (!await dir.exists()) {
  await dir.create(recursive: true);
}

// ✅ 正確：使用系統推薦目錄
import 'package:path_provider/path_provider.dart';
final dir = await getApplicationDocumentsDirectory();
final outputPath = dir.path;
```

**檢查清單**:
- [ ] 輸出目錄已存在或會自動創建
- [ ] 目錄路徑不包含特殊字符
- [ ] 磁盤空間足夠 (> 10MB)

---

### ❌ 問題 7: 數據為空 - 沒有計算結果

**症狀**:
```
PDF 頁面只顯示「此期間無情緒數據」
```

**解決方案**:
```dart
// 1. 檢查原始數據
print('記錄數: ${records.length}');
for (final record in records) {
  print('日期: ${record.date}, 情緒: ${record.emotions.length}');
}

// 2. 檢查日期範圍
final config = ExportConfig.defaultConfig();
print('開始: ${config.startDate}, 結束: ${config.endDate}');

// 3. 驗證指標計算
final metrics = await ExportMetricsCalculator.calculateMetrics(
  records: records,
  config: config,
);
print('情緒數據: ${metrics.hasEmotionData}');
print('睡眠數據: ${metrics.hasSleepData}');
```

**檢查清單**:
- [ ] DailyRecord 數據正確加載
- [ ] 日期範圍包含有效記錄
- [ ] 情緒/睡眠/症狀數據有效值不為 0

---

### ❌ 問題 8: UI 卡頓 - 導出時界面凍結

**症狀**:
```
導出時 UI 無響應，進度條不動
```

**解決方案**:
```dart
// ❌ 錯誤：同步調用阻塞 UI
provider.exportWithDefaultConfig(...);  // 會卡頓

// ✅ 正確：使用 async/await
await provider.exportWithDefaultConfig(...);

// ✅ 更好：在背景執行
Future.microtask(() async {
  await provider.exportWithDefaultConfig(...);
});
```

**檢查清單**:
- [ ] 使用 `async/await` 非同步調用
- [ ] Consumer 監聽 `isExporting` 狀態
- [ ] Provider 正確調用 `notifyListeners()`

---

### ❌ 問題 9: 中文亂碼 - PDF 中文顯示混亂

**症狀**:
```
PDF 中文顯示為符號或空白
```

**解決方案**:
```dart
// 在 pdf_generator_impl.dart 中確保指定字體
pw.Text(
  content,
  style: pw.TextStyle(
    fontFamily: 'Times',  // 使用系統字體或自訂字體
    fontSize: 11,
  ),
)
```

**檢查清單**:
- [ ] Dart 源文件編碼為 UTF-8
- [ ] 文本使用中文字符（檢查原始數據）
- [ ] PDF 套件已配置中文字體（可選）

---

### ❌ 問題 10: 分享功敗 - Share 功能不工作

**症狀**:
```
Error: Unable to share files
Exception: Unhandled Exception: share_plus plugin not initialized
```

**解決方案**:
```bash
# 1. 添加依賴
flutter pub add share_plus

# 2. 更新 pubspec.yaml
# ✅ share_plus: ^7.2.0

# 3. 實現分享代碼
import 'package:share_plus/share_plus.dart';

Share.shareXFiles(
  [XFile(filePath)],
  text: '心晴醫療摘要',
);
```

**檢查清單**:
- [ ] 已安裝 `share_plus` 依賴
- [ ] PDF 文件路徑正確且存在
- [ ] 使用 XFile 而不是字符串路徑

---

## 📊 症狀診斷表

### 根據症狀查找原因

| 症狀 | 可能原因 | 解決方案 |
|------|---------|---------|
| 編譯失敗 | 文件缺失/導入錯誤 | 檢查文件位置和導入語句 |
| 運行時崩潰 | Provider 未初始化 | 在 main.dart 添加 Provider |
| PDF 生成失敗 | 權限或目錄問題 | 檢查權限和目錄存在 |
| 數據為空 | 原始數據為空 | 驗證 DailyRecord 數據 |
| UI 卡頓 | 同步調用 | 使用 async/await |
| 中文亂碼 | 字體或編碼問題 | 配置 PDF 字體 |
| 分享不工作 | 依賴缺失 | 安裝 share_plus |

---

## 🔍 調試技巧

### 1. 啟用詳細日誌
```dart
// 代碼中已包含 debugPrint
// 在 Android Studio logcat 中過濾
adb logcat | grep -i "PDF\|📊\|🚀\|❌"
```

### 2. 檢查 Provider 狀態
```dart
Consumer<PDFExportProvider>(
  builder: (context, provider, _) {
    print('isExporting: ${provider.isExporting}');
    print('progress: ${provider.exportProgress}');
    print('error: ${provider.error}');
    print('result: ${provider.lastResult}');
    return Container();
  },
)
```

### 3. 驗證數據
```dart
// 列出所有記錄
for (final record in records) {
  print('${record.date}: '
      '${record.emotions.length} 情緒, '
      '${record.sleep.durationHours}h 睡眠');
}
```

### 4. 追蹤計算
```dart
final metrics = await ExportMetricsCalculator.calculateMetrics(
  records: records,
  config: config,
);
print(metrics);  // 打印所有指標
```

### 5. 檢查文件
```bash
# 驗證生成的 PDF
adb shell ls -la /storage/emulated/0/Documents/
file /path/to/heart.pdf
```

---

## 📝 收集調試信息

遇到問題時，收集以下信息有助於快速解決：

```
1. Flutter 版本
   flutter --version

2. 依賴版本
   flutter pub deps

3. 錯誤堆疊追蹤
   [複製完整的錯誤信息]

4. logcat 輸出
   adb logcat | grep -i error

5. 代碼片段
   [導致問題的代碼]

6. 重現步驟
   [如何重現問題]
```

---

## 🆘 無法自己解決？

### 1. 查看文檔
- [ ] PDF_EXPORT_GUIDE.md - 詳細實現
- [ ] README.md - 快速參考
- [ ] 源代碼註釋 - 具體細節

### 2. 查看示例
- [ ] pdf_export_examples.dart - 使用示例
- [ ] INTEGRATION_CHECKLIST.md - 步驟清單

### 3. 運行測試
```bash
# 運行示例應用
flutter run lib/PDF/pdf_export_examples.dart

# 驗證編譯
flutter analyze
flutter pub get
```

---

## ✅ 診斷清單

遇到問題時，按順序檢查：

### 環境檢查
- [ ] Flutter 版本 >= 3.10.0
- [ ] Dart 版本 >= 3.3.0
- [ ] 依賴已安裝且無衝突
- [ ] Android SDK >= 21

### 代碼檢查
- [ ] 所有文件都已複製
- [ ] 導入語句正確
- [ ] Provider 已初始化
- [ ] 權限已配置

### 數據檢查
- [ ] DailyRecord 數據有效
- [ ] 日期範圍正確
- [ ] 有足夠的記錄數
- [ ] 情感/睡眠/症狀字段非空

### 邏輯檢查
- [ ] ExportConfig 配置正確
- [ ] 計算邏輯無誤
- [ ] 規則引擎輸出合理
- [ ] PDF 生成完成

### 輸出檢查
- [ ] 目錄存在且可寫
- [ ] PDF 文件已生成
- [ ] 文件大小合理 (> 100KB)
- [ ] 內容完整

---

## 🎯 常見誤區

### ❌ 誤區 1: 導入路徑
```dart
// ❌ 錯誤
import './export_config.dart';
import 'PDF/export_config.dart';

// ✅ 正確
import 'package:moodsogood_app/PDF/export_config.dart';
```

### ❌ 誤區 2: Provider 初始化位置
```dart
// ❌ 錯誤：在 widget 中初始化
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(...)  // 誤位置
  }
}

// ✅ 正確：在 main.dart 初始化
void main() {
  runApp(
    ChangeNotifierProvider(...)
  );
}
```

### ❌ 誤區 3: 同步調用
```dart
// ❌ 錯誤：阻塞 UI
provider.exportWithDefaultConfig(...);

// ✅ 正確：非同步調用
await provider.exportWithDefaultConfig(...);
```

### ❌ 誤區 4: 目錄路徑
```dart
// ❌ 錯誤：路徑不存在
'/nonexistent/directory/file.pdf'

// ✅ 正確：先創建或使用有效路徑
await Directory(outputPath).create(recursive: true);
```

---

## 📞 获得帮助

### 優先順序
1. 查看本排查指南
2. 查看 PDF_EXPORT_GUIDE.md
3. 查看代碼註釋和示例
4. 檢查 Android/iOS 配置
5. 運行 flutter analyze 和 flutter doctor

### 記錄日誌
```bash
# 獲取完整的調試日誌
flutter run -v > debug.log 2>&1

# 查看編譯錯誤
flutter build apk 2>&1 | tee build.log
```

---

**最後更新**: 2024年  
**版本**: 1.0  
**適用於**: Flutter 3.10+, Dart 3.3+
