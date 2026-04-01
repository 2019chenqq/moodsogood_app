import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/daily_record.dart';
import '../PDF/pdf_export_provider.dart';
import '../PDF/export_config.dart';
import '../PDF/export_metrics_calculator.dart';
import '../PDF/summary_rule_engine.dart';
import '../PDF/export_metrics.dart';

/// ============================================================
/// 導出報告頁面 - 包含預覽和導出功能
/// ============================================================
class ExportReportPage extends StatefulWidget {
  final List<DailyRecord> records;
  final List<String>? medications;

  const ExportReportPage({
    Key? key,
    required this.records,
    this.medications,
  }) : super(key: key);

  @override
  State<ExportReportPage> createState() => _ExportReportPageState();
}

class _ExportReportPageState extends State<ExportReportPage> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _includeDailyDetail = false;
  bool _includeLongDiary = false;
  ExportMetrics? _previewMetrics;
  String? _previewSummary;
  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 27)); // 28 天
    _loadPreview();
  }

  /// 加載報告預覽
  Future<void> _loadPreview() async {
    setState(() => _isLoadingPreview = true);

    try {
      final config = ExportConfig(
        startDate: _startDate,
        endDate: _endDate,
        includeDailyDetail: _includeDailyDetail,
        includeLongDiary: _includeLongDiary,
      );

      // 過濾指定日期範圍的記錄
      final filteredRecords = widget.records
          .where((r) =>
              r.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
              r.date.isBefore(_endDate.add(const Duration(days: 1))))
          .toList();

      // 計算指標
      final metrics = await ExportMetricsCalculator.calculateMetrics(
        records: filteredRecords,
        config: config,
      );

      // 生成摘要
      final summary = SummaryRuleEngine.generateAISummary(metrics);

      setState(() {
        _previewMetrics = metrics;
        _previewSummary = summary;
        _isLoadingPreview = false;
      });
    } catch (e) {
      setState(() => _isLoadingPreview = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('預覽加載失敗: $e')),
        );
      }
    }
  }

  /// 更改開始日期
  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: _endDate,
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _loadPreview();
    }
  }

  /// 更改結束日期
  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      _loadPreview();
    }
  }

  /// 執行導出
  void _handleExport() async {
    try {
      final provider = context.read<PDFExportProvider>();
      final config = ExportConfig(
        startDate: _startDate,
        endDate: _endDate,
        includeDailyDetail: _includeDailyDetail,
        includeLongDiary: _includeLongDiary,
      );

      // 獲取正確的輸出目錄
      final outputDir = await _getOutputDirectory();
      debugPrint('📂 PDF 將保存到: $outputDir');

      // 過濾指定日期範圍的記錄
      final filteredRecords = widget.records
          .where((r) =>
              r.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
              r.date.isBefore(_endDate.add(const Duration(days: 1))))
          .toList();

      final result = await provider.exportRecordsToPDF(
        records: filteredRecords,
        config: config,
        outputDir: outputDir,
        medications: widget.medications,
        context: context,
      );

      if (result?.success == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ PDF 已保存\n${result!.filePath}'),
              duration: const Duration(seconds: 5),
            ),
          );
          debugPrint('✅ PDF 導出成功: ${result.filePath}');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 導出失敗: ${result?.error}'),
              duration: const Duration(seconds: 5),
            ),
          );
          debugPrint('❌ PDF 導出失敗: ${result?.error}');
        }
      }
    } catch (e) {
      debugPrint('❌ 導出異常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 導出異常: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// 獲取輸出目錄（保存到內部存儲的 Documents 文件夾）
  Future<String> _getOutputDirectory() async {
    try {
      // 優先使用內部存儲的 Documents 文件夾
      final dir = Directory('/storage/emulated/0/Documents');
      
      // 確保目錄存在
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      debugPrint('📂 使用 Documents 文件夾: ${dir.path}');
      return dir.path;
    } catch (e) {
      debugPrint('⚠️ 無法獲取 Documents，改用應用文件夾: $e');
      try {
        // 備選方案：使用應用程式文件夾
        final appDir = await getApplicationDocumentsDirectory();
        final pdfDir = Directory('${appDir.path}/PDF');
        
        if (!await pdfDir.exists()) {
          await pdfDir.create(recursive: true);
        }
        
        debugPrint('📂 使用應用文件夾: ${pdfDir.path}');
        return pdfDir.path;
      } catch (e) {
        debugPrint('⚠️ 無法獲取應用文件夾，改用根目錄');
        return '/storage/emulated/0';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('匯出報告'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🎯 日期選擇區域
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.calendar_today, size: 16, color: Colors.black87),
                      SizedBox(width: 6),
                      Text(
                        '選擇報告期間',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateButton(
                          '開始日期',
                          _startDate,
                          _selectStartDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('~'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDateButton(
                          '結束日期',
                          _endDate,
                          _selectEndDate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '共 ${_endDate.difference(_startDate).inDays + 1} 天',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            // 📋 選項區域
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.settings, size: 16, color: Colors.black87),
                      SizedBox(width: 6),
                      Text(
                        '報告選項',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('包含每日詳細摘要'),
                    subtitle: const Text('在報告中添加逐日記錄'),
                    value: _includeDailyDetail,
                    onChanged: (value) {
                      setState(() => _includeDailyDetail = value ?? false);
                      _loadPreview();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('包含原始日記文本'),
                    subtitle: const Text('在報告中添加完整日記內容'),
                    value: _includeLongDiary,
                    onChanged: (value) {
                      setState(() => _includeLongDiary = value ?? false);
                      _loadPreview();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // 📊 預覽區域
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.preview, size: 16, color: Colors.black87),
                      SizedBox(width: 6),
                      Text(
                        '報告預覽',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard(),
                ],
              ),
            ),

            // 🔘 導出按鈕區域
            Padding(
              padding: const EdgeInsets.all(16),
              child: Consumer<PDFExportProvider>(
                builder: (context, provider, _) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: provider.isExporting ? null : _handleExport,
                          icon: provider.isExporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.file_download),
                          label: Text(
                            provider.isExporting ? '導出中...' : '導出 PDF 報告',
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      if (provider.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error, color: Colors.red),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    provider.error!,
                                    style:
                                        const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 構建日期選擇按鈕
  Widget _buildDateButton(
    String label,
    DateTime date,
    VoidCallback onPressed,
  ) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: const BorderSide(color: Colors.blue),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('yyyy/MM/dd').format(date),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  /// 構建預覽卡片
  Widget _buildPreviewCard() {
    if (_isLoadingPreview) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_previewMetrics == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text(
          '無法生成預覽，請檢查數據',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final metrics = _previewMetrics!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 情緒摘要
          _buildPreviewSection(
            Icons.mood,
            '情緒摘要',
            _buildEmotionPreview(metrics),
          ),
          const SizedBox(height: 16),

          // 睡眠摘要
          if (metrics.sleepMetrics != null)
            _buildPreviewSection(
              Icons.bedtime,
              '睡眠摘要',
              _buildSleepPreview(metrics),
            ),
          if (metrics.sleepMetrics != null) const SizedBox(height: 16),

          // 症狀摘要
          if (metrics.symptoms.isNotEmpty)
            _buildPreviewSection(
              Icons.local_hospital,
              '症狀摘要',
              _buildSymptomPreview(metrics),
            ),
          if (metrics.symptoms.isNotEmpty) const SizedBox(height: 16),

          // AI 摘要
          _buildPreviewSection(
            Icons.auto_awesome,
            '分析摘要',
            Text(
              _previewSummary ?? '無摘要',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建預覽段落
  Widget _buildPreviewSection(IconData icon, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.black87),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  /// 情緒預覽
  Widget _buildEmotionPreview(ExportMetrics metrics) {
    if (metrics.topEmotions.isEmpty) {
      return const Text('無情緒數據');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metrics.topEmotions.take(3).map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '平均: ${e.averageScore.toStringAsFixed(1)}/10 | 趨勢: ${e.trendDescription}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${e.appearanceDays} 天',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 睡眠預覽
  Widget _buildSleepPreview(ExportMetrics metrics) {
    final sleep = metrics.sleepMetrics!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _buildPreviewStat(
                '平均睡眠',
                '${sleep.averageDuration.toStringAsFixed(1)}h',
              ),
            ),
            Expanded(
              child: _buildPreviewStat(
                '短睡眠 (<5h)',
                '${sleep.shortSleepDays} 晚',
              ),
            ),
            Expanded(
              child: _buildPreviewStat(
                '波動程度',
                sleep.volatilityDescription,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 症狀預覽
  Widget _buildSymptomPreview(ExportMetrics metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metrics.symptoms.take(3).map((s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '高分: ${s.highScoreCount} 次',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              Text(
                s.hasSignificantOverlap ? '⚠️ 與情緒相關' : '無相關',
                style: TextStyle(
                  fontSize: 11,
                  color: s.hasSignificantOverlap ? Colors.orange : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 構建統計信息小卡片
  Widget _buildPreviewStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
