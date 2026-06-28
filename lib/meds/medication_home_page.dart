import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/healing_design_system.dart';
import 'add_medication_page.dart';
import 'edit_medication_page.dart';
import '../widgets/main_drawer.dart';
import '../analytics_service.dart';
import 'record_adjustment_page.dart';
import 'record_adjustment_history_page.dart';
import 'med_symptom_compare_page.dart';
import 'medication_local_db.dart';
import 'drug_dictionary_service.dart';
import 'medication_schedule_utils.dart';

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

int _dateOnlyDiffDays(DateTime from, DateTime to) {
  final f = _startOfDay(from);
  final t = _startOfDay(to);
  return t.difference(f).inDays;
}

DateTime? _parseFlexibleDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

DateTime? _latestChangeAt(List<Map<String, dynamic>> meds) {
  DateTime? latest;
  for (final med in meds) {
    final candidate = _parseFlexibleDate(med['lastChangeAt']) ??
        _parseFlexibleDate(med['updatedAt']);
    if (candidate == null) continue;
    if (latest == null || candidate.isAfter(latest)) {
      latest = candidate;
    }
  }
  return latest;
}

String? _injectionBadgeText({
  required DateTime? startDate,
  required DateTime? lastChangeAt,
  required int? intervalDays,
  required DateTime today,
}) {
  if (startDate == null || intervalDays == null || intervalDays <= 0)
    return null;

  // 優先使用最近一次調整日當作「上次施打/更新基準日」
  final anchor = _startOfDay(lastChangeAt ?? startDate);
  final dueDate = anchor.add(Duration(days: intervalDays));
  final diff = _dateOnlyDiffDays(today, dueDate);

  if (diff >= 0) {
    return '剩 $diff 天';
  }

  return '逾期 ${-diff} 天';
}

String? _injectionBadgeTextV2({
  required DateTime? startDate,
  required DateTime? lastChangeAt,
  required int? intervalValue,
  required String? intervalUnit,
  required DateTime today,
}) {
  if (startDate == null || intervalValue == null || intervalValue <= 0) {
    return null;
  }

  final anchor = lastChangeAt ?? startDate;
  final dueDate = MedicationScheduleUtils.calculateNextInjectionDate(
    lastInjectionDate: anchor,
    intervalValue: intervalValue,
    intervalUnit: intervalUnit ?? 'day',
  );
  final diff = dueDate.difference(today);
  final abs = diff.abs();

  String formatDiff() {
    if (abs.inDays >= 365) return '${abs.inDays ~/ 365} 年';
    if (abs.inDays >= 30) return '${abs.inDays ~/ 30} 月';
    if (abs.inDays >= 7) return '${abs.inDays ~/ 7} 週';
    if (abs.inDays >= 1) return '${abs.inDays} 天';
    return '${abs.inHours} 小時';
  }

  return diff.isNegative ? '逾期 ${formatDiff()}' : '還有 ${formatDiff()}';
}

String _fmtMd(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$m/$d';
}

class MedicationHomePage extends StatefulWidget {
  const MedicationHomePage({super.key});

  @override
  State<MedicationHomePage> createState() => _MedicationHomePageState();
}

class _MedicationHomePageState extends State<MedicationHomePage> {
  late Future<List<Map<String, dynamic>>> _future;
  Future<void>? _pendingSync; // 追蹤未完成的 Firebase 同步
  int _refreshCounter = 0; // 用於強制 FutureBuilder 重新構建

  @override
  void initState() {
    super.initState();
    _refresh();
    AnalyticsService.logPage('medication_home_page');
  }

