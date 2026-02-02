import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'export_config.dart';
import 'export_metrics.dart';
import 'pdf_export_service.dart';

/// ============================================================
/// PDF 具體實現 - 使用 pdf 套件生成真實 PDF 文件
/// ============================================================
class PDFGeneratorImpl {
  /// 生成 PDF 文件（具體實現）
  static Future<String> generatePDFFile({
    required List<PDFPageContent> pages,
    required ExportConfig config,
    required String outputDir,
  }) async {
    try {
      debugPrint('📄 開始生成 PDF...');

      // 1. 創建 PDF 文檔
      final pdf = pw.Document(
        pageMode: PdfPageMode.outlines,
        theme: pw.ThemeData(
          defaultTextStyle: pw.TextStyle(
            font: pw.Font.helvetica(),
            fontSize: 11,
          ),
        ),
      );

      // 2. 為每個頁面添加內容
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        debugPrint('📄 添加第 ${i + 1} 頁: ${page.title}');

        pdf.addPage(
          pw.MultiPage(
            pageFormat: page.orientation == 'landscape'
                ? PdfPageFormat.a4.landscape
                : PdfPageFormat.a4.portrait,
            margin: const pw.EdgeInsets.all(40),
            build: (context) => [
              // 頁面標題
              pw.Text(
                page.title,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),

              // 頁面內容
              if (page.isTable && page.tableData != null)
                _buildTable(page.tableData!)
              else if (page.isChart)
                _buildChartPlaceholder(page.chartType)
              else
                pw.Text(
                  page.content,
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: 11),
                ),

              // 頁腳
              pw.Spacer(),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '心晴醫療摘要',
                    style: pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    '第 ${i + 1} 頁',
                    style: pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      }

      // 3. 確保輸出目錄存在
      final dir = Directory(outputDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 4. 生成檔名和路徑
      final fileName = _generateFileName(config);
      final filePath = '${dir.path}/$fileName';

      // 5. 保存 PDF 文件
      final file = File(filePath);
      final bytes = await pdf.save();
      await file.writeAsBytes(bytes);

      debugPrint('✅ PDF 文件已保存: $filePath (${bytes.length} 字節)');
      return filePath;
    } catch (e) {
      debugPrint('❌ PDF 生成失敗: $e');
      rethrow;
    }
  }

  /// 構建表格
  static pw.Widget _buildTable(List<List<String>> data) {
    if (data.isEmpty) {
      return pw.Text('無表格數據');
    }

    return pw.Table.fromTextArray(
      data: data,
      border: pw.TableBorder.all(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 10,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.grey700,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      rowDecoration: pw.BoxDecoration(
        border: pw.Border.all(),
      ),
    );
  }

  /// 圖表佔位符（實際應使用 fl_chart 或其他圖表庫）
  static pw.Widget _buildChartPlaceholder(String? chartType) {
    final typeStr = chartType ?? 'unknown';
    return pw.Center(
      child: pw.Text(
        '[圖表位置]\n$typeStr 圖表\n(需要集成圖表庫)',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(color: PdfColors.grey),
      ),
    );
  }

  /// 生成檔名
  static String _generateFileName(ExportConfig config) {
    final formatter = DateFormat('yyyyMMdd');
    final startStr = formatter.format(config.startDate);
    final endStr = formatter.format(config.endDate);
    return '心晴_醫師摘要_$startStr-$endStr.pdf';
  }
}

/// ============================================================
/// 增強版：支援圖表和更複雜的格式
/// ============================================================
class AdvancedPDFGenerator {
  /// 生成帶有圖表的 PDF
  static Future<String> generatePDFWithCharts({
    required List<PDFPageContent> pages,
    required ExportConfig config,
    required String outputDir,
    required ExportMetrics metrics,
  }) async {
    try {
      debugPrint('📊 開始生成帶圖表的 PDF...');

      final pdf = pw.Document();

      // 使用 PDFGeneratorImpl 處理基本內容
      // 然後在 build 中添加自訂圖表

      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];

        pdf.addPage(
          pw.MultiPage(
            pageFormat: page.orientation == 'landscape'
                ? PdfPageFormat.a4.landscape
                : PdfPageFormat.a4.portrait,
            margin: const pw.EdgeInsets.all(40),
            build: (context) => [
              // 頁面標題
              pw.Text(
                page.title,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),

              // 根據頁面類型生成特殊內容
              if (page.title == '情緒趨勢分析')
                _buildEmotionTrendContent(metrics)
              else if (page.title == '睡眠紀錄')
                _buildSleepContent(metrics)
              else if (page.title == '用藥、症狀與情緒關聯')
                _buildMedicationContent(metrics)
              else
                pw.Text(page.content),

              // 頁腳
              pw.Spacer(),
              pw.Divider(),
              pw.Text(
                '心晴醫療摘要 - 第 ${i + 1} 頁',
                style: pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        );
      }

      // 保存文件
      final dir = Directory(outputDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileName = _generateAdvancedFileName(config);
      final filePath = '${dir.path}/$fileName';
      final bytes = await pdf.save();
      await File(filePath).writeAsBytes(bytes);

      debugPrint('✅ 高級 PDF 已保存: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ 高級 PDF 生成失敗: $e');
      rethrow;
    }
  }

  /// 情緒趨勢內容
  static pw.Widget _buildEmotionTrendContent(ExportMetrics metrics) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (metrics.topEmotions.isNotEmpty)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: metrics.topEmotions.map((emotion) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${emotion.name}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '平均分: ${emotion.averageScore.toStringAsFixed(1)}/10 | '
                    '最高分: ${emotion.maxScore}/10 | '
                    '變化: ${emotion.trend.toStringAsFixed(1)} (${emotion.trendDescription})',
                  ),
                  pw.Text(
                    '前14天: ${emotion.firstHalfAverage.toStringAsFixed(1)} → '
                    '後14天: ${emotion.secondHalfAverage.toStringAsFixed(1)}',
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }).toList(),
          ),
      ],
    );
  }

