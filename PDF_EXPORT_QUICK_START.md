# ⚡ PDF 導出系統 - 5 分鐘快速開始

## 🎯 30 秒版本

你需要的一切已經創建完畢，**現在就可以使用**！

```dart
// 1️⃣ 在 main.dart 添加 Provider
ChangeNotifierProvider(create: (_) => PDFExportProvider())

// 2️⃣ 在頁面中使用按鈕
PDFExportButton(records: records, medications: meds)

// 完成！按下按鈕就能導出 PDF
```

---

## 📁 已創建的文件（9 個 Dart）

```
lib/PDF/
├── export_config.dart                   # 配置
├── export_metrics.dart                  # 指標模型
├── export_metrics_calculator.dart       # 計算引擎
├── summary_rule_engine.dart             # 規則引擎
├── pdf_page_builder.dart                # 頁面構建
├── pdf_export_service.dart              # 導出服務
├── pdf_generator_impl.dart              # PDF 實現
├── pdf_export_provider.dart             # Provider + UI 組件
└── pdf_export_examples.dart             # 使用示例
```

✅ **所有文件已創建完成**

---

## ⚙️ 3 步集成

### Step 1: 添加依賴 (30 秒)

```yaml
# pubspec.yaml - 已自動更新，但請驗證
dependencies:
  pdf: ^3.10.0
  printing: ^5.11.0
  share_plus: ^7.2.0
  collection: ^1.17.0
```

運行:
```bash
flutter pub get
```

### Step 2: 配置 Provider (1 分鐘)

```dart
// lib/main.dart
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

### Step 3: 使用 UI 組件 (1 分鐘)

```dart
// 任何頁面
import 'package:moodsogood_app/PDF/pdf_export_provider.dart';

class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: PDFExportButton(
          records: myRecords,
          medications: ['藥物1'],
          onSuccess: () => print('成功！'),
          onError: (error) => print('失敗: $error'),
        ),
      ),
    );
  }
}
```

---

## 🚀 立即使用

### 基本導出（推薦）
```dart
PDFExportButton(
  records: records,
  medications: medications,
)
```

### 自訂導出
```dart
final provider = context.read<PDFExportProvider>();

await provider.exportRecordsToPDF(
  records: records,
  config: ExportConfig(
    startDate: DateTime(2024, 1, 1),
    endDate: DateTime(2024, 1, 28),
    includeDailyDetail: true,
  ),
  outputDir: '/storage/emulated/0/Documents',
  medications: medications,
  context: context,
);
```

---

## 📋 檢查清單

- [ ] 已複製 lib/PDF/ 中的 9 個文件
- [ ] 已執行 `flutter pub get`
- [ ] 已在 main.dart 添加 Provider
- [ ] 已在頁面中導入和使用 PDFExportButton
- [ ] 已運行 `flutter run` 測試

---

## 🎯 完成！

**就這些！** 你現在已經擁有一個完整的 PDF 導出系統。

### 下一步（可選）

- 📖 閱讀 [README.md](lib/PDF/README.md) - 了解更多功能
- 📚 查看 [pdf_export_examples.dart](lib/PDF/pdf_export_examples.dart) - 看更多示例
- 🔍 閱讀 [PDF_EXPORT_GUIDE.md](lib/PDF/PDF_EXPORT_GUIDE.md) - 深入理解
- 🛠️ 參考 [PDF_EXPORT_TROUBLESHOOTING.md](PDF_EXPORT_TROUBLESHOOTING.md) - 排查問題

---

## ❓ 常見問題

### Q: 生成的 PDF 在哪裡？
**A**: 默認位置 `/storage/emulated/0/Documents/心晴_醫師摘要_*.pdf`

### Q: 支援多少天的數據？
**A**: 任意天數，默認最近 28 天

### Q: 可以自訂 PDF 內容嗎？
**A**: 可以，編輯 `pdf_page_builder.dart`

### Q: 支援什麼格式？
**A**: 只支援 PDF，但可擴展

### Q: 會上傳數據嗎？
**A**: 不會，所有數據本地處理

---

## 📞 需要幫助？

1. **編譯錯誤** → 查看 PDF_EXPORT_TROUBLESHOOTING.md
2. **不知道怎麼用** → 查看 pdf_export_examples.dart
3. **想了解細節** → 查看 lib/PDF/README.md
4. **想深入理解** → 查看 lib/PDF/PDF_EXPORT_GUIDE.md

---

## ✨ 功能亮點

✅ 自動計算 25+ 項指標  
✅ 智能生成 6 頁 PDF 報告  
✅ 支援情緒、睡眠、症狀、文字分析  
✅ 自動識別時間關聯  
✅ 實時進度顯示  
✅ 完善的錯誤處理  
✅ 支援分享功能  

---

**準備好了嗎？開始使用吧！** 🎉

記住：所有文件都已準備好，只需 3 步集成即可！
