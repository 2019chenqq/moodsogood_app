import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../analytics_service.dart';
import '../constants/healing_design_system.dart';
import '../utils/health_data_encryption_service.dart';
import 'med_symptom_compare_models.dart';
import 'medication_compare_repository.dart';

class MedSymptomComparePage extends StatefulWidget {
  const MedSymptomComparePage({super.key});

  @override
  State<MedSymptomComparePage> createState() => _MedSymptomComparePageState();
}

class _MedSymptomComparePageState extends State<MedSymptomComparePage>
    with WidgetsBindingObserver {
  final MedicationCompareRepository _repository = MedicationCompareRepository();
  late Future<List<MedicationCompareOption>> _optionsFuture;
  String? _selectedOptionKey;
  List<MedicationAdjustmentEvent> _allEvents = const [];
  List<MedicationAdjustmentEvent> _medEvents = const [];
  MedicationAdjustmentEvent? _selectedEvent;
  List<MedicationAdjustmentEvent> _concurrentEvents = const [];
  DailyRecordAggregate? _before;
  DailyRecordAggregate? _after;
  List<CompareMetricResult> _results = const [];
  int _windowDays = 7;
  bool _loading = false;
  bool _dataLoading = true;
  String? _error;
  String? _syncWarning;
  ObservationWindowStatus? _observationStatus;
  int _beforeAvailableDays = 0;
  int _afterAvailableDays = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.logPage('med_symptom_compare_page');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _optionsFuture = uid == null
        ? Future.value(const <MedicationCompareOption>[])
        : _loadOptions(uid);
  }

  Future<List<MedicationCompareOption>> _loadOptions(String uid) async {
    String? syncWarning;
    try {
      await _repository.syncAll(uid);
    } catch (error) {
      syncWarning = '同步失敗，已使用目前可讀資料：$error';
      debugPrint(syncWarning);
    }
    try {
      final medications = await _repository.getMedications(uid);
      final persistedEvents = await _repository.getAdjustmentEvents(uid);
      final events = [
        ...persistedEvents,
        ...buildSyntheticAddedEvents(medications, persistedEvents),
      ]..sort((left, right) => right.date.compareTo(left.date));
      _allEvents = events;
      return mergeMedicationCompareOptions(medications, events);
    } finally {
      if (mounted) {
        setState(() {
          _dataLoading = false;
          _syncWarning = syncWarning;
        });
      }
    }
  }

  void _reloadOptions() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _dataLoading) return;
    setState(() {
      _dataLoading = true;
      _syncWarning = null;
      _selectedOptionKey = null;
      _selectedEvent = null;
      _medEvents = const [];
      _clearResults();
      _optionsFuture = _loadOptions(uid);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_dataLoading) {
      _reloadOptions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _selectMedication(
    String? optionKey,
    List<MedicationCompareOption> options,
  ) {
    if (optionKey == null) return;
    final option = options.firstWhere((item) => item.key == optionKey);
    setState(() {
      _selectedOptionKey = optionKey;
      _selectedEvent = null;
      _medEvents = const [];
      _clearResults();
      _error = null;
    });
    final normalizedName = MedicationCompareOption.normalizedName(option.name);
    final selectedEvents = _allEvents.where((event) {
      if (option.medDocId != null && event.medDocId.isNotEmpty) {
        return event.medDocId == option.medDocId;
      }
      return event.medDocId.isEmpty &&
          MedicationCompareOption.normalizedName(event.medName) ==
              normalizedName;
    }).toList();
    setState(() {
      _medEvents = selectedEvents;
      _selectedEvent = null;
    });
  }

  void _clearResults() {
    _before = null;
    _after = null;
    _results = const [];
    _concurrentEvents = const [];
    _observationStatus = null;
    _beforeAvailableDays = 0;
    _afterAvailableDays = 0;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final foreground = HealingDesignSystem.adaptiveAppBarForeground(context);
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('調藥前後變化'),
        actions: [
          IconButton(
            tooltip: '重新同步藥物與調藥事件',
            onPressed: _dataLoading ? null : _reloadOptions,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '重新計算',
            onPressed: _selectedEvent == null || _loading ? null : _runCompare,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('請先登入後使用'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMedicationPicker(),
                const SizedBox(height: 12),
                _buildEventPicker(),
                const SizedBox(height: 12),
                _buildWindowPicker(),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _selectedEvent == null || _loading ? null : _runCompare,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.analytics_outlined),
                  label: const Text('比較這次調整前後'),
                  style: FilledButton.styleFrom(
                    backgroundColor: HealingDesignSystem.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                if (_syncWarning != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _syncWarning!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _buildResults(),
              ],
            ),
    );
  }

  Widget _buildMedicationPicker() => _SoftCard(
        title: '1. 選擇藥物',
        subtitle: '包含目前使用中、已停用及曾有調整紀錄的藥物',
        child: FutureBuilder<List<MedicationCompareOption>>(
          future: _optionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) return Text('讀取藥物失敗：${snapshot.error}');
            final options = snapshot.data ?? const [];
            if (options.isEmpty) return const Text('尚未建立藥物或調藥歷史');
            return DropdownButtonFormField<String>(
              key: ValueKey(_selectedOptionKey),
              initialValue:
                  options.any((item) => item.key == _selectedOptionKey)
                      ? _selectedOptionKey
                      : null,
              isExpanded: true,
              decoration: _inputDecoration(context),
              items: options.map((option) {
                return DropdownMenuItem(
                  value: option.key,
                  child: Text('${option.name}｜${option.statusLabel}'),
                );
              }).toList(),
              onChanged: (value) => _selectMedication(value, options),
            );
          },
        ),
      );

  Widget _buildEventPicker() => _SoftCard(
        title: '2. 選擇一次調藥事件',
        subtitle: '一次分析只對應一個有效事件；維持原狀的紀錄不列入',
        child: _dataLoading
            ? const Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('正在同步藥物與調藥事件…'),
                ],
              )
            : _selectedOptionKey == null
                ? const Text('請先選擇藥物')
                : _medEvents.isEmpty
                    ? const Text(
                        '這項藥物缺少開始日期或調整紀錄，因此目前無法建立比較基準。\n'
                        '請先補上開始服藥日期，或新增一筆調藥紀錄。',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            key: ValueKey(_selectedEvent?.eventKey),
                            initialValue: _selectedEvent?.eventKey,
                            isExpanded: true,
                            decoration: _inputDecoration(context),
                            items: _medEvents
                                .map((event) => DropdownMenuItem(
                                      value: event.eventKey,
                                      child: Text(
                                        '${event.dateLabel} · ${event.typeLabel}${event.isInferred ? '（推定）' : ''} · ${event.changeSummary}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (key) {
                              if (key == null) return;
                              setState(() {
                                _selectedEvent = _medEvents.firstWhere(
                                    (event) => event.eventKey == key);
                                _clearResults();
                              });
                            },
                          ),
                          if (_selectedEvent != null) ...[
                            const SizedBox(height: 12),
                            _EventSummary(event: _selectedEvent!),
                          ],
                        ],
                      ),
      );

  Widget _buildWindowPicker() => _SoftCard(
        title: '3. 選擇觀察窗口',
        subtitle: '調整當天獨立排除，不納入前後比較',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [3, 7, 14, 30].map((days) {
            return ChoiceChip(
              label: Text('前後各 $days 天'),
              selected: _windowDays == days,
              onSelected: (_) => setState(() {
                _windowDays = days;
                _clearResults();
              }),
            );
          }).toList(),
        ),
      );

  InputDecoration _inputDecoration(BuildContext context) => InputDecoration(
        filled: true,
        fillColor: HealingDesignSystem.adaptiveFill(context),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Future<void> _runCompare() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final event = _selectedEvent;
    if (uid == null || event == null) return;
    final requestedWindow = _windowDays;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final anchor =
          DateTime(event.date.year, event.date.month, event.date.day);
      final beforeStart = anchor.subtract(Duration(days: requestedWindow));
      final beforeEndExclusive = anchor;
      final afterStart = anchor.add(const Duration(days: 1));
      final afterEndExclusive = afterStart.add(Duration(days: requestedWindow));
      final observation = ObservationWindowStatus.calculate(
        eventDate: anchor,
        requestedDays: requestedWindow,
      );
      final documents = await Future.wait([
        _fetchDailyRecords(uid, beforeStart, beforeEndExclusive),
        _fetchDailyRecords(uid, afterStart, afterEndExclusive),
      ]);
      final before = DailyRecordAggregator.aggregate(
        documents[0].map((document) => document.data),
      );
      final after = DailyRecordAggregator.aggregate(
        documents[1].map((document) => document.data),
      );
      final concurrent = _allEvents.where((other) {
        if (other.eventKey == event.eventKey) return false;
        final day = DateTime(other.date.year, other.date.month, other.date.day);
        return !day.isBefore(beforeStart) && day.isBefore(afterEndExclusive);
      }).toList();
      if (!mounted ||
          _selectedEvent?.eventKey != event.eventKey ||
          _windowDays != requestedWindow) {
        return;
      }
      setState(() {
        _before = before;
        _after = after;
        _results = CompareEngine.compare(
          before,
          after,
          beforeAvailableDays: requestedWindow,
          afterAvailableDays: observation.elapsedAfterDays,
          hasConcurrentAdjustments: concurrent.isNotEmpty,
        );
        _concurrentEvents = concurrent;
        _observationStatus = observation;
        _beforeAvailableDays = requestedWindow;
        _afterAvailableDays = observation.elapsedAfterDays;
      });
    } catch (error) {
      if (!mounted ||
          _selectedEvent?.eventKey != event.eventKey ||
          _windowDays != requestedWindow) {
        return;
      }
      setState(() => _error = '比對失敗：$error');
    } finally {
      if (mounted &&
          _selectedEvent?.eventKey == event.eventKey &&
          _windowDays == requestedWindow) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<LogicalDailyRecord>> _fetchDailyRecords(
    String uid,
    DateTime startInclusive,
    DateTime endExclusive,
  ) async {
    String id(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final reference = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('dailyRecords');
    final byDate = await HealthDataEncryptionService.getEncrypted(
      reference
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startInclusive))
          .where('date', isLessThan: Timestamp.fromDate(endExclusive)),
    );
    final byId = await HealthDataEncryptionService.getEncrypted(
      reference
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: id(startInclusive))
          .where(
            FieldPath.documentId,
            isLessThanOrEqualTo:
                id(endExclusive.subtract(const Duration(days: 1))),
          ),
    );
    final documents = <String, HealthDocument>{
      for (final document in byDate) document.id: document,
      for (final document in byId) document.id: document,
    }.values;
    return deduplicateDailyRecords(
      documents.map(
        (document) => LogicalDailyRecord(id: document.id, data: document.data),
      ),
      onSkipped: debugPrint,
    );
  }

  Widget _buildResults() {
    final before = _before;
    final after = _after;
    if (before == null || after == null) {
      return const _NoticeCard(
        icon: Icons.info_outline,
        text: '選擇明確的調藥事件後開始比較。結果只呈現時間上的關聯趨勢，不代表藥物造成變化。',
      );
    }
    final observation = _observationStatus!;
    final confidence = CompareConfidenceSummary.calculate(
      before: before,
      after: after,
      beforeAvailableDays: _beforeAvailableDays,
      afterAvailableDays: _afterAvailableDays,
      hasConcurrentAdjustments: _concurrentEvents.isNotEmpty,
    );
    final insufficient = _results.where((item) => !item.canCalculate).toList();
    final preliminary = _results
        .where((item) => item.canCalculate && !item.canInterpret)
        .toList();
    final newly = _results
        .where((item) => item.newlyAppeared && item.canInterpret)
        .toList();
    final attention = _results
        .where((item) => item.needsAttention && !item.newlyAppeared)
        .toList();
    final improved = _results.where((item) => item.possiblyImproved).toList();
    final mixed = _results
        .where((item) =>
            item.kind == CompareMetricKind.symptom &&
            item.symptomPattern == SymptomChangePattern.mixed &&
            item.canInterpret)
        .toList();
    final other = _results
        .where((item) =>
            item.canInterpret &&
            !item.newlyAppeared &&
            !item.needsAttention &&
            !item.possiblyImproved &&
            item.symptomPattern != SymptomChangePattern.mixed &&
            item.magnitude != ChangeMagnitude.stable)
        .toList();
    final hasMeaningfulDisplayedResult = attention.isNotEmpty ||
        improved.isNotEmpty ||
        newly.isNotEmpty ||
        mixed.isNotEmpty ||
        other.isNotEmpty ||
        preliminary.isNotEmpty ||
        insufficient.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConfidenceCard(
          before: before,
          after: after,
          beforeAvailableDays: _beforeAvailableDays,
          afterAvailableDays: _afterAvailableDays,
          confidence: confidence,
          observation: observation,
          hasConcurrentAdjustments: _concurrentEvents.isNotEmpty,
        ),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '需要優先留意', items: attention),
        ],
        if (improved.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '可能改善的趨勢', items: improved),
        ],
        if (newly.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '新出現症狀', items: newly),
        ],
        if (mixed.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '變化不一致', items: mixed),
        ],
        if (other.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '其他明顯變化', items: other),
        ],
        if (preliminary.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '初步變化／資料有限', items: preliminary),
        ],
        if (insufficient.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultSection(title: '資料不足項目', items: insufficient),
        ],
        if (!hasMeaningfulDisplayedResult && _results.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _NoticeCard(
            icon: Icons.check_circle_outline,
            text: '這段觀察期間未發現達到目前判定門檻的明顯變化。',
          ),
        ] else if (_results.isEmpty) ...[
          const SizedBox(height: 12),
          const _NoticeCard(
              icon: Icons.inbox_outlined, text: '觀察期間沒有可比較的症狀或情緒資料。'),
        ],
        if (_concurrentEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ConcurrentAdjustmentCard(events: _concurrentEvents),
        ],
        if (!observation.completed) ...[
          const SizedBox(height: 12),
          _ObservationIncompleteCard(status: observation),
        ],
        const SizedBox(height: 12),
        const _NoticeCard(
          icon: Icons.health_and_safety_outlined,
          text: '此結果僅描述調整前後同時出現的趨勢，不能證明因果。若症狀明顯或持續變化，請和醫療專業人員討論。',
        ),
      ],
    );
  }
}

