import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../diary/diary_repository.dart';
import '../meds/medication_local_db.dart';
import 'innera_ai_message.dart';
import 'innera_ai_mode.dart';

class InneraAiContextBundle {
  const InneraAiContextBundle({
    required this.data,
    required this.sources,
    this.partialFailureMessage,
  });

  final Map<String, dynamic> data;
  final List<AiContextSource> sources;
  final String? partialFailureMessage;

  bool get hasSources => sources.isNotEmpty;
}

class InneraAiContextService {
  InneraAiContextService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DiaryRepository? diaryRepository,
    MedicationLocalDB? medicationDb,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _diaryRepository = diaryRepository ?? DiaryRepository(),
        _medicationDb = medicationDb ?? MedicationLocalDB();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final DiaryRepository _diaryRepository;
  final MedicationLocalDB _medicationDb;

  Future<InneraAiContextBundle> buildContext({
    required InneraAiMode mode,
    required String latestUserMessage,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('請先登入後再使用心域 AI。');
    }

    final now = DateTime.now();
    final today = _dateOnly(now);
    final lookbackDays = mode == InneraAiMode.recentReview ? 30 : 14;
    final start = today.subtract(Duration(days: lookbackDays - 1));
    final data = <String, dynamic>{
      'mode': mode.systemPromptKey,
      'generatedAt': now.toIso8601String(),
      'lookbackDays': lookbackDays,
    };
    final sources = <AiContextSource>[];
    final failures = <String>[];

    Future<void> guard(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (e, stack) {
        debugPrint('InneraAiContextService $label failed: $e');
        debugPrint('$stack');
        failures.add(label);
      }
    }

    switch (mode) {
      case InneraAiMode.dailyRecord:
        await guard('dailyRecords', () async {
          final todayRecord = await _dailyRecordDoc(uid, today);
          data['todayDailyRecord'] = _compactDailyRecord(todayRecord);
          data['todaySleep'] = _compactSleep(todayRecord?['sleep']);
          if (todayRecord != null) {
            sources.add(
              AiContextSource(
                label: '今日每日紀錄',
                dateRange: _formatDate(today),
                count: 1,
              ),
            );
          }
        });
        await guard('diary', () async {
          final todayDiary = await _diaryRepository.getByDate(today);
          data['todayDiary'] = _compactDiary(todayDiary, maxChars: 360);
          if (todayDiary != null) {
            sources.add(
              AiContextSource(
                label: '今日日記',
                dateRange: _formatDate(today),
                count: 1,
              ),
            );
          }
        });
        break;

      case InneraAiMode.emotionalSupport:
        await guard('dailyRecords', () async {
          final records = await _dailyRecords(
            uid,
            today.subtract(const Duration(days: 2)),
            today,
          );
          data['recentMoodSummary'] = records.map(_compactMoodOnly).toList();
          if (records.isNotEmpty) {
            sources.add(
              AiContextSource(
                label: '最近 3 天情緒概要',
                dateRange: _rangeLabel(
                  today.subtract(const Duration(days: 2)),
                  today,
                ),
                count: records.length,
              ),
            );
          }
        });
        break;

      case InneraAiMode.physicalHealth:
        await guard('dailyRecords', () async {
          final records = await _dailyRecords(uid, start, today);
          data['recentSymptomsAndSleep'] =
              records.map(_compactSymptomsAndSleep).toList();
          final abnormalSleepCount = records
              .where((record) => _hasSleepConcern(record['sleep']))
              .length;
          if (records.isNotEmpty) {
            sources.add(
              AiContextSource(
                label: '最近 14 天每日紀錄',
                dateRange: _rangeLabel(start, today),
                count: records.length,
              ),
            );
          }
          if (abnormalSleepCount > 0) {
            sources.add(
              AiContextSource(
                label: '睡眠異常紀錄',
                dateRange: _rangeLabel(start, today),
                count: abnormalSleepCount,
              ),
            );
          }
        });
        await _loadMedicationContext(
          uid,
          start,
          today,
          data,
          sources,
          failures,
        );
        await _loadPeriodContext(uid, start, today, data, sources, failures);
        await _loadRelatedDiaries(start, today, data, sources, failures);
        break;

      case InneraAiMode.recentReview:
        await guard('dailyRecords', () async {
          final records = await _dailyRecords(uid, start, today);
          data['dailyRecordStats'] = _buildDailyRecordStats(
            records,
            start,
            today,
          );
          data['recentDailyRecords'] =
              records.map(_compactDailyRecord).toList();
          if (records.isNotEmpty) {
            sources.add(
              AiContextSource(
                label: '最近 30 天每日紀錄',
                dateRange: _rangeLabel(start, today),
                count: records.length,
              ),
            );
          }
        });
        await _loadMedicationContext(
          uid,
          start,
          today,
          data,
          sources,
          failures,
        );
        await _loadPeriodContext(uid, start, today, data, sources, failures);
        await _loadRecentDiaries(start, today, data, sources, failures);
        break;
    }

    return InneraAiContextBundle(
      data: _limitMap(data),
      sources: sources,
      partialFailureMessage:
          failures.isEmpty ? null : '目前無法載入部分近期紀錄，這次回答只會根據可取得的紀錄與你在對話中提供的內容。',
    );
  }

