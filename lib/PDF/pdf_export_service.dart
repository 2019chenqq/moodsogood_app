import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/daily_record.dart';
import 'export_config.dart';
import 'export_metrics.dart';
import 'export_metrics_calculator.dart';
import 'summary_rule_engine.dart';
import 'pdf_page_builder.dart';
import 'pdf_generator_impl.dart';

/// ============================================================
/// STEP 5-7: 完整的 PDF 導出服務
/// ============================================================
class PDFExportService {
  /// 主要導出入口
  static Future<PDFExportResult> exportToPDF({
    required List<DailyRecord> records,
    required ExportConfig config,
    required String outputDir,
    List<String>? medications, // 用藥清單
  }) async {
    try {
      debugPrint('🚀 開始 PDF 導出流程...');

      // STEP 2-3: 計算指標
      final metrics = await ExportMetricsCalculator.calculateMetrics(
        records: records,
        config: config,
      );
      debugPrint('✅ 指標計算完成');

      // STEP 4: 生成摘要
      final aiSummary = SummaryRuleEngine.generateAISummary(metrics);
      debugPrint('✅ 摘要生成完成');

      // STEP 5: 組裝頁面
      final pageBuilder = PDFPageBuilder(
        metrics: metrics,
        config: config,
        aiSummary: aiSummary,
        medications: medications ?? [],
        records: records,
      );

      final pages = _assemblePages(pageBuilder, metrics);
      debugPrint('✅ 已準備 ${pages.length} 頁面');

      // STEP 6: 產生 PDF
      final filePath = await _generatePDF(
        pages: pages,
        config: config,
        outputDir: outputDir,
      );
      debugPrint('✅ PDF 文件生成完成: $filePath');

      return PDFExportResult(
        success: true,
        filePath: filePath,
        pageCount: pages.length,
        metrics: metrics,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ PDF 導出失敗: $e');
      debugPrint('堆疊追蹤: $stackTrace');
      return PDFExportResult(
        success: false,
        error: e.toString(),
        metrics: null,
      );
    }
  }

  /// STEP 5: 組裝 PDF 頁面
  static List<PDFPageContent> _assemblePages(
    PDFPageBuilder builder,
    ExportMetrics metrics,
  ) {
    final pages = <PDFPageContent>[];

    // 第 1 頁：總覽摘要
    if (!SummaryRuleEngine.shouldSkipPage('overview', metrics)) {
      pages.add(builder.buildOverviewPage());
    }

    // 第 2 頁：情緒趨勢
    if (!SummaryRuleEngine.shouldSkipPage('emotion_trend', metrics)) {
      pages.add(builder.buildEmotionTrendPage());
    } else {
      pages.add(PDFPageContent(
        title: '情緒趨勢',
        content: SummaryRuleEngine.getNoDataMessage('emotion_trend'),
        orientation: 'portrait',
      ));
    }

    // 第 3 頁：睡眠紀錄
    if (!SummaryRuleEngine.shouldSkipPage('sleep', metrics)) {
      pages.add(builder.buildSleepPage());
    } else {
      pages.add(PDFPageContent(
        title: '睡眠紀錄',
        content: SummaryRuleEngine.getNoDataMessage('sleep'),
        orientation: 'landscape',
      ));
    }

    // 第 4 頁：藥物 × 症狀 × 情緒
    if (!SummaryRuleEngine.shouldSkipPage('symptoms', metrics)) {
      pages.add(builder.buildMedicationSymptomEmotionPage());
    }

    // 第 5-6 頁（選用）：每日摘要 + 文字備註
    if (metrics.hasEmotionData || metrics.hasSleepData) {
      pages.add(builder.buildDailyDetailPage());
    }

    return pages;
  }

  /// STEP 6: 產生 PDF 檔案
  static Future<String> _generatePDF({
    required List<PDFPageContent> pages,
    required ExportConfig config,
    required String outputDir,
  }) async {
    // 使用具體實現生成 PDF
    try {
      final filePath = await PDFGeneratorImpl.generatePDFFile(
        pages: pages,
        config: config,
        outputDir: outputDir,
      );
      return filePath;
    } catch (e) {
      debugPrint('❌ PDF 生成失敗: $e');
      rethrow;
    }
  }

  /// STEP 7: 生成檔名
  static String _generateFileName(ExportConfig config) {
    final formatter = DateFormat('yyyyMMdd');
    final startStr = formatter.format(config.startDate);
    final endStr = formatter.format(config.endDate);

    return '心晴_醫師摘要_$startStr-$endStr.pdf';
  }
}

/// ============================================================
/// PDF 頁面內容模型
/// ============================================================
class PDFPageContent {
  /// 頁面標題
  final String title;

  /// 頁面內容（可以是純文本或結構化數據）
  final String content;

  /// 頁面方向（"portrait" 或 "landscape"）
  final String orientation;

  /// 是否是數據表格
  final bool isTable;

  /// 表格數據（如果 isTable=true）
  final List<List<String>>? tableData;

  /// 是否是圖表
  final bool isChart;

  /// 圖表類型（"line" / "bar" / "pie"）
  final String? chartType;

  const PDFPageContent({
    required this.title,
    required this.content,
    this.orientation = 'portrait',
    this.isTable = false,
    this.tableData,
    this.isChart = false,
    this.chartType,
  });

  @override
  String toString() =>
      'PDFPageContent(title: $title, orientation: $orientation, isTable: $isTable)';
}

/// ============================================================
/// PDF 導出結果
/// ============================================================
class PDFExportResult {
  /// 是否成功
  final bool success;

  /// 文件路徑
  final String? filePath;

  /// 頁面數量
  final int? pageCount;

  /// 計算出的指標
  final ExportMetrics? metrics;

  /// 錯誤訊息
  final String? error;

  const PDFExportResult({
    required this.success,
    this.filePath,
    this.pageCount,
    this.metrics,
    this.error,
  });

  @override
  String toString() => 'PDFExportResult('
      'success: $success, '
      'pages: $pageCount, '
      'file: $filePath, '
      'error: $error)';
}