  /// 睡眠內容
  static pw.Widget _buildSleepContent(ExportMetrics metrics) {
    if (metrics.sleepMetrics == null) {
      return pw.Text('無睡眠數據');
    }

    final sleep = metrics.sleepMetrics!;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('平均睡眠時數: ${sleep.averageDuration.toStringAsFixed(1)} 小時'),
        pw.Text(
          '最短: ${sleep.minDuration.toStringAsFixed(1)}h | '
          '最長: ${sleep.maxDuration.toStringAsFixed(1)}h',
        ),
        pw.Text('短睡眠 (<5h): ${sleep.shortSleepDays} 晚'),
        pw.Text('波動程度: ${sleep.volatilityDescription}'),
        pw.SizedBox(height: 10),
        pw.Text(
          '睡眠時數分布:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        // 簡單的睡眠時數列表
        pw.Column(
          children: sleep.allDurations
              .asMap()
              .entries
              .map(
                (entry) => pw.Text(
                  '第 ${entry.key + 1} 天: ${entry.value.toStringAsFixed(1)}h',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// 用藥內容
  static pw.Widget _buildMedicationContent(ExportMetrics metrics) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '症狀分析:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        if (metrics.symptoms.isNotEmpty)
          pw.Column(
            children: metrics.symptoms.map((symptom) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${symptom.name}: '
                    '高分${symptom.highScoreCount}次, '
                    '與情緒重疊${symptom.emotionOverlapCount}次 '
                    '(${symptom.overlapPercentage.toStringAsFixed(0)}%)',
                  ),
                  if (symptom.hasSignificantOverlap)
                    pw.Text(
                      '→ 常於相近日期與高峰情緒同時出現',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.orange,
                      ),
                    )
                  else
                    pw.Text(
                      '→ 未見與情緒明顯同步',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  pw.SizedBox(height: 5),
                ],
              );
            }).toList(),
          )
        else
          pw.Text('無症狀數據'),
      ],
    );
  }

  static String _generateAdvancedFileName(ExportConfig config) {
    final formatter = DateFormat('yyyyMMdd');
    final startStr = formatter.format(config.startDate);
    final endStr = formatter.format(config.endDate);
    return '心晴_醫師摘要_高級_$startStr-$endStr.pdf';
  }
}

/// ============================================================
/// 使用示例
/// ============================================================
class PDFGeneratorExample {
  /// 使用基礎生成器
  static Future<void> exampleBasicGeneration(
    List<PDFPageContent> pages,
    ExportConfig config,
    String outputDir,
  ) async {
    try {
      final filePath = await PDFGeneratorImpl.generatePDFFile(
        pages: pages,
        config: config,
        outputDir: outputDir,
      );
      debugPrint('✅ PDF 已生成: $filePath');
    } catch (e) {
      debugPrint('❌ 生成失敗: $e');
    }
  }

  /// 使用高級生成器（帶圖表）
  static Future<void> exampleAdvancedGeneration(
    List<PDFPageContent> pages,
    ExportConfig config,
    ExportMetrics metrics,
    String outputDir,
  ) async {
    try {
      final filePath = await AdvancedPDFGenerator.generatePDFWithCharts(
        pages: pages,
        config: config,
        outputDir: outputDir,
        metrics: metrics,
      );
      debugPrint('✅ 高級 PDF 已生成: $filePath');
    } catch (e) {
      debugPrint('❌ 生成失敗: $e');
    }
  }
}