  Future<void> _loadMedicationContext(
    String uid,
    DateTime start,
    DateTime today,
    Map<String, dynamic> data,
    List<AiContextSource> sources,
    List<String> failures,
  ) async {
    try {
      final meds = await _medicationDb.getMedicationsForDisplay(uid);
      final activeMeds = meds
          .where((med) => med['isActive'] != false)
          .map(_compactMedication)
          .toList();
      data['activeMedications'] = activeMeds;
      if (activeMeds.isNotEmpty) {
        sources.add(
          AiContextSource(
            label: '目前用藥資料',
            dateRange: '目前',
            count: activeMeds.length,
          ),
        );
      }

      final adjustments =
          (await _medicationDb.getAdjustmentRecordsForDisplay(uid))
              .where((item) {
                final date = _asDate(item['date']);
                return date != null &&
                    !_dateOnly(date).isBefore(start) &&
                    !date.isAfter(today);
              })
              .map(_compactAdjustment)
              .toList();
      data['recentMedicationAdjustments'] = adjustments;
      if (adjustments.isNotEmpty) {
        sources.add(
          AiContextSource(
            label: '用藥異動紀錄',
            dateRange: _rangeLabel(start, today),
            count: adjustments.length,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InneraAiContextService medications failed: $e');
      debugPrint('$stack');
      failures.add('medications');
    }
  }

  Future<void> _loadPeriodContext(
    String uid,
    DateTime start,
    DateTime today,
    Map<String, dynamic> data,
    List<AiContextSource> sources,
    List<String> failures,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('periodCycles')
          .where('startDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('startDate', descending: true)
          .limit(6)
          .get();
      final cycles = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((cycle) {
            final end =
                _asDate(cycle['endDate']) ?? _asDate(cycle['startDate']);
            return end == null || !end.isBefore(start);
          })
          .map(
            (cycle) => {
              'id': cycle['id'],
              'startDate': _formatNullableDate(_asDate(cycle['startDate'])),
              'endDate': _formatNullableDate(_asDate(cycle['endDate'])),
            },
          )
          .toList();
      data['recentPeriodCycles'] = cycles;
      if (cycles.isNotEmpty) {
        sources.add(
          AiContextSource(
            label: '經期資料',
            dateRange: _rangeLabel(start, today),
            count: cycles.length,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InneraAiContextService periodCycles failed: $e');
      debugPrint('$stack');
      failures.add('periodCycles');
    }
  }

  Future<void> _loadRecentDiaries(
    DateTime start,
    DateTime today,
    Map<String, dynamic> data,
    List<AiContextSource> sources,
    List<String> failures,
  ) async {
    try {
      final diaries = (await _diaryRepository.list(limit: 60))
          .where((entry) {
            final date = _dateOnly(entry.date);
            return !date.isBefore(start) && !date.isAfter(today);
          })
          .map((entry) => _compactDiary(entry, maxChars: 240))
          .whereType<Map<String, dynamic>>()
          .toList();
      data['recentDiaries'] = diaries;
      if (diaries.isNotEmpty) {
        sources.add(
          AiContextSource(
            label: '近期日記摘要',
            dateRange: _rangeLabel(start, today),
            count: diaries.length,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InneraAiContextService diaries failed: $e');
      debugPrint('$stack');
      failures.add('diary');
    }
  }

  Future<void> _loadRelatedDiaries(
    DateTime start,
    DateTime today,
    Map<String, dynamic> data,
    List<AiContextSource> sources,
    List<String> failures,
  ) async {
    try {
      final keywords = ['痛', '暈', '吐', '睡', '藥', '不舒服', '胸', '胃', '頭', '過敏'];
      final diaries = (await _diaryRepository.list(limit: 45))
          .where((entry) {
            final date = _dateOnly(entry.date);
            if (date.isBefore(start) || date.isAfter(today)) return false;
            final text = '${entry.title}\n${entry.content}';
            return keywords.any(text.contains);
          })
          .take(5)
          .map((entry) => _compactDiary(entry, maxChars: 180))
          .whereType<Map<String, dynamic>>()
          .toList();
      data['bodyRelatedDiaries'] = diaries;
      if (diaries.isNotEmpty) {
        sources.add(
          AiContextSource(
            label: '身體不適相關日記摘要',
            dateRange: _rangeLabel(start, today),
            count: diaries.length,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('InneraAiContextService related diaries failed: $e');
      debugPrint('$stack');
      failures.add('relatedDiary');
    }
  }

  Future<Map<String, dynamic>?> _dailyRecordDoc(
    String uid,
    DateTime date,
  ) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .doc(_formatDate(date))
        .get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...?doc.data()};
  }

  Future<List<Map<String, dynamic>>> _dailyRecords(
    String uid,
    DateTime start,
    DateTime end,
  ) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('dailyRecords')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where(
          'date',
          isLessThanOrEqualTo: Timestamp.fromDate(
            end.add(const Duration(days: 1)),
          ),
        )
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Map<String, dynamic> _compactDailyRecord(Map<String, dynamic>? record) {
    if (record == null) return const <String, dynamic>{'exists': false};
    final sleep = _compactSleep(record['sleep']);
    return {
      'exists': true,
      'date': _recordDate(record),
      'overallMood': record['overallMood'],
      'emotions': _compactEmotions(record['emotions']),
      'symptoms': _stringList(
        record['bodySymptoms'] ?? record['symptoms'],
      ).take(12).toList(),
      'sleep': sleep,
      'isPeriod': record['isPeriod'] == true ||
          (record['periodData'] is Map &&
              record['periodData']['isPeriod'] == true),
    };
  }

  Map<String, dynamic> _compactMoodOnly(Map<String, dynamic> record) {
    return {
      'date': _recordDate(record),
      'overallMood': record['overallMood'],
      'emotions': _compactEmotions(record['emotions']).take(8).toList(),
    };
  }

  Map<String, dynamic> _compactSymptomsAndSleep(Map<String, dynamic> record) {
    return {
      'date': _recordDate(record),
      'symptoms': _stringList(
        record['bodySymptoms'] ?? record['symptoms'],
      ).take(12).toList(),
      'sleep': _compactSleep(record['sleep']),
      'isPeriod': record['isPeriod'] == true ||
          (record['periodData'] is Map &&
              record['periodData']['isPeriod'] == true),
    };
  }

  Map<String, dynamic> _compactSleep(dynamic raw) {
    if (raw is! Map) return const <String, dynamic>{};
    return {
      'sleepTime': raw['sleepTime'],
      'wakeTime': raw['wakeTime'],
      'finalWakeTime': raw['finalWakeTime'],
      'quality': raw['quality'],
      'flags': _stringList(raw['flags']).take(8).toList(),
      'napsCount': raw['naps'] is List ? (raw['naps'] as List).length : 0,
      if ((raw['note'] ?? '').toString().trim().isNotEmpty)
        'note': _limitText(raw['note'], 160),
    };
  }

  Map<String, dynamic>? _compactDiary(
    DiaryEntry? entry, {
    required int maxChars,
  }) {
    if (entry == null) return null;
    final parts = [
      entry.title,
      entry.content,
      entry.highlight,
      entry.selfCare,
      entry.gratitude,
    ].where((text) => text != null && text.trim().isNotEmpty).join('\n');
    return {
      'date': _formatDate(entry.date),
      'title': _limitText(entry.title, 80),
      'summary': _limitText(parts, maxChars),
    };
  }

  Map<String, dynamic> _compactMedication(Map<String, dynamic> med) {
    return {
      'id': med['id'],
      'name': _limitText(med['name'] ?? med['nameZh'] ?? med['nameEn'], 80),
      'dose': med['dose'],
      'dosePerUnit': med['dosePerUnit'],
      'pillCount': med['pillCount'],
      'unit': med['unit'],
      'type': med['type'],
      'times': _stringList(med['times']).take(8).toList(),
      'purposes': _stringList(med['purposes']).take(8).toList(),
      'startDate': _formatNullableDate(_asDate(med['startDate'])),
      'lastChangeAt': _formatNullableDate(_asDate(med['lastChangeAt'])),
    };
  }

  Map<String, dynamic> _compactAdjustment(Map<String, dynamic> adj) {
    return {
      'date': _formatNullableDate(_asDate(adj['date'])),
      'type': adj['type'],
      'itemsCount': adj['items'] is List ? (adj['items'] as List).length : null,
      'note': _limitText(adj['note'], 120),
    };
  }

  Map<String, dynamic> _buildDailyRecordStats(
    List<Map<String, dynamic>> records,
    DateTime start,
    DateTime today,
  ) {
    final moodValues = <double>[];
    final sleepHours = <double>[];
    final emotionCounts = <String, int>{};
    final symptomCounts = <String, int>{};
    var sleepConcernDays = 0;
    final medChangeDates = <String>{};

    for (final record in records) {
      final mood = _asDouble(record['overallMood']);
      if (mood != null) moodValues.add(mood);
      for (final emotion in _compactEmotions(record['emotions'])) {
        final name = (emotion['name'] ?? '').toString();
        if (name.isNotEmpty && name != '整體情緒') {
          emotionCounts[name] = (emotionCounts[name] ?? 0) + 1;
        }
      }
      for (final symptom in _stringList(
        record['bodySymptoms'] ?? record['symptoms'],
      )) {
        symptomCounts[symptom] = (symptomCounts[symptom] ?? 0) + 1;
      }
      final sleep = record['sleep'];
      if (_hasSleepConcern(sleep)) sleepConcernDays++;
      final hours = _sleepHours(sleep);
      if (hours != null) sleepHours.add(hours);
      final meds = record['medicines'];
      if (meds is List && meds.isNotEmpty) {
        medChangeDates.add(_recordDate(record));
      }
    }

    final expectedDays = today.difference(start).inDays + 1;
    return {
      'recordedDays': records.length,
      'expectedDays': expectedDays,
      'missingDays': max(0, expectedDays - records.length),
      'averageOverallMood': _average(moodValues),
      'averageSleepHours': _average(sleepHours),
      'commonEmotions': _topCounts(emotionCounts),
      'commonSymptoms': _topCounts(symptomCounts),
      'sleepConcernDays': sleepConcernDays,
      'medicationChangeDates': medChangeDates.toList()..sort(),
    };
  }

  List<Map<String, dynamic>> _compactEmotions(dynamic raw) {
    if (raw is Map) {
      return raw.entries
          .map(
            (entry) => {
              'name': entry.key.toString(),
              'value': _asDouble(entry.value),
            },
          )
          .where((entry) => (entry['name'] ?? '').toString().trim().isNotEmpty)
          .toList();
    }
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map(
            (entry) => {
              'name': (entry['name'] ?? '').toString(),
              'value': _asDouble(entry['value']),
            },
          )
          .where((entry) => (entry['name'] ?? '').toString().trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  bool _hasSleepConcern(dynamic raw) {
    if (raw is! Map) return false;
    final flags = _stringList(raw['flags']);
    final quality = _asDouble(raw['quality']);
    return flags.isNotEmpty || (quality != null && quality <= 2);
  }

  double? _sleepHours(dynamic raw) {
    if (raw is! Map) return null;
    final sleep = _parseClock(raw['sleepTime']);
    final wake = _parseClock(raw['finalWakeTime'] ?? raw['wakeTime']);
    if (sleep == null || wake == null) return null;
    var minutes = wake - sleep;
    if (minutes <= 0) minutes += 24 * 60;
    return double.parse((minutes / 60).toStringAsFixed(1));
  }

  int? _parseClock(dynamic value) {
    final text = (value ?? '').toString();
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  List<Map<String, dynamic>> _topCounts(Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(6)
        .map((entry) => {'name': entry.key, 'count': entry.value})
        .toList();
  }

  double? _average(List<double> values) {
    if (values.isEmpty) return null;
    final total = values.fold<double>(0, (total, value) => total + value);
    return double.parse((total / values.length).toStringAsFixed(1));
  }

  Map<String, dynamic> _limitMap(Map<String, dynamic> input) {
    final encoded = input.toString();
    if (encoded.length <= 12000) return input;
    return {
      ...input,
      'recentDailyRecords':
          (input['recentDailyRecords'] as List?)?.take(18).toList(),
      'recentDiaries': (input['recentDiaries'] as List?)?.take(8).toList(),
      'bodyRelatedDiaries':
          (input['bodyRelatedDiaries'] as List?)?.take(4).toList(),
    };
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,，、\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _recordDate(Map<String, dynamic> record) {
    return _formatNullableDate(_asDate(record['date'])) ??
        (record['id'] ?? '').toString();
  }

  String _limitText(dynamic value, int maxChars) {
    final text = (value ?? '').toString().trim();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}...';
  }

  String _formatDate(DateTime date) {
    final day = _dateOnly(date);
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  String? _formatNullableDate(DateTime? date) =>
      date == null ? null : _formatDate(date);

  String _rangeLabel(DateTime start, DateTime end) =>
      '${_formatDate(start)} 至 ${_formatDate(end)}';
}
