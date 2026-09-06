import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../pro/pro_page.dart';
import '../ai_callable_diagnostics.dart';
import '../innera_ai_mode.dart';

/// The server is authoritative; this display never grants or deducts access.
class AiFreeQuotaBanner extends StatefulWidget {
  const AiFreeQuotaBanner(
      {super.key, required this.mode, required this.revision});

  final InneraAiMode mode;
  final int revision;

  @override
  State<AiFreeQuotaBanner> createState() => _AiFreeQuotaBannerState();
}

class _AiFreeQuotaBannerState extends State<AiFreeQuotaBanner>
    with WidgetsBindingObserver {
  Map<dynamic, dynamic>? _quota;
  Timer? _timer;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant AiFreeQuotaBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.revision != widget.revision) {
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: AiCallableEndpoints.region,
      ).httpsCallable('getInneraAiFreeQuota').call();
      if (!mounted || generation != _generation) return;
      setState(() => _quota = Map<dynamic, dynamic>.from(result.data as Map));
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _quota = null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_quota?['pro'] == true) return const SizedBox.shrink();
    final remaining =
        (_quota?['remaining'] as Map?)?[widget.mode.systemPromptKey];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              remaining == null
                  ? '各模式每天免費 3 則 · 台灣時間 00:00 重置'
                  : '今日此模式免費剩餘 $remaining／3 則\n台灣時間每日 00:00 重置',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const ProPage(source: 'ai_free_quota'),
              ));
              if (mounted) unawaited(_refresh());
            },
            child: const Text('升級 Pro'),
          ),
        ],
      ),
    );
  }
}
