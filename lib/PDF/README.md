# PDF 導出系統 - 快速參考

## 📁 文件結構

```
lib/PDF/
├── export_config.dart                 # STEP 1: 導出配置
├── export_metrics.dart                # STEP 3: 指標模型
├── export_metrics_calculator.dart     # STEP 2-3: 計算指標
├── summary_rule_engine.dart           # STEP 4: 摘要規則
├── pdf_page_builder.dart              # STEP 5: 頁面構建
├── pdf_export_service.dart            # STEP 6-7: 導出服務
├── pdf_generator_impl.dart            # STEP 6: PDF 實現
├── pdf_export_provider.dart           # 狀態管理
├── pdf_export_examples.dart           # 使用示例
├── PDF_EXPORT_GUIDE.md                # 詳細指南
└── README.md                          # 快速參考
```

## 🚀 快速開始

### 1. 添加依賴

```yaml
# pubspec.yaml
dependencies:
  pdf: ^3.10.0
  printing: ^5.11.0
  share_plus: ^7.2.0
```

### 2. 初始化 Provider

```dart
// main.dart
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

### 3. 基本使用

```dart
// 在任何頁面中
final provider = context.read<PDFExportProvider>();

final result = await provider.exportWithDefaultConfig(
  records: myRecords,
  outputDir: '/storage/emulated/0/Documents',
  medications: ['阿司匹林'],
  context: context,
);

if (result?.success == true) {
  print('PDF 已保存: ${result!.filePath}');
}
```

### 4. 使用 UI 組件

```dart
// 最簡單的方式
PDFExportButton(
  records: myRecords,
  medications: medications,
  onSuccess: () => print('成功'),
  onError: (error) => print('失敗: $error'),
)
```

## 📊 7 個步驟流程

```
STEP 0: 全域設定 (ExportConfig)
  ↓
STEP 1: 決定導出參數
  ↓
STEP 2: 擷取原始資料 (DailyRecord)
  ↓
STEP 3: 轉換成中介指標 (ExportMetrics)
  ├─ 情緒指標 (EmotionMetrics)
  ├─ 睡眠指標 (SleepMetrics)
  ├─ 症狀指標 (SymptomMetrics)
  └─ 文字指標 (DiaryTextMetrics)
  ↓
STEP 4: 套用摘要規則 (SummaryRuleEngine)
  ├─ 情緒趨勢判斷
  ├─ 高峰與波動判斷
  ├─ 睡眠×情緒關聯
  ├─ 症狀×情緒同時出現
  └─ 文字摘要選擇
  ↓
STEP 5: 組裝 PDF 頁面 (PDFPageBuilder)
  ├─ 第1頁: 總覽摘要
  ├─ 第2頁: 情緒趨勢
  ├─ 第3頁: 睡眠紀錄
  ├─ 第4頁: 藥物×症狀×情緒
  └─ 第5-6頁: 每日詳細摘要
  ↓
STEP 6: 產生 PDF (PDFGeneratorImpl)
  ↓
STEP 7: 輸出與分享
```

## 🔧 主要類別

### ExportConfig
```dart
// 預設：最近28天
final config = ExportConfig.defaultConfig();

// 自訂
final config = ExportConfig(
  startDate: DateTime(2024, 1, 1),
  endDate: DateTime(2024, 1, 28),
  includeDailyDetail: true,
);
```

### ExportMetrics
```dart
// 包含所有計算的指標
metrics.emotions          // List<EmotionMetrics>
metrics.topEmotions       // Top 3 核心情緒
metrics.sleepMetrics      // SleepMetrics
metrics.symptoms          // List<SymptomMetrics>
metrics.textMetrics       // DiaryTextMetrics
metrics.hasEmotionData    // 數據檢查
```

### PDFExportProvider
```dart
// 在 Consumer 或 context 中使用
provider.isExporting      // bool
provider.exportProgress   // double (0.0-1.0)
provider.error           // String?
provider.lastResult      // PDFExportResult?

// 方法
await provider.exportWithDefaultConfig(...)
await provider.exportRecordsToPDF(...)
provider.reset()
```

## 📋 PDF 頁面結構

### 頁面 1: 總覽摘要
```
匯出期間: YYYY年MM月DD日 至 YYYY年MM月DD日（28天）
核心情緒 Top3: 
  1. 情緒名: 平均X.X/10分, 出現X天 (趨勢)
  2. ...
睡眠摘要: 平均X.X小時 (評級), 波動程度, 短睡眠X晚
用藥清單: • 藥物1, • 藥物2...
AI關鍵發現: [生成的摘要文本]
```

### 頁面 2: 情緒趨勢
```
【情緒名】
平均分: X.X/10 | 最高分: X/10
前14天: X.X | 後14天: X.X | 變化: X.X (趨勢描述)
高峰(≥8分): X次 | 較高(≥7分): X次
```

### 頁面 3: 睡眠紀錄 (橫式)
```
平均睡眠時數: X.X 小時
最短/最長: X.X / X.X 小時
短睡眠天數: X
波動程度: X (標準差: X.X)