class _EventSummary extends StatelessWidget {
  const _EventSummary({required this.event});
  final MedicationAdjustmentEvent event;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveAccent(context)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.medName, style: Theme.of(context).textTheme.titleSmall),
            Text(event.dateLabel),
            Text(event.changeSummary,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(event.typeLabel),
            if (event.isInferred)
              Text(
                event.inferenceReason ?? '此事件為系統推定',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
}

class _ConfidenceCard extends StatelessWidget {
  const _ConfidenceCard({
    required this.before,
    required this.after,
    required this.beforeAvailableDays,
    required this.afterAvailableDays,
    required this.confidence,
    required this.observation,
    required this.hasConcurrentAdjustments,
  });
  final DailyRecordAggregate before;
  final DailyRecordAggregate after;
  final int beforeAvailableDays;
  final int afterAvailableDays;
  final CompareConfidenceSummary confidence;
  final ObservationWindowStatus observation;
  final bool hasConcurrentAdjustments;

  @override
  Widget build(BuildContext context) => _SoftCard(
        title: '觀察資料概況',
        subtitle: '調整當天未納入統計',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '整體紀錄覆蓋率：前段 ${before.effectiveRecordDays}/$beforeAvailableDays 天'),
            Text(
                '整體紀錄覆蓋率：後段 ${after.effectiveRecordDays}/$afterAvailableDays 天'),
            const SizedBox(height: 6),
            Text('整體資料信心：${_confidenceLabel(confidence.overall)}'),
            Text('症狀資料信心：${_confidenceLabel(confidence.symptom)}'),
            Text('情緒資料信心：${_confidenceLabel(confidence.emotion)}'),
            Text('每日狀態資料信心：${_confidenceLabel(confidence.state)}'),
            const SizedBox(height: 6),
            Text(
              '症狀明確完成紀錄：前 ${before.symptomRecordSummary.confirmedRecordedDays} 天、'
              '後 ${after.symptomRecordSummary.confirmedRecordedDays} 天',
            ),
            if (before.symptomRecordSummary.inferredRecordedDays > 0 ||
                after.symptomRecordSummary.inferredRecordedDays > 0)
              Text(
                '症狀舊資料推定：前 ${before.symptomRecordSummary.inferredRecordedDays} 天、'
                '後 ${after.symptomRecordSummary.inferredRecordedDays} 天',
              ),
            Text(
              '情緒明確完成紀錄：前 ${before.emotionRecordSummary.confirmedRecordedDays} 天、'
              '後 ${after.emotionRecordSummary.confirmedRecordedDays} 天',
            ),
            if (before.emotionRecordSummary.inferredRecordedDays > 0 ||
                after.emotionRecordSummary.inferredRecordedDays > 0)
              Text(
                '情緒舊資料推定：前 ${before.emotionRecordSummary.inferredRecordedDays} 天、'
                '後 ${after.emotionRecordSummary.inferredRecordedDays} 天',
              ),
            Text(
              '每日狀態明確完成紀錄：前 ${before.stateRecordSummary.confirmedRecordedDays} 天、'
              '後 ${after.stateRecordSummary.confirmedRecordedDays} 天',
            ),
            if (before.stateRecordSummary.inferredRecordedDays > 0 ||
                after.stateRecordSummary.inferredRecordedDays > 0)
              Text(
                '每日狀態舊資料推定：前 ${before.stateRecordSummary.inferredRecordedDays} 天、'
                '後 ${after.stateRecordSummary.inferredRecordedDays} 天',
              ),
            Text(
                '觀察期完成度：${observation.elapsedAfterDays}/${observation.requestedDays} 天'),
            Text('同期調藥影響：${hasConcurrentAdjustments ? '有，解讀時需留意' : '未發現'}'),
            if (_hasInferredData(before) || _hasInferredData(after)) ...[
              const SizedBox(height: 6),
              const Text(
                '部分較早的紀錄缺少完整填寫狀態，系統會依現有內容推估；推定資料已降低分析信心。',
              ),
            ],
          ],
        ),
      );

  static bool _hasInferredData(DailyRecordAggregate aggregate) =>
      aggregate.symptomRecordSummary.containsInferredData ||
      aggregate.emotionRecordSummary.containsInferredData ||
      aggregate.stateRecordSummary.containsInferredData;
}

