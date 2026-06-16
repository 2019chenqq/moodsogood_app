import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/healing_design_system.dart';
import 'medication_local_db.dart';
import '../analytics_service.dart';

class RecordAdjustmentHistoryPage extends StatefulWidget {
  const RecordAdjustmentHistoryPage({super.key});

  @override
  State<RecordAdjustmentHistoryPage> createState() =>
      _RecordAdjustmentHistoryPageState();
}

class _RecordAdjustmentHistoryPageState
    extends State<RecordAdjustmentHistoryPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('record_adjustment_history_page');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _loadFromLocal();
    // 背景同步 Firebase 資料到本地（非 await，異步執行）
    if (uid != null && !_initialized) {
      _initialized = true;
      _syncFromFirebase(uid);
    }
  }

  void _loadFromLocal() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('❌ uid 為 null，無法載入調整記錄');
      _future = Future.value([]);
    } else {
      debugPrint('📋 正在從本地 DB 載入調整記錄，uid: $uid');
      _future = MedicationLocalDB()
          .getAdjustmentRecordsForDisplay(uid)
          .then((records) {
        debugPrint('✅ 本地 DB 載入成功，共 ${records.length} 筆記錄');
        return records;
      }).catchError((e) {
        debugPrint('❌ 本地 DB 載入失敗：$e');
        return <Map<String, dynamic>>[];
      });
    }
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      debugPrint('🔥 開始從 Firebase 同步調整記錄...');
      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medAdjustments')
          .orderBy('date', descending: true)
          .limit(60);

      final snap = await query.get();
      final docs = snap.docs;
      debugPrint('🔥 Firebase 返回 ${docs.length} 筆記錄');

      for (final doc in docs) {
        final data = doc.data();
        final date = data['date'];
        final dateStr = (date is Timestamp)
            ? _fmtYmd(date.toDate())
            : (date is DateTime)
                ? _fmtYmd(date)
                : date.toString();

        await MedicationLocalDB().addAdjustmentRecord(uid, doc.id, {
          'date': dateStr,
          'note': data['note'],
          'items': data['items'] ?? [],
          'createdAt':
              data['createdAt']?.toString() ?? DateTime.now().toString(),
        });
      }

      debugPrint('✅ Firebase 同步完成，共 ${docs.length} 筆');
      // 同步後重新載入本地資料
      if (mounted) {
        setState(() => _loadFromLocal());
      }
    } catch (e) {
      debugPrint('⚠️ Firebase 同步失敗：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('請先登入後使用')));
    }

    // 確保 _future 已初始化
    if (!_initialized) {
      _initialized = true;
      _syncFromFirebase(uid);
    }

    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        backgroundColor: HealingDesignSystem.primaryBlue,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: HealingDesignSystem.adaptivePrimaryText(context)),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          '調藥時間線',
          style: TextStyle(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          debugPrint(
              '📊 FutureBuilder state: ${snap.connectionState}, hasData: ${snap.hasData}, hasError: ${snap.hasError}');

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            debugPrint('❌ FutureBuilder error: ${snap.error}');
            return Center(child: Text('讀取失敗：${snap.error}'));
          }

          final records = snap.data ?? [];
          if (records.isEmpty) {
            return const _EmptyHistoryTimeline();
          }

          return Container(
            color: HealingDesignSystem.adaptiveBackground(context),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              itemCount: records.length,
              itemBuilder: (context, i) {
                final record = records[i];

                final dateStr = (record['date'] as String?) ?? '';
                final note = (record['note'] as String?)?.trim() ?? '';
                final items =
                    (record['items'] as List?)?.whereType<Map>().toList() ??
                        const [];
                final summary = _buildSummary(items);

                final isFirst = i == 0;
                final isLast = i == records.length - 1;

                return _HistoryTimelineItem(
                  dateText: dateStr,
                  note: note,
                  summary: summary,
                  count: items.length,
                  isFirst: isFirst,
                  isLast: isLast,
                  onTap: () => _showDetailSheet(context, dateStr, note, items),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  /// 讀你目前的 items schema：
  /// { name, type(added/injected/doseChanged/scheduleChanged/stopped), oldDose, newDose, oldTimes, newTimes, unit, stopReason }
  static String _buildSummary(List items) {
    if (items.isEmpty) return '（本次沒有任何變更）';

    String fmtItem(dynamic it) {
      if (it is! Map) return '';
      final name = (it['name'] ?? '未命名藥物').toString();
      final type = (it['type'] ?? 'unchanged').toString();
      final unit = (it['unit'] ?? '').toString();
      final oldDose = it['oldDose'];
      final newDose = it['newDose'];
      final oldTimes = _timesToText(it['oldTimes']);
      final newTimes = _timesToText(it['newTimes']);

      switch (type) {
        case 'added':
          return '$name：新增 ${newDose ?? ''} $unit';
        case 'injected':
          return '$name：已施打';
        case 'injection':
          return '$name：已施打';
        case 'doseChanged':
          final oldDosePerUnit = it['oldDosePerUnit'];
          final newDosePerUnit = it['newDosePerUnit'];
          final oldPillCount = it['oldPillCount'];
          final newPillCount = it['newPillCount'];

          String doseText;
          if (newDosePerUnit != null && newPillCount != null) {
            doseText =
                '$name：${newDosePerUnit ?? ''}$unit × ${newPillCount ?? ''}顆（總量 ${newDose ?? ''} $unit）';
          } else {
            doseText = '$name：${oldDose ?? ''}→${newDose ?? ''} $unit';
          }

          if ((oldDosePerUnit != null && oldPillCount != null) &&
              (oldDosePerUnit != newDosePerUnit ||
                  oldPillCount != newPillCount)) {
            doseText =
                '$doseText；原本 ${oldDosePerUnit ?? ''}$unit × ${oldPillCount ?? ''}顆';
          }

          if (oldTimes != newTimes && newTimes.isNotEmpty) {
            return '$doseText；時間 $oldTimes→$newTimes';
          }
          return doseText;
        case 'scheduleChanged':
          return '$name：時間 $oldTimes→$newTimes';
        case 'stopped':
          return '$name：停藥';
        case 'resumed':
          return '$name：恢復使用';
        default:
          return '$name：維持';
      }
    }

    final shown =
        items.take(3).map(fmtItem).where((s) => s.isNotEmpty).toList();
    final more = items.length > 3 ? '…等 ${items.length} 項' : '';
    return '${shown.join('、')} $more'.trim();
  }

  static void _showDetailSheet(
      BuildContext context, String title, String note, List items) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(note, style: Theme.of(context).textTheme.bodyMedium),
                ],
                const SizedBox(height: 12),
                ...items.map((it) {
                  if (it is! Map) return const SizedBox.shrink();

                  final name = (it['name'] ?? '未命名藥物').toString();
                  final type = (it['type'] ?? 'unchanged').toString();
                  final unit = (it['unit'] ?? '').toString();
                  final oldDose = it['oldDose'];
                  final newDose = it['newDose'];
                  final oldTimes = _timesToText(it['oldTimes']);
                  final newTimes = _timesToText(it['newTimes']);
                  final stopReason = (it['stopReason'] ?? '').toString().trim();

                  String line;
                  if (type == 'added') {
                    line = '新增：${newDose ?? ''} $unit';
                  } else if (type == 'injected' || type == 'injection') {
                    line = '已施打';
                  } else if (type == 'doseChanged') {
                    final oldDosePerUnit = it['oldDosePerUnit'];
                    final newDosePerUnit = it['newDosePerUnit'];
                    final oldPillCount = it['oldPillCount'];
                    final newPillCount = it['newPillCount'];

                    if (newDosePerUnit != null && newPillCount != null) {
                      line =
                          '調整：${newDosePerUnit ?? ''}$unit × ${newPillCount ?? ''}顆（總量 ${newDose ?? ''} $unit）';
                      if (oldDosePerUnit != null &&
                          oldPillCount != null &&
                          (oldDosePerUnit != newDosePerUnit ||
                              oldPillCount != newPillCount)) {
                        line =
                            '$line；原本 ${oldDosePerUnit ?? ''}$unit × ${oldPillCount ?? ''}顆';
                      }
                    } else {
                      line = '調整：${oldDose ?? ''} → ${newDose ?? ''} $unit';
                    }

                    if (oldTimes != newTimes && newTimes.isNotEmpty) {
                      line = '$line；時間：$oldTimes → $newTimes';
                    }
                  } else if (type == 'scheduleChanged') {
                    line = '時間調整：$oldTimes → $newTimes';
                  } else if (type == 'stopped') {
                    line = stopReason.isEmpty ? '停藥' : '停藥（原因：$stopReason）';
                  } else if (type == 'resumed') {
                    line = '恢復使用';
                  } else {
                    line = '維持原劑量';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.circle, size: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(line,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _timesToText(dynamic value) {
    if (value is List) {
      final parts =
          value.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
      if (parts.isEmpty) return '未設定';
      return parts.join('、');
    }
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? '未設定' : t;
    }
    return '未設定';
  }
}

class _HistoryTimelineItem extends StatelessWidget {
  final String dateText;
  final String note;
  final String summary;
  final int count;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _HistoryTimelineItem({
    required this.dateText,
    required this.note,
    required this.summary,
    required this.count,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : HealingDesignSystem.lineColor,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.primaryBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            HealingDesignSystem.primaryBlue.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : HealingDesignSystem.lineColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius:
                      BorderRadius.circular(HealingDesignSystem.radiusL),
                  child: Ink(
                    decoration: HealingDesignSystem.adaptiveCardDecoration(
                      context,
                      radius: HealingDesignSystem.radiusL,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HistoryHeaderRow(
                            title: dateText,
                            count: count,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            summary,
                            style: TextStyle(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context),
                              fontSize: 14,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _HistoryNoteBox(note: note),
                          ],
                          const SizedBox(height: 12),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '查看細節',
                                style: TextStyle(
                                  color: HealingDesignSystem.primaryBlue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: HealingDesignSystem.primaryBlue,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryHeaderRow extends StatelessWidget {
  final String title;
  final int count;

  const _HistoryHeaderRow({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: HealingDesignSystem.adaptiveFill(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.medication_liquid_rounded,
            color: HealingDesignSystem.primaryBlue,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '藥物調整紀錄',
                style: TextStyle(
                  color: HealingDesignSystem.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8FC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCEEF7)),
          ),
          child: Text(
            '$count 項',
            style: const TextStyle(
              color: HealingDesignSystem.primaryBlue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryNoteBox extends StatelessWidget {
  final String note;

  const _HistoryNoteBox({required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: HealingDesignSystem.isDark(context)
            ? const Color(0xFF302A20)
            : const Color(0xFFFFFAF1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HealingDesignSystem.isDark(context)
              ? const Color(0xFF5A4B31)
              : const Color(0xFFF3E6C8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notes_rounded,
            size: 17,
            color: Color(0xFFC7A458),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                color: HealingDesignSystem.adaptiveSecondaryText(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryTimeline extends StatelessWidget {
  const _EmptyHistoryTimeline();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HealingDesignSystem.adaptiveBackground(context),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          decoration: HealingDesignSystem.adaptiveCardDecoration(
            context,
            radius: 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: HealingDesignSystem.adaptiveFill(context),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  size: 30,
                  color: HealingDesignSystem.primaryBlue,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '還沒有調藥紀錄',
                style: TextStyle(
                  color: HealingDesignSystem.adaptivePrimaryText(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '當你新增回診或藥物調整後，\n這裡會慢慢形成一條屬於你的用藥時間線。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