  void _refresh() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _future = Future.value(<Map<String, dynamic>>[]);
      setState(() => _refreshCounter++);
      return;
    }

    debugPrint('🔄 [REFRESH] 開始重新整理藥物列表 (count: $_refreshCounter)');

    // 先立即顯示本地資料
    _future = MedicationLocalDB().getMedicationsForDisplay(uid);
    setState(() => _refreshCounter++);

    // 背景同步 Firebase 後再刷新一次（如果有前一次未完成，等待它）
    _pendingSync = _syncFromFirebase(uid);
  }

  Future<void> _syncFromFirebase(String uid) async {
    try {
      debugPrint('📱 [SYNC] 開始 Firebase 同步...');
      await _mergeFirebaseIntoLocal(uid);
      debugPrint('✅ [SYNC] Firebase 合併完成，重新讀取本地資料');

      // 加入額外延遲，確保本地資料庫寫入完成
      await Future.delayed(const Duration(milliseconds: 200));

      _future = MedicationLocalDB().getMedicationsForDisplay(uid);
      if (mounted) {
        setState(() => _refreshCounter++);
        debugPrint('✅ [SYNC] UI 已更新 (count: $_refreshCounter)');
      }
    } catch (e) {
      debugPrint('❌ [SYNC] 背景同步失敗：$e');
    }
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
        backgroundColor: HealingDesignSystem.adaptiveBackground(context),
        drawer: const MainDrawer(),
        appBar: AppBar(
          backgroundColor: HealingDesignSystem.primaryBlue,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          iconTheme: IconThemeData(
              color: HealingDesignSystem.adaptivePrimaryText(context)),
          title: Text(
            '藥物紀錄',
            style: TextStyle(
              color: HealingDesignSystem.adaptivePrimaryText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
          ),
          bottom: TabBar(
            indicatorColor: HealingDesignSystem.primaryBlue,
            labelColor: HealingDesignSystem.adaptivePrimaryText(context),
            unselectedLabelColor:
                HealingDesignSystem.adaptiveSecondaryText(context),
            tabs: [
              Tab(text: '目前使用藥物'),
              Tab(text: '已停用'),
            ],
          ),
          // 功能已移到首頁總覽卡片（_OverviewBanner）中
          // actions: [
          //   IconButton(
          //     tooltip: '症狀交叉比對',
          //     icon: const Icon(Icons.compare_arrows, color: HealingDesignSystem.deepText),
          //     onPressed: () {
          //       Navigator.push(
          //         context,
          //         MaterialPageRoute(builder: (_) => const MedSymptomComparePage()),
          //       );
          //     },
          //   ),
          //   IconButton(
          //     tooltip: '紀錄調整（回診/調藥）',
          //     onPressed: () async {
          //       final changed = await Navigator.push(
          //         context,
          //         MaterialPageRoute(builder: (_) => const RecordAdjustmentPage()),
          //       );
          //       if (changed == true) _refresh();
          //     },
          //     icon: const Icon(Icons.edit_note, color: HealingDesignSystem.deepText),
          //   ),
          //   IconButton(
          //     tooltip: '新增藥物',
          //     onPressed: () async {
          //       final added = await Navigator.push(
          //         context,
          //         MaterialPageRoute(builder: (_) => const AddMedicationPage()),
          //       );
          //       if (added == true) _refresh();
          //     },
          //     icon: const Icon(Icons.add, color: HealingDesignSystem.primaryBlue),
          //   ),
          // ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          key: ValueKey(_refreshCounter), // 強制重新構建
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('發生錯誤：${snapshot.error}'));
            }

            final allMeds = snapshot.data ?? [];

            final activeMeds =
                allMeds.where((m) => (m['isActive'] ?? true) == true).toList();
            final inactiveMeds =
                allMeds.where((m) => (m['isActive'] ?? true) == false).map((m) {
              // 若有 resumedAt，顯示於 badge（停用後曾恢復的歷史）
              final resumedAt = _parseFlexibleDate(m['resumedAt']);
              if (resumedAt != null) {
                return {
                  ...m,
                  '_badgeOverride': '曾恢復使用：${_fmtMd(resumedAt)}',
                };
              }
              return m;
            }).toList();

            return TabBarView(
              children: [
                _buildMedicationList(
                  context,
                  activeMeds,
                  showOverview: true,
                  inactiveCount: inactiveMeds.length,
                ),
                _buildMedicationList(
                  context,
                  inactiveMeds,
                  showOverview: false,
                  inactiveCount: inactiveMeds.length,
                ),
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
          'nameEn': data['nameEn'],
          'dose': data['dose'],
          'dosePerUnit': data['dosePerUnit'],
          'pillCount': data['pillCount'],
          'concentrationMg': data['concentrationMg'],
          'concentrationMl': data['concentrationMl'],
          'intakeMl': data['intakeMl'],
          'unit': data['unit'],
          'type': data['type'],
          'drugForm': data['drugForm'],
          'compoundType': data['compoundType'],
          'drugConcentration': data['drugConcentration'],
          'packageAmount': data['packageAmount'],
          'packageUnit': data['packageUnit'],
          'ingredientLines':
              (data['ingredientLines'] as List?)?.cast<String>() ?? <String>[],
          ...MedicationScheduleUtils.readInjectionIntervalFields(data),
          'intervalDays': data['intervalDays'],
          'times': (data['times'] as List?)?.cast<String>() ?? <String>[],
          'purposes': (data['purposes'] as List?)?.cast<String>() ?? <String>[],
          'note': data['note'],
          'startDate': startDate?.toString(),
          'isActive': data['isActive'] ?? true,
          'bodySymptoms':
              (data['bodySymptoms'] as List?)?.cast<String>() ?? <String>[],
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
      BuildContext context, List<Map<String, dynamic>> meds,
      {required bool showOverview, required int inactiveCount}) {
    if (meds.isEmpty) {
      return _EmptyState(
        onAdd: () async {
          final added = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMedicationPage()),
          );
          if (added == true) _refresh();
        },
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
      final isInjection = MedicationScheduleUtils.isInjectionMedication(
        dosageForm: med['drugForm'] as String?,
        manualMedicationType: med['type'] as String?,
      );
      if (isInjection) {
        injectionMeds.add(med);
        continue;
      }

      final times = ((med['times'] as List?) ?? const [])
          .whereType<String>()
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();

      var assigned = false;
      for (final t in times) {
        if (groups.containsKey(t) && t != '未設定') {
          groups[t]!.add(med);
          assigned = true;
        }
      }

      if (!assigned) {
        groups['未設定']!.add(med);
      }
    }

    final latestChangeAt = _latestChangeAt(meds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (showOverview) ...[
          _OverviewBanner(
            activeCount: meds.length,
            inactiveCount: inactiveCount,
            lastChangeAt: latestChangeAt,
            onAdd: () async {
              final added = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddMedicationPage()),
              );
              if (added == true) _refresh();
            },
            onAdjust: () async {
              final changed = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecordAdjustmentPage()),
              );
              if (changed == true) _refresh();
            },
            onCompare: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const MedSymptomComparePage()),
              );
            },
            onOpenTimeline: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RecordAdjustmentHistoryPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
        ],

        // 注射藥物
        if (injectionMeds.isNotEmpty) ...[
          _SectionTitle(title: '長效針', count: injectionMeds.length),
          const SizedBox(height: 8),
          ...injectionMeds.map((med) {
            final medId = med['id'] as String? ?? '';
            final startDate = _parseFlexibleDate(med['startDate']);
            final lastChangeAt = _parseFlexibleDate(med['lastChangeAt']);
            final intervalValue =
                MedicationScheduleUtils.parseInjectionIntervalValue(
                      med['injectionIntervalValue'],
                    ) ??
                    MedicationScheduleUtils.parseInjectionIntervalValue(
                      med['intervalDays'],
                    );
            final intervalUnit =
                MedicationScheduleUtils.normalizeInjectionIntervalUnit(
              med['injectionIntervalUnit'] ?? med['intervalUnit'] ?? 'day',
            );
            final badgeText = _injectionBadgeTextV2(
              startDate: startDate,
              lastChangeAt: lastChangeAt,
              intervalValue: intervalValue,
              intervalUnit: intervalUnit,
              today: DateTime.now(),
            );

            debugPrint(
              '💉 [INJECTION] medId=$medId, start=$startDate, lastChangeAt=$lastChangeAt, intervalValue=$intervalValue, intervalUnit=$intervalUnit, badge=$badgeText',
            );

            return _MedicationCard(
              docId: medId,
              data: {
                ...med,
                if (badgeText != null) '_badgeOverride': badgeText,
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
              const SizedBox(height: 8),
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
    final isActive = (data['isActive'] as bool?) ?? true;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('編輯藥物資料'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (!mounted) return;
                  final updated = await navigator.push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EditMedicationPage(
                        docId: medId,
                        initialData: data,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  if (updated == true) {
                    // ⏱️ 延遲以確保本地資料庫完全寫入
                    debugPrint('⏳ 編輯完成，等待資料庫同步...');
                    await Future.delayed(const Duration(milliseconds: 800));
                    if (!mounted) return;

                    // 立即刷新本地資料
                    debugPrint('🔄 開始刷新本地資料...');
                    _refresh();

                    // 等待 Firebase 同步完成
                    if (_pendingSync != null) {
                      debugPrint('⏳ 等待 Firebase 同步...');
                      await _pendingSync;
                      if (!mounted) return;
                      debugPrint('✅ Firebase 同步完成');
                    }
                  }
                },
              ),
              if (isActive)
                ListTile(
                  leading: const Icon(Icons.pause_circle_outline),
                  title: const Text('停藥（標記為已停用）'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!mounted) return;
                    // 本地更新
                    final nowStr = DateTime.now().toString();
                    await MedicationLocalDB().updateMedicationStatus(
                      uid,
                      medId,
                      isActive: false,
                      updatedAt: nowStr,
                      lastChangeAt: nowStr,
                    );

                    // Firebase 更新
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('medications')
                        .doc(medId)
                        .update({'isActive': false});

                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已標記為停藥')),
                    );
                    _refresh();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('恢復使用'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!mounted) return;
                    final nowStr = DateTime.now().toString();
                    await MedicationLocalDB().updateMedicationStatus(
                      uid,
                      medId,
                      isActive: true,
                      updatedAt: nowStr,
                      lastChangeAt: nowStr,
                    );

                    // 將恢復日期也寫入本地DB
                    final localMed =
                        await MedicationLocalDB().getMedication(uid, medId);
                    if (localMed != null) {
                      final updated = Map<String, dynamic>.from(localMed);
                      updated['resumedAt'] = nowStr;
                      await MedicationLocalDB()
                          .updateMedication(uid, medId, updated);
                    }

                    // Firebase 更新
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('medications')
                        .doc(medId)
                        .update({
                      'isActive': true,
                      'resumedAt': FieldValue.serverTimestamp(),
                    });

                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已恢復使用，恢復日期已標註')),
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
                  Navigator.of(sheetContext).pop();
                  if (!mounted) return;

                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('確認刪除'),
                      content: const Text('刪除後將無法復原，確定要刪除嗎？'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
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

                    if (!mounted) return;
                    messenger.showSnackBar(
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

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: HealingDesignSystem.adaptivePrimaryText(context),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
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
        color: HealingDesignSystem.adaptiveFill(context),
        border:
            Border.all(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: HealingDesignSystem.primaryBlue,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
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
      color: HealingDesignSystem.adaptiveSurface(context),
      surfaceTintColor: Colors.transparent,
      shadowColor: HealingDesignSystem.primaryBlue.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusL),
        side:
            BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
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
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CountPill(count: widget.count),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: HealingDesignSystem.mutedText,
                    ),
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
    String fmt1(dynamic v) {
      double? d;
      if (v is num) d = v.toDouble();
      if (v is String) d = double.tryParse(v);
      if (d == null) return '';
      final rounded = (d * 10).round() / 10;
      return rounded % 1 == 0
          ? rounded.toInt().toString()
          : rounded.toStringAsFixed(1);
    }

    bool isCompoundIngredient(String? value) {
      if (value == null) return false;
      return RegExp(r'(\s*\+\s*|[;\n\r])').hasMatch(value.trim());
    }

    bool ingredientContainsDose(String? value) {
      if (value == null) return false;
      return RegExp(r'\d+(?:\.\d+)?\s*(MG|MCG|UG|G|ML|IU)\b',
              caseSensitive: false)
          .hasMatch(value);
    }

    final rawName = data['name'] ?? data['nameZh'] ?? data['nameEn'];
    final name = (rawName as String?)?.trim().isNotEmpty == true
        ? rawName.toString().trim()
        : '未命名藥物';
    final explicitNameEn = (data['nameEn'] as String?)?.trim();
    final dose = data['dose'];
    final dosePerUnit = data['dosePerUnit'];
    final pillCount = data['pillCount'];
    final concentrationMg = data['concentrationMg'];
    final concentrationMl = data['concentrationMl'];
    final intakeMl = data['intakeMl'];
    final unit = (data['unit'] as String?) ?? 'mg';
    final type = (data['type'] as String?) ?? 'tablet';
    final compoundIngredientHasDose = isCompoundIngredient(explicitNameEn) &&
        ingredientContainsDose(explicitNameEn);

    final times = (data['times'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final purposes =
        (data['purposes'] as List?)?.whereType<String>().toList() ??
            const <String>[];

    final subtitleOverride = data['_subtitleOverride'] as String?;
    final subtitle = subtitleOverride ??
        (() {
          if (type == 'drops' &&
              concentrationMg != null &&
              concentrationMl != null &&
              intakeMl != null) {
            return '${fmt1(concentrationMg)}mg/${fmt1(concentrationMl)}mL x ${fmt1(intakeMl)}mL';
          }
          if (dosePerUnit != null &&
              pillCount != null &&
              compoundIngredientHasDose) {
            return '每次 ${fmt1(pillCount)} 顆';
          }
          if (dosePerUnit != null && pillCount != null) {
            return '${fmt1(dosePerUnit)} $unit x ${fmt1(pillCount)} 顆';
          }
          if (dose == null) return '劑量未填';
          return '$dose $unit';
        })();

    final badge = data['_badgeOverride'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Card(
          elevation: 0,
          color: HealingDesignSystem.adaptiveSurface(context),
          surfaceTintColor: Colors.transparent,
          shadowColor: HealingDesignSystem.primaryBlue.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
                color: HealingDesignSystem.adaptiveCardBorder(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: HealingDesignSystem.adaptiveFill(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    color: HealingDesignSystem.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color:
                              HealingDesignSystem.adaptivePrimaryText(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _EnglishIngredientText(
                        name: name,
                        explicitNameEn: explicitNameEn,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: HealingDesignSystem.mutedText,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      if (badge != null && badge.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _Chip(text: badge),
                      ],
                      if (times.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 6,
                          runSpacing: 6,
                          children: times.map((t) => _Chip(text: t)).toList(),
                        ),
                      ],
                      if (purposes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 6,
                          runSpacing: 6,
                          children: purposes
                              .map((p) => _Chip(text: p, isSecondary: true))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '更多',
                  onPressed: onMore,
                  icon: Icon(
                    Icons.more_horiz,
                    color: HealingDesignSystem.adaptivePrimaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnglishIngredientText extends StatelessWidget {
  final String name;
  final String? explicitNameEn;

  const _EnglishIngredientText({
    required this.name,
    required this.explicitNameEn,
  });

  @override
  Widget build(BuildContext context) {
    final existing = explicitNameEn?.trim();
    if (existing != null && existing.isNotEmpty) {
      return _buildText(_normalizeIngredientText(existing));
    }

    return FutureBuilder<String?>(
      future: DrugDictionaryService.instance.findEnglishName(name),
      builder: (context, snapshot) {
        final value = snapshot.data?.trim();
        if (value == null || value.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildText(_normalizeIngredientText(value));
      },
    );
  }

  String _normalizeIngredientText(String value) {
    return value
        .split(RegExp(r'\s*(?:\+|;|\r?\n)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' + ');
  }

  Widget _buildText(String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        value,
        style: const TextStyle(
          color: HealingDesignSystem.mutedText,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w600,
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
        ? HealingDesignSystem.adaptiveFill(context).withOpacity(0.7)
        : HealingDesignSystem.adaptiveFill(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: HealingDesignSystem.adaptiveCardBorder(context)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: HealingDesignSystem.adaptivePrimaryText(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
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
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: HealingDesignSystem.adaptiveFill(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.medication_outlined,
                  size: 36, color: HealingDesignSystem.primaryBlue),
            ),
            const SizedBox(height: 12),
            Text(
              '先建立你的藥物清單',
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '平常不需要每天填藥。只有回診或調藥時，再做一次「紀錄調整」。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: HealingDesignSystem.mutedText,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增第一顆藥'),
              style: FilledButton.styleFrom(
                backgroundColor: HealingDesignSystem.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBanner extends StatelessWidget {
  final int activeCount;
  final int inactiveCount;
  final DateTime? lastChangeAt;
  final VoidCallback onAdd;
  final VoidCallback onAdjust;
  final VoidCallback onCompare;
  final VoidCallback onOpenTimeline;

  const _OverviewBanner({
    required this.activeCount,
    required this.inactiveCount,
    required this.lastChangeAt,
    required this.onAdd,
    required this.onAdjust,
    required this.onCompare,
    required this.onOpenTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final lastChangeText = lastChangeAt == null
        ? '尚未紀錄調整'
        : '上次調整：${lastChangeAt!.year}/${lastChangeAt!.month.toString().padLeft(2, '0')}/${lastChangeAt!.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: HealingDesignSystem.adaptiveCardDecoration(
        context,
        radius: HealingDesignSystem.radiusL,
        shadows: [
          HealingDesignSystem.shadowMedium(
              color: HealingDesignSystem.primaryBlue)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: HealingDesignSystem.primaryGradient(),
                  borderRadius: BorderRadius.circular(16),
                ),
                child:
                    const Icon(Icons.medication_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '藥物總覽',
                      style: TextStyle(
                        color: HealingDesignSystem.adaptivePrimaryText(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '先看現在吃哪些，再進入個別藥物管理。',
                      style: TextStyle(
                        color:
                            HealingDesignSystem.adaptiveSecondaryText(context),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatPill(
                  label: '使用中',
                  value: activeCount,
                  accent: HealingDesignSystem.primaryBlue),
              const SizedBox(width: 10),
              _StatPill(
                  label: '已停用',
                  value: inactiveCount,
                  accent: HealingDesignSystem.mutedText),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            lastChangeText,
            style: const TextStyle(
              color: HealingDesignSystem.mutedText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('新增藥物'),
                style: FilledButton.styleFrom(
                  backgroundColor: HealingDesignSystem.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.edit_note),
                label: const Text('調藥紀錄'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      HealingDesignSystem.adaptivePrimaryText(context),
                  side: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCompare,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('症狀比對'),
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      HealingDesignSystem.adaptivePrimaryText(context),
                  side: BorderSide(
                      color: HealingDesignSystem.adaptiveCardBorder(context)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              FilledButton.icon(
                onPressed: onOpenTimeline,
                icon: const Icon(Icons.timeline_rounded),
                label: const Text('完整時間線'),
                style: FilledButton.styleFrom(
                  backgroundColor: HealingDesignSystem.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;

  const _StatPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withOpacity(0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: TextStyle(
                color: HealingDesignSystem.adaptivePrimaryText(context),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
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
