// lib/edit_record_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'record_detail_screen.dart';
import '../utils/date_helper.dart';
import '../utils/firebase_sync_config.dart';
import '../utils/health_data_encryption_service.dart';
import 'daily_record_repository.dart';
import '../constants/healing_design_system.dart';
import '../analytics_service.dart';
class EditRecordPage extends StatefulWidget {
  final String uid;
  final String docId;
  final Map<String, dynamic> initData;

  const EditRecordPage({
    super.key,
    required this.uid,
    required this.docId,
    required this.initData,
  });

  @override
  State<EditRecordPage> createState() => _EditRecordPageState();
}

class _EditRecordPageState extends State<EditRecordPage> {
  bool _saving = false;

Future<void> _saveAndClose() async {
  if (_saving) return;
  setState(() => _saving = true);

  // 你要的提示：「開始儲存情緒、症狀、睡眠」
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('開始儲存情緒、症狀、睡眠')),
    );
  }

  debugPrint('💾 開始保存編輯，_sleepTime=$_sleepTime, _wakeTime=$_wakeTime');

  try {
    final uid = widget.uid;
final docId = widget.docId;
final ref = FirebaseFirestore.instance
    .collection('users').doc(uid)
    .collection('dailyRecords').doc(docId);

// 先把目前畫面上的睡眠欄位整理成新的 Map
// 注意：要保留現有的所有值，只更新改動的部分
final Map<String, dynamic> newSleep = Map<String, dynamic>.from(sleep);

// 有沒有吃安眠藥
newSleep['tookHypnotic'] = _tookHypnotic;

// 藥名、劑量（沒有就存空字串）
newSleep['hypnoticName'] = _hypNameCtrl.text.trim();
newSleep['hypnoticDose'] = _hypDoseCtrl.text.trim();

// 入睡時間、起床時間（確保保存時間或清除空值）
if (_sleepTime != null) {
  newSleep['sleepTime'] = DateHelper.formatTime(_sleepTime);
} else {
  newSleep.remove('sleepTime');
}

if (_wakeTime != null) {
  newSleep['wakeTime'] = DateHelper.formatTime(_wakeTime);
} else {
  newSleep.remove('wakeTime');
}

// 中途醒來時間
if (_midWakeCtrl.text.trim().isNotEmpty) {
  newSleep['midWakeList'] = _midWakeCtrl.text.trim();
} else {
  newSleep.remove('midWakeList');
}

// 自覺睡眠品質
if (_sleepQuality != null) {
  newSleep['quality'] = _sleepQuality;
} else {
  newSleep.remove('quality');
}

// flags / note / naps：更新旗標和備註
newSleep['flags'] = (sleep['flags'] as List?)?.map((e) => e.toString()).toList() ?? [];
newSleep['note'] = (sleep['note'] ?? '').toString();

final List<Map<String, dynamic>> naps = ((sleep['naps'] as List?) ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
newSleep['naps'] = naps;

// 最後再組 payload
    final payload = <String, dynamic>{
      'emotions': emotions,
      'symptoms': symptoms,
      'sleep': newSleep, // ⬅️ 改成用 newSleep
      'savedAt': FieldValue.serverTimestamp(),
    };


    debugPrint('🔥 即將保存的完整 sleep 物件：$newSleep');
    debugPrint('🔥 即將保存的完整 payload：$payload');
    
    // Only sync to Firebase if enabled
    if (FirebaseSyncConfig.shouldSync()) {
      await HealthDataEncryptionService.setEncrypted(ref, payload);
    }

    // Always save to local database
    try {
      final repo = DailyRecordRepository();
      await repo.saveDailyRecord(
        id: docId,
        userId: uid,
        date: DateTime.tryParse(widget.initData['date'] ?? '') ?? DateTime.now(),
        emotions: Map<String, dynamic>.from(
          emotions
              .where((e) => e['value'] != null && e['name'] != '整體情緒') // Exclude overallMood
              .toList()
              .asMap()
              .map((k, v) => MapEntry(v['name'] ?? '', v['value']))
        ),
        // symptoms 已經是 List<String>，僅過濾空白
        bodySymptoms: symptoms
          .where((name) => name.isNotEmpty)
          .toList(),
        sleep: newSleep,
      );
      debugPrint('✅ 本地數據已保存');
    } catch (e) {
      debugPrint('❌ 本地保存失敗: $e');
    }


    if (!mounted) return;
    // 儲存成功 ➜ 關掉編輯頁並回傳 true
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      // 萬一這頁是最上層，保險起見導回詳細頁
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RecordDetailScreen(uid: uid, docId: docId),
        ),
      );
    }
  } catch (e, st) {
    debugPrint('save error: $e\n$st');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$e')),
      );
    }
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  // ====== 狀態：情緒 / 症狀 / 睡眠 ======
  late List<Map<String, dynamic>> emotions; // [{name: '期待', value: 7}, ...]
  late List<String> symptoms;               // ['心悸', '頭痛', ...]
  late Map<String, dynamic> sleep;          // 見下方 keys

  // 睡眠控制器（避免 TextField 反向輸入）
  late final TextEditingController _hypNameCtrl;
  late final TextEditingController _hypDoseCtrl;
  TimeOfDay? _sleepTime;
 late final TextEditingController _midWakeCtrl;
  TimeOfDay? _wakeTime;
  int? _sleepQuality; // null 代表 '-'
  bool _tookHypnotic = false;

  // 方便：旗標列表（你可依需求增減）
  static const List<Map<String, String>> kSleepFlags = [
    {'key': 'good', 'label': '優'},
    {'key': 'ok', 'label': '良好'},
    {'key': 'earlyWake', 'label': '早醒'},
    {'key': 'dreams', 'label': '多夢'},
    {'key': 'lightSleep', 'label': '淺眠'},
    {'key': 'nocturia', 'label': '夜尿'},
    {'key': 'fragmented', 'label': '睡睡醒醒'},
    {'key': 'insufficient', 'label': '睡眠不足'},
    {'key': 'initInsomnia', 'label': '入睡困難'},
    {'key': 'interrupted', 'label': '睡眠中斷'},
  ];

  @override
  void initState() {
    super.initState();
AnalyticsService.logPage('edit_record_page');
    // ===== 初始化：把每日紀錄的內容帶進來 =====
    final init = widget.initData;

    emotions = ((init['emotions'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    symptoms = ((init['symptoms'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    sleep = Map<String, dynamic>.from((init['sleep'] as Map?) ?? const {});

    _tookHypnotic = sleep['tookHypnotic'] == true;
    _hypNameCtrl = TextEditingController(text: (sleep['hypnoticName'] ?? '').toString());
    _hypDoseCtrl = TextEditingController(text: (sleep['hypnoticDose'] ?? '').toString());
    _midWakeCtrl = TextEditingController(text: (sleep['midWakeList'] ?? '').toString());
    _sleepTime = DateHelper.parseTime(sleep['sleepTime']);
    _wakeTime  = DateHelper.parseTime(sleep['wakeTime']);
    final savedSleepQuality = sleep['quality'];
    _sleepQuality = savedSleepQuality is num
        ? savedSleepQuality.round().clamp(1, 5).toInt()
        : null;
    
    debugPrint('🛏️ 編輯頁初始化睡眠：sleepTime=$_sleepTime, wakeTime=$_wakeTime, sleep=$sleep');
  }

  @override
  void dispose() {
    _hypNameCtrl.dispose();
    _hypDoseCtrl.dispose();
    _midWakeCtrl.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) async {
    final now = TimeOfDay.now();
    return showTimePicker(
      context: context,
      initialTime: initial ?? now,
    );
  }

  // ====== UI ======
 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: HealingDesignSystem.adaptiveBackground(context),
    appBar: AppBar(
      backgroundColor: HealingDesignSystem.adaptiveAppBarBackground(context),
      foregroundColor: HealingDesignSystem.adaptiveAppBarForeground(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(
        '編輯每日紀錄',
        style: TextStyle(
          color: HealingDesignSystem.adaptiveAppBarForeground(context),
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      iconTheme: IconThemeData(color: HealingDesignSystem.adaptiveAppBarForeground(context)),
      actions: [
        IconButton(
          icon: Icon(
            Icons.save,
            color: HealingDesignSystem.adaptiveAppBarForeground(context),
          ),
          tooltip: '儲存',
          onPressed: _saveAndClose,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
          // 情緒區塊
          _sectionHeader('情緒', onAdd: _addEmotion),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              bgColor: HealingDesignSystem.adaptiveSurface(context),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              children: [
                if (emotions.isEmpty)
                  ListTile(title: Text('沒有情緒項目', style: TextStyle(color: HealingDesignSystem.adaptiveSecondaryText(context)))),
                ...emotions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  return ListTile(
                    title: Text(m['name']?.toString() ?? '', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                    subtitle: Slider(
                      value: (m['value'] is num) ? (m['value'] as num).toDouble() : 0,
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: '${m['value'] ?? 0}',
                      activeColor: HealingDesignSystem.primaryBlue,
                      inactiveColor: HealingDesignSystem.lineColor,
                      onChanged: (v) => setState(() => emotions[idx]['value'] = v.round()),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: HealingDesignSystem.dangerRed),
                      onPressed: () => setState(() => emotions.removeAt(idx)),
                    ),
                  );
                }),
              ],
            ),
          ),

          // 症狀區塊
          _sectionHeader('症狀', onAdd: _addSymptom),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              bgColor: HealingDesignSystem.adaptiveSurface(context),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              children: [
                if (symptoms.isEmpty)
                  ListTile(title: Text('沒有症狀項目', style: TextStyle(color: HealingDesignSystem.adaptiveSecondaryText(context)))),
                ...symptoms.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  return Dismissible(
                    key: ValueKey('sym-$idx-$s'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      decoration: BoxDecoration(
                        color: HealingDesignSystem.dangerRed,
                        borderRadius: BorderRadius.circular(HealingDesignSystem.radiusM),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => setState(() => symptoms.removeAt(idx)),
                    child: ListTile(title: Text(s, style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context)))),
                  );
                }),
              ],
            ),
          ),

          const Divider(height: 32),

          _sectionHeader('睡眠'),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              bgColor: HealingDesignSystem.adaptiveSurface(context),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 服藥
                SwitchListTile(
                  title: Text('前一晚是否服用安眠藥', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  value: _tookHypnotic,
                  activeColor: HealingDesignSystem.primaryBlue,
                  onChanged: (v) => setState(() => _tookHypnotic = v),
                  contentPadding: EdgeInsets.zero,
                ),
                _textTile('藥物名稱', _hypNameCtrl),
                _textTile('劑量', _hypDoseCtrl),
                // 入睡 / 起床
                ListTile(
                  title: Text('入睡時間', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  trailing: Text(DateHelper.formatTime(_sleepTime), style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  onTap: () async {
                    final t = await _pickTime(_sleepTime);
                    if (t != null) setState(() => _sleepTime = t);
                  },
                ),
                ListTile(
                  title: Text('夜間醒來時間', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  subtitle: TextField(
                    controller: _midWakeCtrl,
                    style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context)),
                    decoration: InputDecoration(
                      hintText: '例如：03:20 / 05:10 或 03:40醒過一次',
                      filled: true,
                      fillColor: HealingDesignSystem.adaptiveFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(HealingDesignSystem.radiusS)),
                        borderSide: BorderSide(color: HealingDesignSystem.lineColor),
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                ListTile(
                  title: Text('起床時間', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  trailing: Text(DateHelper.formatTime(_wakeTime), style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  onTap: () async {
                    final t = await _pickTime(_wakeTime);
                    if (t != null) setState(() => _wakeTime = t);
                  },
                ),
                // 自覺睡眠品質
                ListTile(
                  title: Text('自覺睡眠品質（1~5）', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  trailing: Text(_sleepQuality?.toString() ?? '-', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  onTap: () async {
                    final v = await _pickQuality(context, _sleepQuality ?? 3);
                    if (v != null) setState(() => _sleepQuality = v);
                  },
                ),
                // 夜間睡眠狀況 flags
                const SizedBox(height: 8),
                Text('夜間睡眠狀況', style: HealingDesignSystem.titleSmall.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: kSleepFlags.map((f) {
                    final key = f['key']!;
                    final label = f['label']!;
                    final selected = ((sleep['flags'] as List?) ?? const []).contains(key);
                    return FilterChip(
                      label: Text(label, style: HealingDesignSystem.bodySmall.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                      selected: selected,
                      selectedColor: HealingDesignSystem.adaptiveAccent(context).withOpacity(0.22),
                      checkmarkColor: HealingDesignSystem.adaptiveAccent(context),
                      backgroundColor: HealingDesignSystem.adaptiveSurface(context),
                      side: BorderSide(
                        color: selected
                            ? HealingDesignSystem.adaptiveAccent(context)
                            : HealingDesignSystem.adaptiveCardBorder(context),
                      ),
                      onSelected: (v) {
                        final list = ((sleep['flags'] as List?) ?? const []).map((e) => e.toString()).toList();
                        if (v) {
                          if (!list.contains(key)) list.add(key);
                        } else {
                          list.remove(key);
                        }
                        setState(() => sleep['flags'] = list);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // 註記
                ListTile(
                  title: Text('睡眠註記', style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  subtitle: Text((sleep['note'] ?? '').toString().isEmpty ? '—' : (sleep['note'] ?? '').toString(), style: HealingDesignSystem.bodySmall.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                  onTap: () async {
                    final v = await _editNote(context, (sleep['note'] ?? '').toString());
                    if (v != null) setState(() => sleep['note'] = v);
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 32),

          // 小睡
          _sectionHeader('小睡', onAdd: _addNap),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(
              context,
              bgColor: HealingDesignSystem.adaptiveSurface(context),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Column(
              children: [
                ...(((sleep['naps'] as List?) ?? const [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList()
                    .asMap()
                    .entries
                    .map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  final start = (m['start'] ?? '-').toString();
                  final end = (m['end'] ?? '-').toString();
                  final mins = (m['minutes'] ?? 0) as int;
                  String durationText = '';
                  if (mins > 0) {
                    final hours = mins ~/ 60;
                    final remain = mins % 60;
                    if (hours > 0 && remain > 0) {
                      durationText = '（$hours 小時 $remain 分）';
                    } else if (hours > 0) {
                      durationText = '（$hours 小時）';
                    } else {
                      durationText = '（$remain 分）';
                    }
                  }
                  final text = '$start → $end $durationText';
                  return ListTile(
                    title: Text(text, style: HealingDesignSystem.bodyMedium.copyWith(color: HealingDesignSystem.adaptivePrimaryText(context))),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: HealingDesignSystem.dangerRed),
                      onPressed: () {
                        final list = ((sleep['naps'] as List?) ?? const [])
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        list.removeAt(idx);
                        setState(() => sleep['naps'] = list);
                      },
                    ),
                    onTap: () => _editNap(idx),
                  );
                }).toList()),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ====== UI helpers ======
  Widget _sectionHeader(String title, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: HealingDesignSystem.adaptiveAccent(context),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: HealingDesignSystem.titleSmall.copyWith(
                color: HealingDesignSystem.adaptivePrimaryText(context),
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              icon: Icon(
                Icons.add,
                color: HealingDesignSystem.adaptiveAccent(context),
              ),
              tooltip: '新增$title',
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }

  Widget _textTile(String title, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl, // 保持同一個 controller，避免反向輸入
        textDirection: TextDirection.ltr,
        style: HealingDesignSystem.bodyMedium.copyWith(
          color: HealingDesignSystem.adaptivePrimaryText(context),
        ),
        decoration: InputDecoration(
          labelText: title,
          labelStyle: TextStyle(color: HealingDesignSystem.adaptiveSecondaryText(context)),
          filled: true,
          fillColor: HealingDesignSystem.adaptiveFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(color: HealingDesignSystem.adaptiveCardBorder(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(
              color: HealingDesignSystem.adaptiveAccent(context),
              width: 2,
            ),
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  // ====== 互動：新增 / 編輯 ======
  Future<void> _addEmotion() async {
    String name = '';
    double value = 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增情緒'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '名稱',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => name = v.trim(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('強度 0-10'),
                Expanded(
                  child: Slider(
                    value: value,
                    min: 0, max: 10, divisions: 10,
                    label: value.round().toString(),
                    onChanged: (v) => setState(() => value = v),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('加入')),
        ],
      ),
    );
    if (ok == true && name.isNotEmpty) {
      setState(() => emotions.add({'name': name, 'value': value.round()}));
    }
  }

  Future<void> _addSymptom() async {
    String s = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增症狀'),
        content: TextField(
          decoration: const InputDecoration(
            labelText: '症狀',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => s = v.trim(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('加入')),
        ],
      ),
    );
    if (ok == true && s.isNotEmpty) {
      setState(() => symptoms.add(s));
    }
  }

  Future<int?> _pickQuality(BuildContext context, int initial) async {
    int temp = initial.clamp(1, 5);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('自覺睡眠品質（1~5）'),
        content: StatefulBuilder(
          builder: (_, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$temp', style: Theme.of(context).textTheme.headlineSmall),
              Slider(
                value: temp.toDouble(),
                min: 1, max: 5, divisions: 4,
                label: '$temp',
                onChanged: (v) => setLocal(() => temp = v.round()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定')),
        ],
      ),
    );
    if (ok == true) return temp;
    return null;
  }

  Future<String?> _editNote(BuildContext context, String init) async {
    String v = init;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('睡眠註記'),
        content: TextField(
          controller: TextEditingController(text: init),
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '想補充的睡眠觀察…',
          ),
          onChanged: (x) => v = x,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定')),
        ],
      ),
    );
    if (ok == true) return v;
    return null;
  }

  Future<void> _addNap() async {
    final result = await _napDialog();
    if (result == null) return;
    final list = ((sleep['naps'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    list.add(result);
    setState(() => sleep['naps'] = list);
  }

  Future<void> _editNap(int index) async {
    final list = ((sleep['naps'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (index < 0 || index >= list.length) return;
    final result = await _napDialog(init: list[index]);
    if (result == null) return;
    list[index] = result;
    setState(() => sleep['naps'] = list);
  }

  Future<Map<String, dynamic>?> _napDialog({Map<String, dynamic>? init}) async {
  TimeOfDay? start = DateHelper.parseTime(init?['start']);
  TimeOfDay? end   = DateHelper.parseTime(init?['end']);

  // 一開始如果是新增（沒有初始值），先給 0 即可
  int minutes = 0;
  if (start != null && end != null) {
    minutes = DateHelper.calcDurationMinutes(start, end);
  }

  String fmt(TimeOfDay? t) => t == null ? '-' : t.format(context);

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          // 重新計算分鐘數
          void recalc() {
            if (start != null && end != null) {
              minutes = DateHelper.calcDurationMinutes(start!, end!);
            } else {
              minutes = 0;
            }
            setState(() {});
          }

          Future<void> pickStart() async {
            final v = await showTimePicker(
              context: ctx,
              initialTime: start ?? TimeOfDay.now(),
            );
            if (v != null) {
              start = v;
              recalc();
            }
          }

          Future<void> pickEnd() async {
            final v = await showTimePicker(
              context: ctx,
              initialTime: end ?? (start ?? TimeOfDay.now()),
            );
            if (v != null) {
              end = v;
              recalc();
            }
          }

          final canSubmit = start != null && end != null && minutes > 0;

          return AlertDialog(
            title: const Text('小睡（開始 / 結束）'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('開始時間'),
                  trailing: Text(fmt(start)),
                  onTap: pickStart,
                ),
                ListTile(
                  title: const Text('結束時間'),
                  trailing: Text(fmt(end)),
                  onTap: pickEnd,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('時長：${DateHelper.formatDurationText(minutes)}'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                // 只有條件成立才可按
                onPressed: canSubmit
                    ? () {
                        Navigator.pop<Map<String, dynamic>>(ctx, {
                          'start': fmt(start),
                          'end'  : fmt(end),
                          'minutes': minutes,
                        });
                      }
                    : null,
                child: const Text('確定'),
              ),
            ],
          );
        },
      );
    },
  );
}
}
