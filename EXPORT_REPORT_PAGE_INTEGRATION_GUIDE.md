# 📋 導出報告頁面 - 集成指南

## 🎯 概述

已為你建立了一個完整的 **導出報告頁面** (`lib/pages/export_report_page.dart`)，包含：

✅ 日期範圍選擇
✅ 報告選項配置
✅ 實時報告預覽
✅ PDF 導出功能
✅ 完整的 UI 設計

---

## 🚀 3 步快速集成

### Step 1: 導入頁面（在導航中）

在你的 `Home_shell.dart` 或導航文件中，添加該頁面到導航菜單：

```dart
import 'pages/export_report_page.dart';

// 在菜單或按鈕中
ListTile(
  leading: Icon(Icons.file_download),
  title: Text('匯出報告'),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExportReportPage(
        records: records,  // 傳入所有日記記錄
        medications: medications,  // 傳入用藥列表
      ),
    ),
  ),
)
```

### Step 2: 在設置頁面添加

```dart
// lib/settings_page.dart
import 'package:moodsogood_app/pages/export_report_page.dart';

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // ... 其他設置項
        
        ListTile(
          leading: Icon(Icons.assessment),
          title: Text('匯出醫療報告'),
          trailing: Icon(Icons.arrow_forward),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExportReportPage(
                records: recordsFromProvider,
                medications: medicationsFromProvider,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Step 3: 在首頁添加快速按鈕

```dart
// lib/Home_shell.dart
FloatingActionButton(
  heroTag: 'export_report',
  child: Icon(Icons.file_download),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExportReportPage(
        records: _records,
        medications: _medications,
      ),
    ),
  ),
)
```

---

## 📋 功能詳解

### 1️⃣ 日期範圍選擇

- 默認為最近 **28 天**
- 支援自訂開始和結束日期
- 實時計算天數

### 2️⃣ 報告選項

```
☐ 包含每日詳細摘要  → 添加逐日記錄到 PDF
☐ 包含原始日記文本  → 添加完整日記內容到 PDF
```

### 3️⃣ 實時報告預覽

顯示將被導出的數據：
- 😊 **情緒摘要** - 前 3 個主要情緒
  - 平均分、趨勢、出現天數
- 😴 **睡眠摘要** - 睡眠統計
  - 平均時數、短睡眠次數、波動程度
- 🏥 **症狀摘要** - 前 3 個主要症狀
  - 高分次數、與情緒的相關性
- 🤖 **分析摘要** - AI 智能分析結果

### 4️⃣ 導出功能

- 點擊「導出 PDF 報告」按鈕
- 自動計算所有指標
- 生成 PDF 文件
- 保存到 `/storage/emulated/0/Documents/`
- 顯示成功或失敗消息

---

## 📱 完整使用流程

```
1. 進入「匯出報告」頁面
   ↓
2. 選擇報告期間（日期範圍）
   ↓
3. 勾選所需的報告選項
   ↓
4. 查看預覽（實時生成）
   ↓
5. 點擊「導出 PDF 報告」
   ↓
6. 等待導出完成
   ↓
7. 查看成功消息和文件路徑
```

---

## 🎨 UI 組件說明

### 頁面結構

```
┌─────────────────────────────────┐
│  頂部：AppBar (標題)             │
├─────────────────────────────────┤
│  藍色區域：日期選擇               │
│  ┌─────────────────────────────┐ │
│  │ 開始日期  ~  結束日期        │ │
│  │ 共 28 天                    │ │
│  └─────────────────────────────┘ │
├─────────────────────────────────┤
│  白色區域：報告選項               │
│  ☐ 包含每日詳細摘要             │
│  ☐ 包含原始日記文本             │
├─────────────────────────────────┤
│  白色卡片：報告預覽               │
│  😊 情緒摘要                    │
│  😴 睡眠摘要                    │
│  🏥 症狀摘要                    │
│  🤖 分析摘要                    │
├─────────────────────────────────┤
│  藍色按鈕：導出 PDF 報告          │
│  (導出中時會顯示進度條)          │
└─────────────────────────────────┘
```

---

## 🔧 自訂選項

### 改變默認日期範圍

在 `export_report_page.dart` 第 27 行：

```dart
// 改為 14 天（兩週）
_startDate = _endDate.subtract(const Duration(days: 13));

