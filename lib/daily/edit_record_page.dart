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
import '../models/daily_record.dart';
import 'widgets/night_awakening_editor.dart';
import 'daily_state_dimensions.dart';
import 'symptom_definitions.dart';
import 'body_measurement_input.dart';
import 'sleep_record_service.dart';
import 'unified_sleep_repository.dart';
import '../models/sleep_record.dart';
import '../models/body_measurement_record.dart';
import 'body_measurement_record_service.dart';
import 'unified_body_measurement_repository.dart';

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
    final bodyMeasurement = _currentBodyMeasurement;
    if (bodyMeasurement?.isValid == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先修正身體數據的輸入範圍')),
      );
      return;
    }
    setState(() => _saving = true);

    // 你要的提示：「開始儲存情緒、症狀、睡眠」
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開始儲存情緒、症狀、睡眠')),
      );
    }

    debugPrint('💾 開始保存編輯紀錄');

    try {
      final uid = widget.uid;
      final docId = widget.docId;
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dailyRecords')
          .doc(docId);

// 先把目前畫面上的睡眠欄位整理成新的 Map
// 注意：要保留現有的所有值，只更新改動的部分
      final Map<String, dynamic> newSleep = Map<String, dynamic>.from(sleep);

// 有沒有吃安眠藥
      newSleep['tookHypnotic'] = _tookHypnotic;

// 藥名、劑量（沒有就存空字串）
      newSleep['hypnoticName'] = _hypNameCtrl.text.trim();
      newSleep['hypnoticDose'] = _hypDoseCtrl.text.trim();

// 準備睡覺時間、推估入睡時間、起床時間
      if (_sleepTime != null) {
        newSleep['sleepTime'] = DateHelper.formatTime(_sleepTime);
      } else {
        newSleep.remove('sleepTime');
      }

      if (_estimatedSleepTime != null) {
        newSleep['estimatedSleepTime'] =
            DateHelper.formatTime(_estimatedSleepTime);
      } else {
        newSleep.remove('estimatedSleepTime');
      }

      if (_wakeTime != null) {
        newSleep['wakeTime'] = DateHelper.formatTime(_wakeTime);
      } else {
        newSleep.remove('wakeTime');
      }

      newSleep['nightAwakenings'] =
          _nightAwakenings.map((item) => item.toMap()).toList();

// 自覺睡眠品質
      if (_sleepQuality != null) {
        newSleep['quality'] = _sleepQuality;
      } else {
        newSleep.remove('quality');
      }

// flags / note / naps：更新旗標和備註
      newSleep['flags'] =
          (sleep['flags'] as List?)?.map((e) => e.toString()).toList() ?? [];
      newSleep['note'] = (sleep['note'] ?? '').toString();

      final List<Map<String, dynamic>> naps =
          ((sleep['naps'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      newSleep['naps'] = naps;

// 最後再組 payload
      final payload = <String, dynamic>{
        'emotions': emotions,
        'symptoms': symptoms.map(normalizeSymptomName).toSet().toList(),
        'stateChanges': stateChanges,
        'symptomSectionCompleted': true,
        'emotionSectionCompleted': true,
        'stateSectionCompleted': true,
        'savedAt': FieldValue.serverTimestamp(),
      };

      final recordDate = DateHelper.parseIdToDate(docId) ?? DateTime.now();
      final sleepRecord =
          SleepRecord.fromMap({...newSleep, 'date': recordDate});
      if (sleepRecord.hasData) {
        await SleepRecordService().save(userId: uid, record: sleepRecord);
      }
      if (bodyMeasurement?.hasData == true) {
        final now = DateTime.now();
        final timestamp = _editingBodyMeasurement?.timestamp ??
            DateTime(
              recordDate.year,
              recordDate.month,
              recordDate.day,
              now.hour,
              now.minute,
              now.second,
            );
        await BodyMeasurementRecordService().save(
          userId: uid,
          record: BodyMeasurementRecord(
            id: _editingBodyMeasurement?.id ?? '',
            timestamp: timestamp,
            weightKg: bodyMeasurement!.weightKg,
            bodyFatPercent: bodyMeasurement.bodyFatPercent,
            waistCm: bodyMeasurement.waistCm,
            measurementTiming: bodyMeasurement.measurementTiming,
            otherTimingText: bodyMeasurement.effectiveCustomMeasurementTime,
          ),
        );
      }

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
          date: DateHelper.parseIdToDate(docId) ?? DateTime.now(),
          emotions: Map<String, dynamic>.from(emotions
              .where((e) =>
                  e['value'] != null &&
                  e['name'] != '整體情緒') // Exclude overallMood
              .toList()
              .asMap()
              .map((k, v) => MapEntry(v['name'] ?? '', v['value']))),
          stateChanges: Map<String, int>.from(stateChanges),
          symptomSectionCompleted: true,
          emotionSectionCompleted: true,
          stateSectionCompleted: true,
          // symptoms 已經是 List<String>，僅過濾空白
          bodySymptoms: symptoms
              .map(normalizeSymptomName)
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList(),
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
  late List<String> symptoms; // ['心悸', '頭痛', ...]
  late Map<String, int> stateChanges;
  BodyMeasurement? _initialBodyMeasurement;
  BodyMeasurementRecord? _editingBodyMeasurement;
  late Map<String, dynamic> sleep; // 見下方 keys

  // 睡眠控制器（避免 TextField 反向輸入）
  late final TextEditingController _hypNameCtrl;
  late final TextEditingController _hypDoseCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _bodyFatCtrl;
  late final TextEditingController _waistCtrl;
  late final TextEditingController _customMeasurementTimeCtrl;
  MeasurementTiming? _measurementTiming;
  TimeOfDay? _sleepTime;
  TimeOfDay? _estimatedSleepTime;
  final List<NightAwakeningItem> _nightAwakenings = [];
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

    symptoms = ((init['symptoms'] as List?) ??
            (init['bodySymptoms'] as List?) ??
            const [])
        .map((e) => normalizeSymptomName(e.toString()))
        .toSet()
        .toList();

    final parsedRecord = DailyRecord.fromData(widget.docId, init);
    stateChanges = Map<String, int>.from(parsedRecord.stateChanges);
    _initialBodyMeasurement = parsedRecord.bodyMeasurement;
    _weightCtrl = TextEditingController(
      text: formatBodyMeasurementNumber(_initialBodyMeasurement?.weightKg),
    );
    _bodyFatCtrl = TextEditingController(
      text: formatBodyMeasurementNumber(
        _initialBodyMeasurement?.bodyFatPercent,
      ),
    );
    _waistCtrl = TextEditingController(
      text: formatBodyMeasurementNumber(_initialBodyMeasurement?.waistCm),
    );
    _customMeasurementTimeCtrl = TextEditingController(
      text: _initialBodyMeasurement?.effectiveCustomMeasurementTime ?? '',
    );
    _measurementTiming = _initialBodyMeasurement?.measurementTiming;

    sleep = Map<String, dynamic>.from((init['sleep'] as Map?) ?? const {});

    _tookHypnotic = sleep['tookHypnotic'] == true;
    _hypNameCtrl =
        TextEditingController(text: (sleep['hypnoticName'] ?? '').toString());
    _hypDoseCtrl =
        TextEditingController(text: (sleep['hypnoticDose'] ?? '').toString());
    _nightAwakenings.addAll(
      (sleep['nightAwakenings'] as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .where((item) => DateHelper.parseTime(item['start']) != null)
              .map(NightAwakeningItem.fromMap) ??
          const [],
    );
    _sleepTime = DateHelper.parseTime(sleep['sleepTime']);
    _estimatedSleepTime = DateHelper.parseTime(sleep['estimatedSleepTime']);
    _wakeTime = DateHelper.parseTime(sleep['wakeTime']);
    final savedSleepQuality = sleep['quality'];
    _sleepQuality = savedSleepQuality is num
        ? savedSleepQuality.round().clamp(1, 5).toInt()
        : null;

    debugPrint('🛏️ 編輯頁已載入睡眠欄位');
    _loadUnifiedSleep();
    _loadUnifiedBodyMeasurement();
  }

  Future<void> _loadUnifiedBodyMeasurement() async {
    final date = DateHelper.parseIdToDate(widget.docId);
    if (date == null) return;
    try {
      final records = await UnifiedBodyMeasurementRepository().getByDateRange(
        userId: widget.uid,
        start: date,
        end: date,
      );
      final trend = UnifiedBodyMeasurementRepository.selectDailyTrend(records);
      if (!mounted || trend.isEmpty) return;
      final latest = trend.single;
      setState(() {
        if (latest.source == BodyMeasurementSource.bodyMeasurementRecord) {
          _editingBodyMeasurement = BodyMeasurementRecord(
            id: latest.id ?? '',
            timestamp: latest.timestamp!,
            weightKg: latest.measurement.weightKg,
            bodyFatPercent: latest.measurement.bodyFatPercent,
            waistCm: latest.measurement.waistCm,
            measurementTiming: latest.measurement.measurementTiming,
            otherTimingText: latest.measurement.effectiveCustomMeasurementTime,
          );
        }
        _weightCtrl.text =
            formatBodyMeasurementNumber(latest.measurement.weightKg);
        _bodyFatCtrl.text =
            formatBodyMeasurementNumber(latest.measurement.bodyFatPercent);
        _waistCtrl.text =
            formatBodyMeasurementNumber(latest.measurement.waistCm);
        _measurementTiming = latest.measurement.measurementTiming;
        _customMeasurementTimeCtrl.text =
            latest.measurement.effectiveCustomMeasurementTime ?? '';
      });
    } catch (error) {
      debugPrint('BodyMeasurementRecord load failed: $error');
    }
  }

  Future<void> _loadUnifiedSleep() async {
    final date = DateHelper.parseIdToDate(widget.docId);
    if (date == null) return;
    try {
      final unified = await UnifiedSleepRepository().getForDate(
        userId: widget.uid,
        date: date,
      );
      if (!mounted || unified == null) return;
      final data = unified.record.toSleepData().toMap();
      setState(() {
        sleep = Map<String, dynamic>.from(data);
        _tookHypnotic = sleep['tookHypnotic'] == true;
        _hypNameCtrl.text = (sleep['hypnoticName'] ?? '').toString();
        _hypDoseCtrl.text = (sleep['hypnoticDose'] ?? '').toString();
        _sleepTime = DateHelper.parseTime(sleep['sleepTime']);
        _estimatedSleepTime = DateHelper.parseTime(sleep['estimatedSleepTime']);
        _wakeTime = DateHelper.parseTime(sleep['wakeTime']);
        _sleepQuality = (sleep['quality'] as num?)?.toInt();
        _nightAwakenings
          ..clear()
          ..addAll(unified.record.nightAwakenings);
      });
    } catch (error) {
      debugPrint('SleepRecord load failed: $error');
    }
  }

  @override
  void dispose() {
    _hypNameCtrl.dispose();
    _hypDoseCtrl.dispose();
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    _waistCtrl.dispose();
    _customMeasurementTimeCtrl.dispose();
    super.dispose();
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) async {
    final now = TimeOfDay.now();
    return showTimePicker(
      context: context,
      initialTime: initial ?? now,
    );
  }

  Widget _buildNightAwakeningsEditor() {
    final legacyText = (sleep['midWakeList'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '夜間醒來',
            style: HealingDesignSystem.bodyMedium.copyWith(
              color: HealingDesignSystem.adaptivePrimaryText(context),
            ),
          ),
          for (var i = 0; i < _nightAwakenings.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_outlined),
              title: Text(_nightAwakeningLabel(_nightAwakenings[i])),
              subtitle: _nightAwakenings[i].note?.trim().isNotEmpty == true
                  ? Text(_nightAwakenings[i].note!.trim())
                  : null,
              onTap: () async {
                final item = await showNightAwakeningEditor(
                  context,
                  initial: _nightAwakenings[i],
                );
                if (item != null && mounted) {
                  setState(() => _nightAwakenings[i] = item);
                }
              },
              trailing: IconButton(
                tooltip: '刪除這筆夜間醒來',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => setState(
                  () => _nightAwakenings.removeAt(i),
                ),
              ),
            ),
          if (legacyText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HealingDesignSystem.adaptiveFill(context),
                borderRadius: BorderRadius.circular(
                  HealingDesignSystem.radiusS,
                ),
              ),
              child: Text(
                '舊版夜間醒來註記：$legacyText',
                style: HealingDesignSystem.bodySmall.copyWith(
                  color: HealingDesignSystem.mutedText,
                ),
              ),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () async {
              final item = await showNightAwakeningEditor(context);
              if (item != null && mounted) {
                setState(() => _nightAwakenings.add(item));
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('新增夜間醒來'),
          ),
        ],
      ),
    );
  }

  String _nightAwakeningLabel(NightAwakeningItem item) {
    final start = DateHelper.formatTime(item.start);
    if (item.end != null) {
      return '$start → ${DateHelper.formatTime(item.end)}';
    }
    if (item.estimatedDurationMinutes != null) {
      return '$start · 約 ${item.estimatedDurationMinutes} 分鐘';
    }
    return start;
  }

  BodyMeasurement? get _currentBodyMeasurement {
    final measurement = BodyMeasurement(
      weightKg: parseBodyMeasurementNumber(_weightCtrl.text),
      bodyFatPercent: parseBodyMeasurementNumber(_bodyFatCtrl.text),
      waistCm: parseBodyMeasurementNumber(_waistCtrl.text),
      measuredAt: _initialBodyMeasurement?.measuredAt,
      measurementTiming: _measurementTiming,
      customMeasurementTime: _measurementTiming == MeasurementTiming.other
          ? _customMeasurementTimeCtrl.text.trim()
          : null,
    );
    return measurement.hasData ? measurement : null;
  }

  Widget _measurementField(
    TextEditingController controller,
    String label,
    String unit,
    double min,
    double max,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          const OneDecimalTextInputFormatter(),
        ],
        decoration: InputDecoration(labelText: label, suffixText: unit),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (raw) {
          return validateBodyMeasurementNumber(
            raw,
            min: min,
            max: max,
            unit: unit,
          );
        },
      ),
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
        iconTheme: IconThemeData(
            color: HealingDesignSystem.adaptiveAppBarForeground(context)),
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
                  ListTile(
                      title: Text('沒有情緒項目',
                          style: TextStyle(
                              color: HealingDesignSystem.adaptiveSecondaryText(
                                  context)))),
                ...emotions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  return ListTile(
                    title: Text(m['name']?.toString() ?? '',
                        style: HealingDesignSystem.bodyMedium.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context))),
                    subtitle: Slider(
                      value: ((m['value'] as num?)?.toDouble() ?? 1).clamp(
                          1, widget.initData['moodScale'] == 10 ? 10 : 5),
                      min: 1,
                      max: widget.initData['moodScale'] == 10 ? 10 : 5,
                      divisions: widget.initData['moodScale'] == 10 ? 9 : 4,
                      label: '${m['value'] ?? 1}',
                      activeColor: HealingDesignSystem.primaryBlue,
                      inactiveColor: HealingDesignSystem.lineColor,
                      onChanged: (v) =>
                          setState(() => emotions[idx]['value'] = v.round()),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: HealingDesignSystem.dangerRed),
                      onPressed: () => setState(() => emotions.removeAt(idx)),
                    ),
                  );
                }),
              ],
            ),
          ),

          _sectionHeader('今日狀態變化'),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: HealingDesignSystem.adaptiveCardDecoration(context),
            child: ExpansionTile(
              title: const Text('請和平常的自己相比'),
              subtitle: const Text('3 分代表和平常差不多；未操作不會儲存'),
              children: kDailyStateDimensions.map((dimension) {
                final value = stateChanges[dimension.id];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(dimension.displayName)),
                        if (value == null)
                          const Text('尚未填寫')
                        else
                          TextButton(
                            onPressed: () => setState(
                                () => stateChanges.remove(dimension.id)),
                            child: const Text('清除'),
                          ),
                      ]),
                      Text(dimension.question),
                      Slider(
                        value: (value ?? 3).toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: value?.toString() ?? '尚未填寫',
                        onChanged: (next) => setState(
                          () => stateChanges[dimension.id] = next.round(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
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
                  ListTile(
                      title: Text('沒有症狀項目',
                          style: TextStyle(
                              color: HealingDesignSystem.adaptiveSecondaryText(
                                  context)))),
                ...symptoms.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  return Dismissible(
                    key: ValueKey('sym-$idx-$s'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      decoration: BoxDecoration(
                        color: HealingDesignSystem.dangerRed,
                        borderRadius:
                            BorderRadius.circular(HealingDesignSystem.radiusM),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => setState(() => symptoms.removeAt(idx)),
                    child: ListTile(
                        title: Text(s,
                            style: HealingDesignSystem.bodyMedium.copyWith(
                                color: HealingDesignSystem.adaptivePrimaryText(
                                    context)))),
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
                  title: Text('前一晚是否服用安眠藥',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  value: _tookHypnotic,
                  activeColor: HealingDesignSystem.primaryBlue,
                  onChanged: (v) => setState(() => _tookHypnotic = v),
                  contentPadding: EdgeInsets.zero,
                ),
                _textTile('藥物名稱', _hypNameCtrl),
                _textTile('劑量', _hypDoseCtrl),
                // 準備睡覺 / 推估入睡 / 起床
                ListTile(
                  title: Text('準備睡覺時間',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  trailing: Text(DateHelper.formatTime(_sleepTime),
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  onTap: () async {
                    final t = await _pickTime(_sleepTime);
                    if (t != null) setState(() => _sleepTime = t);
                  },
                ),
                ListTile(
                  title: Text('推估入睡時間（選填）',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  subtitle: Text(
                    _estimatedSleepTime == null
                        ? '留空時以準備睡覺時間估算'
                        : DateHelper.formatTime(_estimatedSleepTime),
                  ),
                  onTap: () async {
                    final t =
                        await _pickTime(_estimatedSleepTime ?? _sleepTime);
                    if (t != null) setState(() => _estimatedSleepTime = t);
                  },
                ),
                _buildNightAwakeningsEditor(),
                ListTile(
                  title: Text('起床時間',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  trailing: Text(DateHelper.formatTime(_wakeTime),
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  onTap: () async {
                    final t = await _pickTime(_wakeTime);
                    if (t != null) setState(() => _wakeTime = t);
                  },
                ),
                // 自覺睡眠品質
                ListTile(
                  title: Text('自覺睡眠品質（1~5）',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  trailing: Text(_sleepQuality?.toString() ?? '-',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  onTap: () async {
                    final v = await _pickQuality(context, _sleepQuality ?? 3);
                    if (v != null) setState(() => _sleepQuality = v);
                  },
                ),
                // 夜間睡眠狀況 flags
                const SizedBox(height: 8),
                Text('夜間睡眠狀況',
                    style: HealingDesignSystem.titleSmall.copyWith(
                        color:
                            HealingDesignSystem.adaptivePrimaryText(context))),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 8,
                  children: kSleepFlags.map((f) {
                    final key = f['key']!;
                    final label = f['label']!;
                    final selected =
                        ((sleep['flags'] as List?) ?? const []).contains(key);
                    return FilterChip(
                      label: Text(label,
                          style: HealingDesignSystem.bodySmall.copyWith(
                              color: HealingDesignSystem.adaptivePrimaryText(
                                  context))),
                      selected: selected,
                      selectedColor: HealingDesignSystem.adaptiveAccent(context)
                          .withOpacity(0.22),
                      checkmarkColor:
                          HealingDesignSystem.adaptiveAccent(context),
                      backgroundColor:
                          HealingDesignSystem.adaptiveSurface(context),
                      side: BorderSide(
                        color: selected
                            ? HealingDesignSystem.adaptiveAccent(context)
                            : HealingDesignSystem.adaptiveCardBorder(context),
                      ),
                      onSelected: (v) {
                        final list = ((sleep['flags'] as List?) ?? const [])
                            .map((e) => e.toString())
                            .toList();
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
                  title: Text('睡眠註記',
                      style: HealingDesignSystem.bodyMedium.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  subtitle: Text(
                      (sleep['note'] ?? '').toString().isEmpty
                          ? '—'
                          : (sleep['note'] ?? '').toString(),
                      style: HealingDesignSystem.bodySmall.copyWith(
                          color: HealingDesignSystem.adaptivePrimaryText(
                              context))),
                  onTap: () async {
                    final v = await _editNote(
                        context, (sleep['note'] ?? '').toString());
                    if (v != null) setState(() => sleep['note'] = v);
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 32),

          _sectionHeader('身體數據（選填）'),
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(12),
            decoration: HealingDesignSystem.adaptiveCardDecoration(context),
            child: ExpansionTile(
              initiallyExpanded: _initialBodyMeasurement?.hasData == true,
              title: const Text('今天實際測量的數字'),
              children: [
                _measurementField(_weightCtrl, '體重', 'kg', 20, 300),
                _measurementField(_bodyFatCtrl, '體脂率', '%', 1, 70),
                _measurementField(_waistCtrl, '腰圍', 'cm', 30, 250),
                DropdownButtonFormField<MeasurementTiming?>(
                  value: _measurementTiming,
                  decoration: const InputDecoration(labelText: '測量時間'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('尚未填寫')),
                    ...MeasurementTiming.values.map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.displayName),
                        )),
                  ],
                  onChanged: (value) => setState(() {
                    _measurementTiming = value;
                    if (value != MeasurementTiming.other) {
                      _customMeasurementTimeCtrl.clear();
                    }
                  }),
                ),
                if (_measurementTiming == MeasurementTiming.other)
                  TextFormField(
                    controller: _customMeasurementTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: '自訂測量時間',
                      hintText: '例如：運動後、下午三點',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) =>
                        value?.trim().isEmpty == false ? null : '選擇其他時間時請填寫',
                  ),
              ],
            ),
          ),

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
                    title: Text(text,
                        style: HealingDesignSystem.bodyMedium.copyWith(
                            color: HealingDesignSystem.adaptivePrimaryText(
                                context))),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: HealingDesignSystem.dangerRed),
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
          labelStyle: TextStyle(
              color: HealingDesignSystem.adaptiveSecondaryText(context)),
          filled: true,
          fillColor: HealingDesignSystem.adaptiveFill(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(
                color: HealingDesignSystem.adaptiveCardBorder(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(
                color: HealingDesignSystem.adaptiveCardBorder(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HealingDesignSystem.radiusS),
            borderSide: BorderSide(
              color: HealingDesignSystem.adaptiveAccent(context),
              width: 2,
            ),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: value.round().toString(),
                    onChanged: (v) => setState(() => value = v),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('加入')),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('加入')),
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
                min: 1,
                max: 5,
                divisions: 4,
                label: '$temp',
                onChanged: (v) => setLocal(() => temp = v.round()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定')),
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定')),
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
    TimeOfDay? end = DateHelper.parseTime(init?['end']);

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
                            'end': fmt(end),
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
