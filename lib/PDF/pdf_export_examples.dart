import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/daily_record.dart';
import 'export_config.dart';
import 'pdf_export_provider.dart';
import '../analytics_service.dart';

/// ============================================================
/// PDF 導出集成示例
/// 展示如何在實際應用中使用 PDF 導出功能
/// ============================================================

/// 示例 1: 簡單的導出按鈕頁面
class SimplePDFExportPage extends StatelessWidget {
  final List<DailyRecord> allRecords;
  final List<String> medications;

  const SimplePDFExportPage({
    Key? key,
    required this.allRecords,
    required this.medications,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('導出醫療摘要'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.file_download,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                '導出最近 28 天的醫療摘要',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                '包含情緒趨勢、睡眠統計、症狀分析等詳細信息',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              PDFExportButton(
                records: allRecords,
                medications: medications,
                onSuccess: () {
                  // 導出成功
                },
                onError: (error) {
                  // 導出失敗
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 示例 2: 進階配置頁面
class AdvancedPDFExportPage extends StatefulWidget {
  final List<DailyRecord> allRecords;

  const AdvancedPDFExportPage({
    Key? key,
    required this.allRecords,
  }) : super(key: key);

  @override
  State<AdvancedPDFExportPage> createState() => _AdvancedPDFExportPageState();
}

class _AdvancedPDFExportPageState extends State<AdvancedPDFExportPage> {
  late DateTime startDate;
  late DateTime endDate;
  bool includeDailyDetail = false;
  bool includeLongDiary = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('advanced_pdf_export_page');
    endDate = DateTime.now();
    startDate = endDate.subtract(const Duration(days: 27));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('進階導出設定'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 日期範圍選擇
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '選擇日期範圍',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildDateSelector('開始日期', startDate, (newDate) {
                    setState(() => startDate = newDate);
                  }),
                  const SizedBox(height: 12),
                  _buildDateSelector('結束日期', endDate, (newDate) {
                    setState(() => endDate = newDate);
                  }),
                  const SizedBox(height: 12),
                  Text(
                    '共 ${endDate.difference(startDate).inDays + 1} 天',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 選項設定
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '導出選項',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('包含每日詳細摘要'),
                    subtitle: const Text('添加每天的詳細記錄'),
                    value: includeDailyDetail,
                    onChanged: (value) {
                      setState(() => includeDailyDetail = value ?? false);
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('包含原始長文日記'),
                    subtitle: const Text('包含完整的日記文本內容'),
                    value: includeLongDiary,
                    onChanged: (value) {
                      setState(() => includeLongDiary = value ?? false);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 導出按鈕
          Consumer<PDFExportProvider>(
            builder: (context, provider, _) {
              return SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: provider.isExporting ? null : _handleExport,
                  icon: provider.isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.file_download),
                  label: Text(
                    provider.isExporting ? '正在導出...' : '導出 PDF',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector(
    String label,
    DateTime date,
    Function(DateTime) onDateChanged,
  ) {
    return GestureDetector(
      onTap: () async {
        final newDate = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (newDate != null) {
          onDateChanged(newDate);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.year}年${date.month}月${date.day}日',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            const Icon(Icons.calendar_today, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _handleExport() async {
    final config = ExportConfig(
      startDate: startDate,
      endDate: endDate,
      reportType: 'doctor_summary',
      includeDailyDetail: includeDailyDetail,
      includeLongDiary: includeLongDiary,
    );

    final provider = context.read<PDFExportProvider>();
    final result = await provider.exportRecordsToPDF(
      records: widget.allRecords,
      config: config,
      outputDir: '/storage/emulated/0/Documents',
      context: context,
    );

    if (mounted) {
      if (result?.success == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 已保存: ${result!.filePath}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: '分享',
              onPressed: () {
                // TODO: 實現分享功能
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('導出失敗: ${result?.error ?? "未知錯誤"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// 示例 3: 導出歷史頁面
class ExportHistoryPage extends StatelessWidget {
  const ExportHistoryPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('導出歷史'),
      ),
      body: Consumer<PDFExportProvider>(
        builder: (context, provider, _) {
          if (provider.lastResult == null) {
            return const Center(
              child: Text('尚未導出任何 PDF'),
            );
          }

          final result = provider.lastResult!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '最後導出記錄',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('狀態', result.success ? '成功' : '失敗'),
                      _buildInfoRow('文件路徑', result.filePath ?? 'N/A'),
                      _buildInfoRow('頁面數', '${result.pageCount}'),
                      if (result.metrics != null) ...[
                        _buildInfoRow(
                          '情緒數據',
                          result.metrics!.hasEmotionData ? '有' : '無',
                        ),
                        _buildInfoRow(
                          '睡眠數據',
                          result.metrics!.hasSleepData ? '有' : '無',
                        ),
                        _buildInfoRow(
                          '症狀數據',
                          result.metrics!.hasSymptomData ? '有' : '無',
                        ),
                      ],
                      if (result.error != null)
                        _buildInfoRow('錯誤訊息', result.error!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  provider.reset();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('導出歷史已清除')),
                  );
                },
                icon: const Icon(Icons.delete),
                label: const Text('清除歷史'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// 示例 4: 在設定頁面中集成
class SettingsPageWithPDFExport extends StatelessWidget {
  final List<DailyRecord> records;

  const SettingsPageWithPDFExport({
    Key? key,
    required this.records,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          const ListTile(
            title: Text('一般設定'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('通知設定'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('隱私設定'),
            onTap: () {},
          ),
          const Divider(),
          const ListTile(
            title: Text('數據與備份'),
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('匯出醫療摘要'),
            subtitle: const Text('導出 PDF 醫療摘要（最近 28 天）'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SimplePDFExportPage(
                    allRecords: records,
                    medications: ['示例用藥'],
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('進階導出設定'),
            subtitle: const Text('自訂日期範圍和導出選項'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdvancedPDFExportPage(
                    allRecords: records,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('導出歷史'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ExportHistoryPage(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('關於'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// 示例 5: 完整的應用程式示例
class PDFExportDemoApp extends StatelessWidget {
  const PDFExportDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 示例數據
    final demoRecords = _generateDemoRecords();

    return MaterialApp(
      title: 'PDF 導出示例',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: ChangeNotifierProvider(
        create: (_) => PDFExportProvider(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('心域 - PDF 導出示例'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'PDF 導出功能示例',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildDemoCard(
                context,
                '簡單導出',
                '使用預設配置導出最近 28 天的數據',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SimplePDFExportPage(
                      allRecords: demoRecords,
                      medications: ['布洛芬', '阿司匹林'],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildDemoCard(
                context,
                '進階導出',
                '自訂日期範圍和導出選項',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdvancedPDFExportPage(
                      allRecords: demoRecords,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildDemoCard(
                context,
                '導出歷史',
                '查看之前的導出記錄',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ExportHistoryPage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildDemoCard(
                context,
                '設定頁面',
                '在應用設定中查看導出選項',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsPageWithPDFExport(
                      records: demoRecords,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoCard(
    BuildContext context,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }

  List<DailyRecord> _generateDemoRecords() {
    // 生成示例記錄
    final records = <DailyRecord>[];
    final now = DateTime.now();

    for (int i = 0; i < 28; i++) {
      final date = now.subtract(Duration(days: i));
      records.add(
        DailyRecord(
          id: date.toIso8601String().split('T')[0],
          date: date,
          emotions: [
            Emotion(name: '開心', value: (5 + (i % 4)).toInt()),
            Emotion(name: '焦慮', value: (3 + (i % 3)).toInt()),
          ],
          symptoms: ['頭痛', '失眠'],
          sleep: SleepData(
            sleepTime: const TimeOfDay(hour: 23, minute: 30),
            wakeTime: const TimeOfDay(hour: 7, minute: 30),
            quality: 7,
          ),
        ),
      );
    }

    return records;
  }
}
