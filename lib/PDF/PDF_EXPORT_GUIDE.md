# PDF 導出系統完整實現指南

## 目錄
1. [系統架構](#系統架構)
2. [核心模塊說明](#核心模塊說明)
3. [使用步驟](#使用步驟)
4. [集成方法](#集成方法)
5. [常見問題](#常見問題)

---

## 系統架構

```
┌─────────────────────────────────────────────────────────┐
│              PDF 導出系統 (7 個步驟)                     │
├─────────────────────────────────────────────────────────┤
│ STEP 0: 導出前的固定前提 (ExportConfig)                │
│ STEP 1: 決定導出參數 (ExportConfig)                     │
│ STEP 2: 擷取原始資料 (Raw Data Fetch)                  │
│ STEP 3: 轉換成中介指標 (ExportMetrics)                │
│ STEP 4: 套用摘要規則 (SummaryRuleEngine)              │
│ STEP 5: 組裝 PDF 頁面 (PDFPageBuilder)                │
│ STEP 6: 產生 PDF 檔案 (PDF 套件)                       │
│ STEP 7: 輸出與分享 (File Export)                      │
└─────────────────────────────────────────────────────────┘
```

---

## 核心模塊說明

### 1. `export_config.dart` - 導出配置
**責任**: 定義導出參數
```dart
// 使用預設配置（最近28天）
final config = ExportConfig.defaultConfig(
  includeDailyDetail: true,
  includeLongDiary: false,
);

// 自訂配置
final config = ExportConfig(
  startDate: DateTime(2024, 1, 1),
  endDate: DateTime(2024, 1, 28),
  reportType: 'doctor_summary',
  includeDailyDetail: false,
  includeLongDiary: false,
);
```

**輸出**:
- `startDate` - 開始日期
- `endDate` - 結束日期
- `reportType` - 報告類型 (doctor_summary)
- `durationDays` - 導出期間天數

---

### 2. `export_metrics.dart` - 指標模型
**責任**: 定義中介指標結構

#### 2-1. 情緒指標 (EmotionMetrics)
```
- name: 情緒名稱
- averageScore: 28天平均分數
- maxScore: 最高分
- highScoreCount: ≥7次數
- veryHighScoreCount: ≥8次數
- firstHalfAverage: 前14天平均
- secondHalfAverage: 後14天平均
- trend: 變化量（後-前）
- appearanceDays: 出現天數
- importanceScore: 重要度（平均分×出現天數）
```

#### 2-2. 睡眠指標 (SleepMetrics)
```
- averageDuration: 平均睡眠時數
- minDuration / maxDuration: 最短/最長
- shortSleepDays: <5小時天數
- standardDeviation: 波動程度
- volatilityLevel: 波動級別（小/中/大）
```

#### 2-3. 症狀指標 (SymptomMetrics)
```
- name: 症狀名稱
- highScoreCount: ≥7分次數
- emotionOverlapCount: 與情緒重疊次數
- overlapPercentage: 重疊比例（%）
- appearanceDays: 出現天數
- averageScore: 平均分數
```

#### 2-4. 文字分析指標 (DiaryTextMetrics)
```
- sleepRelated: 睡眠相關詞頻
- physicalDiscomfort: 身體不適詞頻
- rumination: 反覆思考詞頻
- emotionDescription: 情緒描述詞頻
- primaryTheme: 主要主題
- topKeyword: 最高頻詞
```

---

### 3. `export_metrics_calculator.dart` - 指標計算器
**責任**: STEP 2-3，從原始數據計算指標

```dart
final metrics = await ExportMetricsCalculator.calculateMetrics(
  records: dailyRecords,
  config: exportConfig,
);
```

**計算流程**:
1. `_calculateEmotionMetrics()` - 計算每種情緒的各項指標
2. `_calculateSleepMetrics()` - 計算睡眠統計
3. `_calculateSymptomMetrics()` - 計算症狀相關指標
4. `_calculateTextMetrics()` - 分析日記文本（分詞+分類）
5. `_calculateEmotionSleepCorrelation()` - 計算睡眠×情緒關聯
6. `_selectTopEmotions()` - 選出 Top 3 核心情緒

**輸出**: `ExportMetrics` 對象（包含所有指標 + 充分性檢查）

---

### 4. `summary_rule_engine.dart` - 摘要規則引擎
**責任**: STEP 4，套用選句規則生成摘要

#### 4-1. 情緒趨勢判斷
```dart
String analyzeTrend(EmotionMetrics emotion) {
  if (trend >= 1.0) return '上升';
  if (trend <= -1.0) return '下降';
  return '穩定';
}
```

#### 4-2. 高峰與波動判斷
```dart
// 檢查是否出現≥8分
// 檢查是否連續≥2天
// 檢查波動程度
```

#### 4-3. 睡眠×情緒關聯
```
IF <5小時天數 ≥ 6 
AND 隔日情緒平均 ↑ ≥ 0.8
→ 顯示「具有時間關聯」
```

#### 4-4. 症狀×情緒同時出現
```
IF 重疊比例 ≥ 50%
→ 使用「常於相近日期出現」
ELSE
→ 使用「未見明顯同步」
```

#### 4-5. 文字摘要選擇
```
IF 高頻詞集中於某類 
→ 顯示該類描述
ELSE
→ 顯示「未出現明顯集中主題」
```

**主要方法**:
```dart
String generateAISummary(ExportMetrics metrics)
  ↓ 返回完整的 AI 摘要文本
```

---

### 5. `pdf_page_builder.dart` - PDF 頁面構建器
**責任**: STEP 5，組裝各頁面內容

#### 頁面結構
```
頁面 1: 總覽摘要 (Portrait)
  ├─ 匯出期間
  ├─ 核心情緒 Top3
  ├─ 睡眠摘要
  ├─ 用藥清單
  └─ AI 關鍵發現

頁面 2: 情緒趨勢 (Portrait)
  ├─ 核心情緒折線圖
  └─ 其他情緒排行榜

頁面 3: 睡眠紀錄 (Landscape)
  ├─ 睡眠統計
  ├─ 睡眠圖表
  └─ 每日睡眠時數表

頁面 4: 藥物×症狀×情緒 (Landscape)
  ├─ 用藥時間軸
  ├─ 症狀趨勢
  └─ 關聯性分析

頁面 5-6: 每日詳細摘要 (Portrait)
  ├─ 每日記錄
  └─ 文字分析摘要
```

#### 使用方式
```dart
final builder = PDFPageBuilder(
  metrics: metrics,
  config: config,
  aiSummary: aiSummary,
  medications: medications,
  records: records,
);

final page1 = builder.buildOverviewPage();
final page2 = builder.buildEmotionTrendPage();
// ... 更多頁面
```

---

### 6. `pdf_export_service.dart` - PDF 導出服務
**責任**: STEP 6-7，生成 PDF 文件並輸出

#### 主要方法
```dart
Future<PDFExportResult> exportToPDF({
  required List<DailyRecord> records,
  required ExportConfig config,
  required String outputDir,
  List<String>? medications,
})
```

#### 流程
1. 計算指標（調用 ExportMetricsCalculator）
2. 生成摘要（調用 SummaryRuleEngine）
3. 組裝頁面（調用 PDFPageBuilder）
4. 生成 PDF（使用 pdf 套件）
5. 保存到設備

#### 檔名規則
```
心域_醫師摘要_YYYYMMDD-YYYYMMDD.pdf
```

#### 返回結果
```dart
class PDFExportResult {
  bool success;
  String? filePath;
  int? pageCount;
  ExportMetrics? metrics;
  String? error;
}
```

---

### 7. `pdf_export_provider.dart` - 狀態管理
**責任**: 集成 Provider，管理導出狀態

#### 主要屬性
```dart
bool isExporting;          // 是否正在導出
String? error;             // 錯誤訊息
PDFExportResult? lastResult; // 最後結果
double exportProgress;     // 導出進度（0.0-1.0）
```

#### 主要方法
```dart
// 完整導出
exportRecordsToPDF({
  required List<DailyRecord> records,
  required ExportConfig config,
  required String outputDir,
  List<String>? medications,
  required BuildContext context,
})

// 使用預設配置
exportWithDefaultConfig({
  required List<DailyRecord> records,
  required String outputDir,
  List<String>? medications,
  required BuildContext context,
})

// 重置狀態
reset()
```

---

## 使用步驟

### Step 1: 在 pubspec.yaml 中添加依賴

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.5+1
  intl: ^0.20.2
  collection: ^1.17.0
  
  # PDF 生成（需要添加）
  pdf: ^3.10.0
  printing: ^5.11.0
```

### Step 2: 初始化 Provider（在 main.dart）

```dart
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

### Step 3: 調用導出功能

#### 方法 A: 使用按鈕組件（推薦）
```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('導出')),
      body: Center(
        child: PDFExportButton(
          records: myRecords,
          medications: ['阿司匹林'],
          onSuccess: () {
            print('導出成功！');
          },
          onError: (error) {
            print('導出失敗: $error');
          },
        ),
      ),
    );
  }
}
```

#### 方法 B: 手動調用
```dart
final provider = context.read<PDFExportProvider>();

final result = await provider.exportWithDefaultConfig(
  records: myRecords,
  outputDir: '/storage/emulated/0/Documents',
  medications: ['用藥1'],
  context: context,
);

if (result?.success == true) {
  print('PDF 已保存: ${result!.filePath}');
}
```

#### 方法 C: 自訂配置
```dart
final config = ExportConfig(
  startDate: DateTime(2024, 1, 1),
  endDate: DateTime(2024, 1, 28),
  includeDailyDetail: true,
);

final result = await provider.exportRecordsToPDF(
  records: records,
  config: config,
  outputDir: outputDir,
  medications: medications,
  context: context,
);
```

### Step 4: 處理 PDF 套件集成

當前 `pdf_export_service.dart` 中的 `_generatePDF()` 方法為框架。需要：

1. 安裝 `pdf` 套件
2. 在 `_generatePDF()` 中實現實際的 PDF 生成邏輯

```dart
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

static Future<String> _generatePDF({
  required List<PDFPageContent> pages,
  required ExportConfig config,
  required String outputDir,
}) async {
  final pdf = pw.Document();
  
  for (final page in pages) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: page.orientation == 'landscape'
            ? pw.PageOrientation.landscape
            : pw.PageOrientation.portrait,
        build: (context) => [
          pw.Text(page.title),
          pw.SizedBox(height: 20),
          pw.Text(page.content),
        ],
      ),
    );
  }
  
  // 保存檔案
  final dir = Directory(outputDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  
  final fileName = _generateFileName(config);
  final filePath = '${dir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(await pdf.save());
  
  return filePath;
}
```

---

## 集成方法

### 在設定頁面中添加導出按鈕

```dart
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('匯出醫療摘要'),
            subtitle: const Text('導出最近28天的醫療摘要 PDF'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => _handleExport(context),
          ),
        ],
      ),
    );
  }

  void _handleExport(BuildContext context) async {
    // 1. 從 Provider 獲取記錄
    // final records = context.read<RecordProvider>().records;
    
    // 2. 調用導出
    final provider = context.read<PDFExportProvider>();
    await provider.exportWithDefaultConfig(
      records: records,
      outputDir: '/storage/emulated/0/Documents',
      medications: medications,
      context: context,
    );
  }
}
```

### 在首頁添加快速導出

```dart
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _quickExport(context),
        child: const Icon(Icons.file_download),
      ),
      // ...
    );
  }

  void _quickExport(BuildContext context) async {
    final provider = context.read<PDFExportProvider>();
    final config = ExportConfig.defaultConfig(includeDailyDetail: true);
    
    final result = await provider.exportRecordsToPDF(
      records: allRecords,
      config: config,
      outputDir: '/storage/emulated/0/Documents',
      medications: medicationList,
      context: context,
    );

    if (result?.success == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已導出: ${result!.filePath}'),
          action: SnackBarAction(
            label: '分享',
            onPressed: () => _shareFile(result.filePath!),
          ),
        ),
      );
    }
  }

  void _shareFile(String filePath) {
    // TODO: 使用 share_plus 分享文件
  }
}
```

---

## 常見問題

### Q1: 如何自訂 PDF 樣式？
**A**: 修改 `pdf_page_builder.dart` 中的 `buildxxxPage()` 方法，或在 `_generatePDF()` 中使用 `pdf` 套件的樣式參數。

### Q2: 如何處理沒有數據的情況？
**A**: `SummaryRuleEngine.shouldSkipPage()` 會檢查是否應該跳過某頁，`getNoDataMessage()` 提供相應提示。

### Q3: 如何修改關鍵詞列表？
**A**: 編輯 `export_metrics_calculator.dart` 中的：
- `_sleepKeywords`
- `_physicalKeywords`
- `_ruminationKeywords`
- `_emotionKeywords`

### Q4: 如何實現分享功能？
**A**: 使用 `share_plus` 套件：
```dart
import 'package:share_plus/share_plus.dart';

Share.shareXFiles([XFile(filePath)], text: '心域醫療摘要');
```

### Q5: 如何修改檔名格式？
**A**: 修改 `pdf_export_service.dart` 中的 `_generateFileName()` 方法。

### Q6: 支援中文嗎？
**A**: 支援。PDF 套件需要配置中文字體。參考：
```dart
pw.TextStyle(fontFamily: 'zh_CN') // 需要在項目中添加中文字體
```

---

## 調試提示

### 1. 查看詳細日誌
所有關鍵步驟都有 `debugPrint()` 輸出，便於追蹤流程。

### 2. 檢查數據充分性
```dart
final metrics = await ExportMetricsCalculator.calculateMetrics(...);
print(metrics.hasEmotionData);    // 是否有情緒數據
print(metrics.hasSleepData);      // 是否有睡眠數據
print(metrics.hasSymptomData);    // 是否有症狀數據
print(metrics.hasTextData);       // 是否有文字數據
```

### 3. 驗證指標計算
```dart
for (final emotion in metrics.topEmotions) {
  print('${emotion.name}: '
      'avg=${emotion.averageScore}, '
      'trend=${emotion.trend}, '
      'trendDesc=${emotion.trendDescription}');
}
```

### 4. 測試摘要生成
```dart
final summary = SummaryRuleEngine.generateAISummary(metrics);
print(summary);
```

---

## 下一步

1. **實現完整的 PDF 生成** - 在 `_generatePDF()` 中集成 `pdf` 套件
2. **添加圖表支持** - 使用 `fl_chart` 或 `pdf` 的圖表功能
3. **支援多語言** - 添加繁簡中文、英文等語言包
4. **分享功能** - 集成 `share_plus` 實現一鍵分享
5. **雲端備份** - 上傳到 Firebase Storage 或其他雲端存儲

---

**最後更新**: 2024 年
**作者**: AI 助手
