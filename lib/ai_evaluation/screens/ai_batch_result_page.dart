import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/ai_batch_test_result.dart';

class AiBatchResultPage extends StatefulWidget {
  const AiBatchResultPage({
    required this.result,
    required this.resultFilePath,
    super.key,
  });

  final AiBatchTestResult result;
  final String resultFilePath;

  @override
  State<AiBatchResultPage> createState() => _AiBatchResultPageState();
}

class _AiBatchResultPageState extends State<AiBatchResultPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 批次測試結果')),
      body: Column(
        children: [
          _StatisticsCard(result: result),
          if (result.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text('${_index + 1} / ${result.results.length}'),
                  const Spacer(),
                  const Icon(Icons.swipe, size: 18),
                  const SizedBox(width: 6),
                  const Text('左右滑動切換案例'),
                ],
              ),
            ),
          Expanded(
            child: result.results.isEmpty
                ? const Center(child: Text('沒有測試結果。'))
                : PageView.builder(
                    itemCount: result.results.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) =>
                        _CaseResultView(item: result.results[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.result});

  final AiBatchTestResult result;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text('案例數：${result.results.length}'),
                  Text('成功：${result.successCount}'),
                  Text('失敗：${result.failureCount}'),
                  Text(
                    '平均回覆時間：'
                    '${result.averageElapsedMs.toStringAsFixed(0)} ms',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '模型：${result.model}　Prompt：${result.promptVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _CaseResultView extends StatelessWidget {
  const _CaseResultView({required this.item});

  final AiBatchCaseResult item;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.caseId,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Icon(
                      item.success ? Icons.check_circle : Icons.error,
                      color: item.success ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text('${item.elapsedMs} ms'),
                  ],
                ),
                const Divider(height: 28),
                Text('【原始資料】', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(item.input),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const Divider(height: 32),
                Text('【AI 回覆】', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(
                  item.success ? item.response : '執行失敗：${item.error ?? '未知錯誤'}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Tokens：輸入 ${item.inputTokens?.toString() ?? '未提供'} / '
                  '輸出 ${item.outputTokens?.toString() ?? '未提供'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
}
