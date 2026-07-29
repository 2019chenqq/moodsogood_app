import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ai_batch_test_result.dart';
import '../services/ai_batch_dataset_service.dart';
import '../services/ai_batch_test_service.dart';
import '../services/ai_evaluation_file_action_service.dart';
import 'ai_batch_result_page.dart';

class AiBatchTesterScreen extends StatefulWidget {
  const AiBatchTesterScreen({super.key});

  @override
  State<AiBatchTesterScreen> createState() => _AiBatchTesterScreenState();
}

class _AiBatchTesterScreenState extends State<AiBatchTesterScreen> {
  final _datasetService = AiBatchDatasetService();
  late final AiBatchTestService _testService = AiBatchTestService(
    datasetService: _datasetService,
  );
  List<File> _datasets = const [];
  File? _selected;
  bool _loading = true;
  bool _running = false;
  int _completed = 0;
  int _total = 0;
  int _successes = 0;
  int _failures = 0;
  String? _message;
  AiBatchRunOutput? _output;

  @override
  void initState() {
    super.initState();
    _refreshDatasets();
  }

  Future<void> _refreshDatasets() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final files = await _datasetService.listFullDatasets();
      if (!mounted) return;
      setState(() {
        _datasets = files;
        _selected = files.isEmpty ? null : files.first;
      });
    } catch (error) {
      if (mounted) setState(() => _message = '讀取評測資料失敗：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    final selected = _selected;
    if (selected == null || _running) return;
    setState(() {
      _running = true;
      _completed = 0;
      _total = 0;
      _successes = 0;
      _failures = 0;
      _message = null;
      _output = null;
    });
    try {
      final dataset = await _datasetService.load(selected);
      if (!mounted) return;
      setState(() => _total = dataset.cases.length);
      final output = await _testService.run(
        dataset: dataset,
        onProgress: (completed, total, successes, failures) {
          if (!mounted) return;
          setState(() {
            _completed = completed;
            _total = total;
            _successes = successes;
            _failures = failures;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _output = output;
        _message = '批次測試完成，結果 JSON 已儲存。';
      });
    } catch (error, stackTrace) {
      debugPrint('AI batch test failed: $error\n$stackTrace');
      if (mounted) setState(() => _message = '批次測試失敗：$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('此功能僅限 Debug 模式。')));
    }
    final progress = _total == 0 ? null : _completed / _total;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 批次測試'),
        actions: [
          IconButton(
            onPressed: _running ? null : _refreshDatasets,
            tooltip: '重新整理',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '只讀取 ai_evaluation_exports 中的匿名模擬資料，並直接呼叫正式 '
            'AI Function。這會產生實際 AI API 用量。',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<File>(
            key: ValueKey(_selected?.path),
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: '選擇評測資料',
              border: OutlineInputBorder(),
            ),
            items: _datasets
                .map(
                  (file) => DropdownMenuItem(
                    value: file,
                    child: Text(
                      _fileName(file),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged:
                _running ? null : (value) => setState(() => _selected = value),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else if (_datasets.isEmpty) ...[
            const SizedBox(height: 12),
            const Text('找不到 ai_evaluation_full_*.json，請先產生評測資料。'),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _selected == null || _loading || _running ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(_running ? '測試中…' : '開始測試'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('目前：$_completed / $_total'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 12),
                  Text('成功：$_successes'),
                  Text('失敗：$_failures'),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(_message!),
                  ],
                ],
              ),
            ),
          ),
          if (_output != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✅ 測試完成'),
                    const SizedBox(height: 8),
                    Text(_fileName(File(_output!.filePath))),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AiBatchResultPage(
                                result: _output!.result,
                                resultFilePath: _output!.filePath,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.view_carousel_outlined),
                          label: const Text('查看結果'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              AiEvaluationFileActionService.shareFiles(
                            context,
                            [_output!.filePath],
                          ),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('分享 JSON'),
                        ),
                        IconButton(
                          onPressed: () =>
                              AiEvaluationFileActionService.copyPath(
                            context,
                            _output!.filePath,
                          ),
                          tooltip: '複製路徑',
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fileName(File file) => file.uri.pathSegments.last;
}