每日睡眠時數表:
1/1: 7.5h
1/2: 6.0h
...
```

### 頁面 4: 藥物×症狀×情緒
```
【用藥時間軸】
• 藥物1
• 藥物2

【症狀趨勢】
【症狀名】
高分次數: X | 與情緒重疊: X次 (X%)
→ 常於相近日期與高峰情緒同時出現/未見明顯同步
```

### 頁面 5-6: 每日詳細摘要
```
【MM月DD日 (星期)】
情緒: 情緒1 X/10, 情緒2 X/10
睡眠: X.X小時
症狀: 症狀1, 症狀2
備註: [日記內容]

【文字分析】
高頻關鍵詞: "詞" (X次)
主要主題: 睡眠相關
```

## 🎯 常用場景

### 場景 1: 在設定頁添加導出按鈕

```dart
ListTile(
  title: const Text('匯出醫療摘要'),
  onTap: () async {
    final provider = context.read<PDFExportProvider>();
    await provider.exportWithDefaultConfig(
      records: records,
      outputDir: '/storage/emulated/0/Documents',
      medications: medications,
      context: context,
    );
  },
)
```

### 場景 2: 首頁快速導出

```dart
FloatingActionButton(
  onPressed: () async {
    final provider = context.read<PDFExportProvider>();
    final result = await provider.exportWithDefaultConfig(
      records: records,
      outputDir: '/storage/emulated/0/Documents',
      medications: medications,
      context: context,
    );
    if (result?.success == true) {
      // 分享或打開 PDF
    }
  },
  child: const Icon(Icons.file_download),
)
```

### 場景 3: 自訂日期範圍

```dart
final config = ExportConfig(
  startDate: userSelectedStartDate,
  endDate: userSelectedEndDate,
  includeDailyDetail: true,
  includeLongDiary: false,
);

final result = await provider.exportRecordsToPDF(
  records: records,
  config: config,
  outputDir: outputDir,
  medications: medications,
  context: context,
);
```

### 場景 4: 帶進度顯示

```dart
Consumer<PDFExportProvider>(
  builder: (context, provider, _) {
    return Column(
      children: [
        LinearProgressIndicator(value: provider.exportProgress),
        Text('${(provider.exportProgress * 100).toInt()}%'),
      ],
    );
  },
)
```

## 🛠️ 自訂和擴展

### 修改關鍵詞列表

```dart
// export_metrics_calculator.dart
static const List<String> _sleepKeywords = [
  '睡眠', '睡覺', '入睡', '失眠', '夜裡', '早醒'
  // 添加你的關鍵詞
];
```

### 修改 PDF 樣式

```dart
// pdf_generator_impl.dart
// 修改 _buildTable() 或 _buildChartPlaceholder() 方法
```

### 添加新頁面

```dart
// pdf_page_builder.dart - 添加新方法
PDFPageContent buildCustomPage() {
  return PDFPageContent(
    title: '自訂頁面',
    content: '頁面內容',
    orientation: 'portrait',
  );
}

// pdf_export_service.dart - 在 _assemblePages() 中添加
pages.add(builder.buildCustomPage());
```

## 📱 檔案權限（Android）

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## 📦 檔名格式

```
心域_醫師摘要_YYYYMMDD-YYYYMMDD.pdf

示例: 心域_醫師摘要_20240101-20240128.pdf
```

## 🐛 調試技巧

### 查看詳細日誌
```
搜索 "debugPrint" 輸出
或者在 Android Studio 的 Logcat 中過濾 "PDF" 或 "📊"
```

### 檢查數據充分性
```dart
if (metrics.hasEmotionData) { /* ... */ }
if (metrics.hasSleepData) { /* ... */ }
if (metrics.hasSymptomData) { /* ... */ }
```

### 驗證計算結果
```dart
print(metrics.topEmotions);
print(metrics.sleepMetrics);
print(metrics.symptoms);
```

## ⚡ 性能優化

1. **非同步導出**: 在背景執行，不阻塞 UI
2. **進度報告**: `exportProgress` 提供實時反饋
3. **數據過濾**: 只處理指定日期範圍的數據
4. **記憶體管理**: PDF 生成後自動釋放

## 📚 相關文檔

- [詳細指南](PDF_EXPORT_GUIDE.md)
- [完整示例](pdf_export_examples.dart)
- [API 參考](#類別說明)

## 🔗 關鍵依賴

```yaml
provider: ^6.1.5+1     # 狀態管理
pdf: ^3.10.0           # PDF 生成
printing: ^5.11.0      # 列印支援
share_plus: ^7.2.0     # 分享功能
intl: ^0.20.2          # 國際化日期
```

---

**版本**: 1.0  
**最後更新**: 2024年  
**作者**: AI 助手