class _ConcurrentAdjustmentCard extends StatelessWidget {
  const _ConcurrentAdjustmentCard({required this.events});
  final List<MedicationAdjustmentEvent> events;

  @override
  Widget build(BuildContext context) {
    final groups = groupAdjustmentEvents(events);
    return _SoftCard(
      title: '同期其他調藥提醒',
      subtitle:
          '此期間另有 ${groups.length} 筆調藥紀錄，共包含 ${events.length} 項其他藥物變動，結果可能受到影響。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.values.map((group) {
          final first = group.first;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(first.dateLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                ...group.map((event) => Text(
                    '• ${event.medName}：${MedicationAdjustmentFormatter.shortSummary(event)}')),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ObservationIncompleteCard extends StatelessWidget {
  const _ObservationIncompleteCard({required this.status});
  final ObservationWindowStatus status;

  @override
  Widget build(BuildContext context) => _NoticeCard(
        icon: Icons.hourglass_bottom,
        text: '本次 ${status.requestedDays} 天觀察期尚未完成\n'
            '目前已觀察 ${status.elapsedAfterDays}/${status.requestedDays} 天\n'
            '預計於 ${_dateLabel(status.expectedCompletionDate)} 完成。'
            '尚未到來的日期不計為缺漏。',
      );
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.items});
  final String title;
  final List<CompareMetricResult> items;

  @override
  Widget build(BuildContext context) => _SoftCard(
        title: title,
        child: Column(
          children: items
              .map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MetricRow(item: item),
                  ))
              .toList(),
        ),
      );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.item});
  final CompareMetricResult item;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    if (!item.canCalculate) {
      lines.add('資料不足，無法判定變化');
    } else if (item.kind == CompareMetricKind.symptom) {
      lines.add(
          '出現率：${_percent(item.beforeOccurrenceRate)} → ${_percent(item.afterOccurrenceRate)}');
      lines.add(
          '出現天數：${item.beforePresentDays}/${item.beforeRecordedDays} → ${item.afterPresentDays}/${item.afterRecordedDays} 天');
      if (item.beforeAverageScore != null || item.afterAverageScore != null) {
        lines.add(
            '平均強度：${_score(item.beforeAverageScore)} → ${_score(item.afterAverageScore)}');
        lines.add(
            '最高強度：${_score(item.beforeMaximumScore)} → ${_score(item.afterMaximumScore)}');
      }
      lines.add(
          '頻率變化：${_changeText(item.occurrenceDirection, item.occurrenceMagnitude)}');
      lines.add(
          '強度變化：${_changeText(item.severityDirection, item.severityMagnitude)}');
    } else {
      lines.add(
          '平均分：${_score(item.beforeAverageScore)} → ${_score(item.afterAverageScore)}');
      lines
          .add('有效樣本：${item.beforeRecordedDays} → ${item.afterRecordedDays} 天');
    }
    lines.add('資料信心：${_confidenceLabel(item.confidence)}');
    if (item.dataAdequacy == DataAdequacy.veryLimited) {
      lines.add('資料非常有限，目前僅能視為初步變化。');
    } else if (item.dataAdequacy == DataAdequacy.limited) {
      lines.add('資料有限，目前屬初步趨勢。');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HealingDesignSystem.adaptiveFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w800))),
              _Tag(text: _label(item)),
            ],
          ),
          if (item.newlyAppeared)
            Text(item.afterPresentDays == 1
                ? '後段新出現 1 次，仍需更多紀錄確認'
                : '後段新出現 ${item.afterPresentDays} 次'),
          if (item.disappeared) const Text('觀察期間後段未再出現'),
          ...lines.map((line) => Text(line)),
        ],
      ),
    );
  }

  static String _label(CompareMetricResult item) {
    if (!item.canCalculate) return '資料不足';
    if (item.dataAdequacy == DataAdequacy.veryLimited) {
      return switch (item.direction) {
        ChangeDirection.increased => '初步上升',
        ChangeDirection.decreased => '初步下降',
        _ => item.newlyAppeared ? '初步新出現' : '初步變化',
      };
    }
    if (item.symptomPattern == SymptomChangePattern.mixed) return '變化不一致';
    if (item.newlyAppeared) {
      return item.afterPresentDays == 1 ? '新出現／初步變化' : '新出現';
    }
    if (item.needsAttention) return '需要留意';
    if (item.possiblyImproved) return '可能改善';
    final direction = switch (item.direction) {
      ChangeDirection.increased => '上升',
      ChangeDirection.decreased => '下降',
      ChangeDirection.stable => '穩定',
      ChangeDirection.unknown => '未判定',
    };
    final magnitude = switch (item.magnitude) {
      ChangeMagnitude.highAttention || ChangeMagnitude.meaningful => '明顯',
      ChangeMagnitude.minor => '輕度',
      ChangeMagnitude.stable => '無明顯',
    };
    return '$magnitude$direction';
  }

  static String _percent(double? value) =>
      value == null ? '未記錄' : '${value.toStringAsFixed(1)}%';
  static String _score(double? value) =>
      value == null ? '未記錄' : value.toStringAsFixed(1);

  static String _changeText(
    ChangeDirection direction,
    ChangeMagnitude magnitude,
  ) {
    if (direction == ChangeDirection.unknown) return '無可比較分數';
    final prefix = switch (magnitude) {
      ChangeMagnitude.highAttention || ChangeMagnitude.meaningful => '明顯',
      ChangeMagnitude.minor => '初步',
      ChangeMagnitude.stable => '無明顯',
    };
    final suffix = switch (direction) {
      ChangeDirection.increased => '增加',
      ChangeDirection.decreased => '下降',
      ChangeDirection.stable => '變化',
      ChangeDirection.unknown => '',
    };
    return '$prefix$suffix';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveAccent(context)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: HealingDesignSystem.adaptiveCardBorder(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HealingDesignSystem.adaptiveSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: HealingDesignSystem.adaptiveCardBorder(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

String _confidenceLabel(CompareConfidence value) => switch (value) {
      CompareConfidence.high => '高',
      CompareConfidence.medium => '中',
      CompareConfidence.low => '低',
    };

String _dateLabel(DateTime date) => '${date.year.toString().padLeft(4, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.day.toString().padLeft(2, '0')}';
