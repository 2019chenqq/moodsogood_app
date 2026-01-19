import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_medication_page.dart';
import 'edit_medication_page.dart';
import '../widgets/main_drawer.dart';
import 'record_adjustment_page.dart';
import 'med_symptom_compare_page.dart';
import 'medication_local_db.dart';

const List<String> kTimeOrder = [
  '早上',
  '中午',
  '下午',
  '晚上',
  '睡前',
  '需要時',
  '未設定',
];

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

String _fmtMd(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$m/$d';
}

/// 依 startDate + intervalDays 推算「下一次注射日」
/// - 若今天剛好是注射日，回傳今天（剩 0 天）
DateTime _nextInjectionDate({
  required DateTime startDate,
  required int intervalDays,
  required DateTime today,
}) {
  final s = _startOfDay(startDate);
  final t = _startOfDay(today);

  if (t.isBefore(s)) return s;

  final diffDays = t.difference(s).inDays;
  final mod = diffDays % intervalDays;

  if (mod == 0) return t; // 今天就是注射日
  final addDays = intervalDays - mod;
  return t.add(Duration(days: addDays));
}
class MedicationHomePage extends StatefulWidget {
  const MedicationHomePage({super.key});

  @override
  State<MedicationHomePage> createState() => _MedicationHomePageState();
}

