import 'package:flutter/material.dart';

/// ============================================================
/// STEP 1: 導出配置模型 (Export Config)
/// ============================================================
/// 一旦確定，後面所有流程都用同一份設定
class ExportConfig {
  /// 導出的開始日期
  final DateTime startDate;

  /// 導出的結束日期
  final DateTime endDate;

  /// 報告類型（預設為醫師版摘要）
  final String reportType; // "doctor_summary"

  /// 是否包含每日詳細摘要
  final bool includeDailyDetail;

  /// 是否包含原始長文日記
  final bool includeLongDiary;

  /// 語氣（客觀醫療描述）
  final String tone; // "medical"

   ExportConfig({
    required this.startDate,
    required this.endDate,
    this.reportType = 'doctor_summary',
    this.includeDailyDetail = false,
    this.includeLongDiary = false,
    this.tone = 'medical',
  }) : assert(
          startDate.isBefore(endDate) || startDate.isAtSameMomentAs(endDate),
          '開始日期必須在結束日期之前或相同');

  /// 取得導出期間天數
  int get durationDays => endDate.difference(startDate).inDays + 1;

  /// 產生預設配置（最近28天）
  factory ExportConfig.defaultConfig({
    DateTime? baseDate,
    bool includeDaily = false,
    bool includeDiary = false,
  }) {
    final now = baseDate ?? DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day); // 今天
    final startDate = endDate.subtract(const Duration(days: 27)); // 往前27天 = 28天期間

    return ExportConfig(
      startDate: startDate,
      endDate: endDate,
      reportType: 'doctor_summary',
      includeDailyDetail: includeDaily,
      includeLongDiary: includeDiary,
      tone: 'medical',
    );
  }

  /// 複製並修改配置
  ExportConfig copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? reportType,
    bool? includeDailyDetail,
    bool? includeLongDiary,
    String? tone,
  }) {
    return ExportConfig(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      reportType: reportType ?? this.reportType,
      includeDailyDetail: includeDailyDetail ?? this.includeDailyDetail,
      includeLongDiary: includeLongDiary ?? this.includeLongDiary,
      tone: tone ?? this.tone,
    );
  }

  @override
  String toString() => 'ExportConfig('
      'startDate: $startDate, '
      'endDate: $endDate, '
      'reportType: $reportType, '
      'includeDailyDetail: $includeDailyDetail, '
      'includeLongDiary: $includeLongDiary, '
      'tone: $tone)';
}