// 改為 90 天（三個月）
_startDate = _endDate.subtract(const Duration(days: 89));
```

### 改變輸出目錄

在 `_handleExport()` 方法中：

```dart
// 改為自訂路徑
outputDir: '/your/custom/path',

// 或使用應用程式目錄
outputDir: getApplicationDocumentsDirectory(),
```

### 隱藏某個預覽段落

在 `_buildPreviewCard()` 方法中註解相應段落：

```dart
// 隱藏症狀預覽
// if (metrics.symptoms.isNotEmpty)
//   _buildPreviewSection(...)
```

---

## ⚙️ 配置說明

### ExportConfig 參數

```dart
ExportConfig(
  startDate: DateTime(2024, 1, 1),        // 開始日期
  endDate: DateTime(2024, 1, 28),         // 結束日期
  includeDailyDetail: true,               // 包含每日摘要
  includeLongDiary: false,                // 包含原始日記
  reportType: 'doctor_summary',           // 報告類型（固定）
  tone: 'medical',                        // 語氣（固定）
)
```

### 導出結果結構

```dart
PDFExportResult(
  success: true,
  filePath: '/storage/emulated/0/Documents/心域_醫師摘要_20240101-20240128.pdf',
  pageCount: 6,
  metrics: ExportMetrics(...),
  error: null,
)
```

---

## 🐛 常見問題

### Q1: 預覽不更新？
**A**: 確保已實現 `setState(() => _loadPreview())` 在選項改變時調用。

### Q2: 預覽加載很慢？
**A**: 檢查 `ExportMetricsCalculator.calculateMetrics()` 的性能，可能需要優化。

### Q3: 如何從 Provider 獲取記錄？
**A**: 在頁面中使用 `context.read<YourRecordProvider>().records`

### Q4: 可以預先填入日期嗎？
**A**: 可以，在頁面構造函數中添加參數：
```dart
class ExportReportPage extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  
  @override
  void initState() {
    _startDate = widget.initialStartDate ?? ...;
    _endDate = widget.initialEndDate ?? ...;
  }
}
```

---

## 📊 預覽內容詳解

### 情緒摘要顯示
- 排序：按重要性（平均分 × 天數）
- 取顯示：前 3 個情緒
- 內容：名稱、平均分、趨勢、出現天數

### 睡眠摘要顯示
- 平均睡眠時長（小時）
- 短睡眠（<5h）的天數
- 波動程度（小/中/大）

### 症狀摘要顯示
- 排序：按出現頻率
- 取顯示：前 3 個症狀
- 內容：高分次數、與情緒相關性

### 分析摘要顯示
- 自動生成的 AI 分析文本
- 包含 5 個分析維度：
  1. 情緒趨勢
  2. 高峰情緒
  3. 睡眠-情緒關聯
  4. 症狀-情緒關聯
  5. 文本主題

---

## 🎁 額外功能

### 想添加更多預覽內容？

1. 在 `ExportMetrics` 中添加新指標
2. 在 `_buildPreviewCard()` 添加新段落
3. 建立對應的 `_buildXxxPreview()` 方法

### 想改變預覽樣式？

修改 `_buildPreviewSection()` 和相關小部件的樣式參數

### 想添加導出歷史？

可以使用 `Consumer<PDFExportProvider>` 存取 `lastResult` 並顯示歷史記錄

---

## 📞 需要幫助？

如有問題，檢查：
1. ✅ 已導入所有必要的類（dailyRecord、provider 等）
2. ✅ 已在 main.dart 配置 PDFExportProvider
3. ✅ 已傳入正確的 records 和 medications 參數
4. ✅ 日期範圍有效（開始日期 ≤ 結束日期）
5. ✅ 檔案輸出路徑有讀寫權限

---

**現在你已經擁有一個完整的報告匯出系統！** 🎉
