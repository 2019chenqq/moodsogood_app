import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/daily_record.dart';
import 'pdf_export_service.dart';
import 'export_config.dart';

/// ============================================================
/// PDF 導出 Provider - 管理導出流程和狀態
/// ============================================================
class PDFExportProvider extends ChangeNotifier {
  bool isExporting = false;
  String? error;
  PDFExportResult? lastResult;
  double exportProgress = 0.0;

  /// 執行 PDF 導出
  Future<PDFExportResult?> exportRecordsToPDF({
    required List<DailyRecord> records,
    required ExportConfig config,
    required String outputDir,
    List<String>? medications,
    List<String>? followUpNotes,
  }) async {
    try {
      isExporting = true;
      error = null;
      exportProgress = 0.0;
      notifyListeners();

      debugPrint('🚀 PDF 導出開始');

      // 執行導出
      final result = await PDFExportService.exportToPDF(
        records: records,
        config: config,
        outputDir: outputDir,
        medications: medications,
        followUpNotes: followUpNotes,
      );

      lastResult = result;
      if (!result.success) {
        error = result.error;
      }

      exportProgress = 1.0;
      isExporting = false;
      notifyListeners();

      return result;
    } catch (e) {
      error = e.toString();
      isExporting = false;
      notifyListeners();
      return null;
    }
  }

  /// 使用預設配置導出（最近28天）
  Future<PDFExportResult?> exportWithDefaultConfig({
    required List<DailyRecord> records,
    required String outputDir,
    List<String>? medications,
    List<String>? followUpNotes,
  }) async {
    final config = ExportConfig.defaultConfig();
    return exportRecordsToPDF(
      records: records,
      config: config,
      outputDir: outputDir,
      medications: medications,
      followUpNotes: followUpNotes,
    );
  }

  /// 重置狀態
  void reset() {
    isExporting = false;
    error = null;
    lastResult = null;
    exportProgress = 0.0;
    notifyListeners();
  }
}

/// ============================================================
/// 使用示例
/// ============================================================
class PDFExportExample {
  /// 示例 1: 基本使用
  static void exampleBasicUsage(
    BuildContext context,
    List<DailyRecord> records,
  ) async {
    final provider = context.read<PDFExportProvider>();

    // 創建導出配置
    final config = ExportConfig.defaultConfig(
      includeDaily: true,
      includeDiary: false,
    );

    // 執行導出
    final result = await provider.exportRecordsToPDF(
      records: records,
      config: config,
      outputDir: '/storage/emulated/0/Documents',
      medications: ['阿司匹林', '布洛芬'],
    );

    if (!context.mounted) return;
    if (result?.success == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 已保存: ${result!.filePath}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('導出失敗: ${result?.error}')),
      );
    }
  }

  /// 示例 2: 自訂日期範圍
  static void exampleCustomDateRange(
    BuildContext context,
    List<DailyRecord> records,
  ) async {
    final startDate = DateTime.now().subtract(const Duration(days: 27));
    final endDate = DateTime.now();

    final config = ExportConfig(
      startDate: startDate,
      endDate: endDate,
      reportType: 'doctor_summary',
      includeDailyDetail: true,
      includeLongDiary: false,
    );
    // 注：這裡使用的是 ExportConfig 構造函數，參數名應該是類別屬性名
    // (includeDailyDetail, includeLongDiary) 是正確的

    final provider = context.read<PDFExportProvider>();
    final result = await provider.exportRecordsToPDF(
      records: records,
      config: config,
      outputDir: '/storage/emulated/0/Documents',
      medications: ['用藥1', '用藥2'],
    );

    debugPrint('導出結果: ${result?.toString()}');
  }

  /// 示例 3: 帶進度顯示
  static void exampleWithProgress(
    BuildContext context,
    List<DailyRecord> records,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('正在導出 PDF...'),
          content: Consumer<PDFExportProvider>(
            builder: (context, provider, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: provider.exportProgress,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '進度: ${(provider.exportProgress * 100).toStringAsFixed(0)}%',
                  ),
                  if (provider.error != null)
                    Text(
                      '錯誤: ${provider.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              );
            },
          ),
        );
      },
    );

    // 在背景執行導出
    final config = ExportConfig.defaultConfig();
    context
        .read<PDFExportProvider>()
        .exportRecordsToPDF(
          records: records,
          config: config,
          outputDir: '/storage/emulated/0/Documents',
        )
        .then((result) {
      if (!context.mounted) return;
      Navigator.pop(context);
      if (result?.success == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 已保存: ${result!.filePath}')),
        );
      }
    });
  }

  /// 示例 4: 設置 Provider
  static Widget setupProvider(Widget child) {
    return ChangeNotifierProvider(
      create: (_) => PDFExportProvider(),
      child: child,
    );
  }
}

/// ============================================================
/// UI 組件：導出按鈕
/// ============================================================
class PDFExportButton extends StatelessWidget {
  final List<DailyRecord> records;
  final List<String>? medications;
  final VoidCallback? onSuccess;
  final Function(String)? onError;

  const PDFExportButton({
    super.key,
    required this.records,
    this.medications,
    this.onSuccess,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PDFExportProvider>(
      builder: (context, provider, _) {
        return ElevatedButton.icon(
          onPressed: provider.isExporting
              ? null
              : () => _handleExport(context, provider),
          icon: provider.isExporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download),
          label: Text(provider.isExporting ? '導出中...' : '匯出 PDF'),
        );
      },
    );
  }

  void _handleExport(BuildContext context, PDFExportProvider provider) async {
    try {
      final result = await provider.exportWithDefaultConfig(
        records: records,
        outputDir: '/storage/emulated/0/Documents',
        medications: medications,
      );

      if (!context.mounted) return;
      if (result?.success == true) {
        onSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 已保存: ${result!.filePath}'),
            action: SnackBarAction(
              label: '開啟',
              onPressed: () {
                // TODO: 使用 open_file 打開 PDF
              },
            ),
          ),
        );
      } else {
        onError?.call(result?.error ?? '未知錯誤');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('導出失敗: ${result?.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      onError?.call(e.toString());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('導出異常: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