class _MedicationHomePageState extends State<MedicationHomePage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _future = Future.value(<Map<String, dynamic>>[]);
      setState(() {});
      return;
    }

    // 先立即顯示本地資料
    _future = MedicationLocalDB().getMedicationsForDisplay(uid);
    setState(() {});

    // 背景同步 Firebase 後再刷新一次
    _syncFromFirebase(uid);
  }

  Future<void> _syncFromFirebase(String uid) async {
    await _mergeFirebaseIntoLocal(uid);
    _future = MedicationLocalDB().getMedicationsForDisplay(uid);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('請先登入帳號')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const MainDrawer(),
        appBar: AppBar(
          title: const Text('藥物'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '目前使用藥物'),
              Tab(text: '已停用'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '症狀交叉比對',
              icon: const Icon(Icons.compare_arrows),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MedSymptomComparePage()),
                );
              },
            ),
            IconButton(
              tooltip: '紀錄調整（回診/調藥）',
              onPressed: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecordAdjustmentPage()),
                );
                if (changed == true) _refresh();
              },
              icon: const Icon(Icons.edit_note),
            ),
            IconButton(
              tooltip: '新增藥物',
              onPressed: () async {
                final added = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMedicationPage()),
                );
                if (added == true) _refresh();
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('發生錯誤：${snapshot.error}'));
            }

            final allMeds = snapshot.data ?? [];

            final activeMeds = allMeds.where((m) => (m['isActive'] ?? true) == true).toList();
            final inactiveMeds = allMeds.where((m) => (m['isActive'] ?? true) == false).toList();

            return TabBarView(
              children: [
                _buildMedicationList(context, activeMeds),
                _buildMedicationList(context, inactiveMeds),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 將 Firebase 資料合併到本地（不阻塞首次顯示）
  Future<void> _mergeFirebaseIntoLocal(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('medications')
          .get();

      for (final doc in snap.docs) {
        final data = doc.data();
        final startTs = data['startDate'];
        DateTime? startDate;
        if (startTs is Timestamp) startDate = startTs.toDate();
        if (startTs is String) startDate = DateTime.tryParse(startTs);

        // 檢查本地是否已存在該藥物
        final localMed = await MedicationLocalDB().getMedication(uid, doc.id);
        if (localMed != null) {
          // 比較更新時間：如果本地比 Firebase 更新，則跳過覆蓋
          final localUpdatedStr = localMed['updatedAt'] as String?;
          final remoteUpdated = (data['updatedAt'] as Timestamp?)?.toDate();
          
          if (localUpdatedStr != null && remoteUpdated != null) {
            final localUpdated = DateTime.tryParse(localUpdatedStr);
            if (localUpdated != null && localUpdated.isAfter(remoteUpdated)) {
              debugPrint('⏭️ 本地資料更新：${doc.id}，跳過 Firebase 覆蓋');
              continue;
            }
          }
        }

        final mapped = {
          'id': doc.id,
          'name': data['name'],
          'dose': data['dose'],
          'unit': data['unit'],
          'type': data['type'],
          'intervalDays': data['intervalDays'],
          'times': (data['times'] as List?)?.cast<String>() ?? <String>[],
          'purposes': (data['purposes'] as List?)?.cast<String>() ?? <String>[],
          'note': data['note'],
          'startDate': startDate?.toString(),
          'isActive': data['isActive'] ?? true,
          'bodySymptoms': (data['bodySymptoms'] as List?)?.cast<String>() ?? <String>[],
          'purposeOther': data['purposeOther'],
          'createdAt': (localMed?['createdAt']) ?? DateTime.now().toString(),
          'updatedAt': data['updatedAt'] is Timestamp 
              ? (data['updatedAt'] as Timestamp).toDate().toString()
              : data['updatedAt']?.toString() ?? DateTime.now().toString(),
          'lastChangeAt': (data['lastChangeAt'] is Timestamp)
              ? (data['lastChangeAt'] as Timestamp).toDate().toString()
              : data['lastChangeAt']?.toString(),
        };

        await MedicationLocalDB().addMedication(uid, mapped);
      }
    } catch (e) {
      debugPrint('抓取 Firebase 藥物失敗：$e');
    }
  }

  Widget _buildMedicationList(
    BuildContext context,
    List<Map<String, dynamic>> meds,
  ) {
    if (meds.isEmpty) {
      return const Center(
        child: Text('目前沒有藥物紀錄'),
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('請先登入'));
    }

    // 構建分組
    final Map<String, List<Map<String, dynamic>>> groups = {
      for (final t in kTimeOrder) t: <Map<String, dynamic>>[],
    };
    final List<Map<String, dynamic>> injectionMeds = [];

    for (final med in meds) {
      final isInjection = (med['type'] as String?) == 'injection';
      if (isInjection) {
        injectionMeds.add(med);
        continue;
      }

      final times = (med['times'] as List?)?.cast<String>() ?? <String>[];
      if (times.isEmpty) {
        groups['未設定']!.add(med);
      } else {
        for (final t in times) {
          if (groups.containsKey(t)) {
            groups[t]!.add(med);
          } else {
            groups['未設定']!.add(med);
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 注射藥物
        if (injectionMeds.isNotEmpty) ...[
          _SectionTitle(title: '長效針', count: injectionMeds.length),
          ...injectionMeds.map((med) {
            final medId = med['id'] as String? ?? '';
            final startDate = med['startDate'];
            final intervalDays = med['intervalDays'];

            DateTime? start;
            if (startDate is String) {
              start = DateTime.tryParse(startDate);
            } else if (startDate is DateTime) {
              start = startDate;
            }

            final nextDate = (start != null && intervalDays != null)
                ? _nextInjectionDate(
                    startDate: start,
                    intervalDays: intervalDays as int,
                    today: DateTime.now(),
                  )
                : null;

            final diffDays = nextDate != null
                ? nextDate.difference(DateTime.now()).inDays
                : null;

            return _MedicationCard(
              docId: medId,
              data: {
                ...med,
                if (diffDays != null) '_badgeOverride': '剩 $diffDays 天',
              },
              onTap: () {
                _showMedActions(context, uid: uid, medId: medId, data: med);
              },
              onMore: () {
                _showMedActions(context, uid: uid, medId: medId, data: med);
              },
            );
          }).toList(),
          const SizedBox(height: 12),
        ],

        // 口服藥分組
        ...kTimeOrder.map((timeLabel) {
          final medsInTime = groups[timeLabel] ?? [];
          if (medsInTime.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(title: timeLabel, count: medsInTime.length),
              ...medsInTime.map((med) {
                final medId = med['id'] as String? ?? '';
                return _MedicationCard(
                  docId: medId,
                  data: med,
                  onTap: () {
                    _showMedActions(context, uid: uid, medId: medId, data: med);
                  },
                  onMore: () {
                    _showMedActions(context, uid: uid, medId: medId, data: med);
                  },
                );
              }).toList(),
              const SizedBox(height: 12),
            ],
          );
        }).toList(),
      ],
    );
  }

  void _showMedActions(
  BuildContext context, {
  required String uid,
  required String medId,
  required Map<String, dynamic> data,
}) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯藥物資料'),
              onTap: () async {
                Navigator.pop(context);
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditMedicationPage(
                      docId: medId,
                      initialData: data,
                    ),
                  ),
                );
                if (updated == true) {
                  _refresh();
                }
},
            ),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('停藥（標記為已停用）'),
              onTap: () async {
                Navigator.pop(context);
                // 本地更新
                await MedicationLocalDB().updateMedication(uid, medId, {
                  'isActive': false,
                  'updatedAt': DateTime.now().toString(),
                  'lastChangeAt': DateTime.now().toString(),
                });

                // Firebase 更新
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('medications')
                    .doc(medId)
                    .update({'isActive': false});

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已標記為停藥')),
                );
                _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                '刪除藥物（永久）',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);

                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('確認刪除'),
                    content: const Text('刪除後將無法復原，確定要刪除嗎？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('刪除'),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  // 本地刪除
                  await MedicationLocalDB().deleteMedication(uid, medId);

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('medications')
                      .doc(medId)
                      .delete();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('藥物已刪除')),
                  );
                  _refresh();
                }
              },
            ),
          ],
        ),
      );
    },
  );
}

}

class _HeaderHintCard extends StatelessWidget {
  final DateTime? lastChangeAt;
  const _HeaderHintCard({required this.lastChangeAt});

  @override
  Widget build(BuildContext context) {
    final text = (lastChangeAt == null)
        ? '若今天回診或調藥，點右上角「紀錄調整」。'
        : '上次調整：${_fmtYmd(lastChangeAt!)}｜若今天回診或調藥，點右上角「紀錄調整」。';

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        _CountPill(count: count),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final int count;
  final bool initiallyExpanded;
  final Widget child;

  const _ExpandableSection({
    required this.title,
    required this.count,
    required this.initiallyExpanded,
    required this.child,
  });

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(width: 8),
                          _CountPill(count: widget.count),
                        ],
                      ),
                    ),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_expanded) widget.child,
          ],
        ),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  const _MedicationCard({
    required this.docId,
    required this.data,
    this.onTap,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final rawName = data['name'] ?? data['nameZh'] ?? data['nameEn'];
final name = (rawName as String?)?.trim().isNotEmpty == true
    ? rawName.toString().trim()
    : '未命名藥物';
    final dose = data['dose'];
    final unit = (data['unit'] as String?) ?? 'mg';

    final times = (data['times'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final purposes = (data['purposes'] as List?)?.whereType<String>().toList() ?? const <String>[];

    final subtitleOverride = data['_subtitleOverride'] as String?;
final subtitle = subtitleOverride ?? ((dose == null) ? '劑量未填' : '$dose $unit');

final badge = data['_badgeOverride'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
                child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.medication_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                      if (badge != null && badge.trim().isNotEmpty) ...[
  const SizedBox(height: 8),
  _Chip(text: badge),
],
                      if (times.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: times.map((t) => _Chip(text: t)).toList(),
                        ),
                      ],
                      if (purposes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: purposes.map((p) => _Chip(text: p, isSecondary: true)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '更多',
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool isSecondary;
  const _Chip({required this.text, this.isSecondary = false});

  @override
  Widget build(BuildContext context) {
    final bg = isSecondary
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.7)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _MutedText extends StatelessWidget {
  final String text;
  const _MutedText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medication_outlined, size: 44),
            const SizedBox(height: 12),
            Text('先建立你的藥物清單', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '平常不需要每天填藥。只有回診或調藥時，再做一次「紀錄調整」。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增第一顆藥'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _TimeSectionHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const Spacer(),
        Container(
          width: 28,
          height: 4,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.25),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
}