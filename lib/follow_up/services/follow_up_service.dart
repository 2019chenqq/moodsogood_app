import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../utils/health_data_encryption_service.dart';
import '../models/follow_up_ai_summary.dart';

const _legacyDiscussionTopicAppointmentLabels = <String>{
  '情緒狀況',
  '睡眠品質',
  '藥物副作用',
  '身體不適',
  '食慾變化',
  '生活近況',
  '生活壓力',
  '人際關係',
  '工作／學業',
  '運動習慣',
  '其他',
};

/// 一筆回診資料
class FollowUpAppointment {
  final String id;
  final DateTime date;
  final String label; // 例如：身心科、診所、醫院回診
  final String? note;

  FollowUpAppointment({
    required this.id,
    required this.date,
    this.label = '',
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        'label': label,
        'note': note,
      };

  factory FollowUpAppointment.fromMap(Map<String, dynamic> map) {
    final ts = map['date'];
    DateTime? date;
    if (ts is Timestamp) date = ts.toDate();
    if (ts is String) date = DateTime.tryParse(ts);

    final storedLabel = (map['label'] as String?)?.trim() ?? '';
    return FollowUpAppointment(
      id: (map['id'] as String?) ?? '',
      date: date ?? DateTime.now(),
      // Older AI summaries accidentally saved the first discussion topic as
      // the appointment label. Normalize only those exact legacy topic values;
      // user-entered clinic or department labels remain untouched.
      label: _legacyDiscussionTopicAppointmentLabels.contains(storedLabel)
          ? '回診'
          : storedLabel,
      note: map['note'] as String?,
    );
  }

  /// 距離今天還有幾天（負數表示已逾期）
  int get daysUntil {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }
}

/// 回診前後持續整理的工作區內容。
class FollowUpWorkspace {
  final String medicalInstructions;
  final List<String> discussionTopics;
  final String discussionDetails;
  final List<FollowUpDiscussionTopicInput> aiDiscussionTopics;
  final String aiDiscussionDetails;
  final String aiAdditionalNotes;
  final bool aiAllowDiaryReference;
  final DateTime? medicalInstructionsUpdatedAt;
  final DateTime? updatedAt;

  const FollowUpWorkspace({
    this.medicalInstructions = '',
    this.discussionTopics = const [],
    this.discussionDetails = '',
    this.aiDiscussionTopics = const [],
    this.aiDiscussionDetails = '',
    this.aiAdditionalNotes = '',
    this.aiAllowDiaryReference = false,
    this.medicalInstructionsUpdatedAt,
    this.updatedAt,
  });

  FollowUpWorkspace copyWith({
    String? medicalInstructions,
    List<String>? discussionTopics,
    String? discussionDetails,
    List<FollowUpDiscussionTopicInput>? aiDiscussionTopics,
    String? aiDiscussionDetails,
    String? aiAdditionalNotes,
    bool? aiAllowDiaryReference,
    DateTime? medicalInstructionsUpdatedAt,
    DateTime? updatedAt,
  }) {
    return FollowUpWorkspace(
      medicalInstructions: medicalInstructions ?? this.medicalInstructions,
      discussionTopics: discussionTopics ?? this.discussionTopics,
      discussionDetails: discussionDetails ?? this.discussionDetails,
      aiDiscussionTopics: aiDiscussionTopics ?? this.aiDiscussionTopics,
      aiDiscussionDetails: aiDiscussionDetails ?? this.aiDiscussionDetails,
      aiAdditionalNotes: aiAdditionalNotes ?? this.aiAdditionalNotes,
      aiAllowDiaryReference:
          aiAllowDiaryReference ?? this.aiAllowDiaryReference,
      medicalInstructionsUpdatedAt:
          medicalInstructionsUpdatedAt ?? this.medicalInstructionsUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'medicalInstructions': medicalInstructions,
        'discussionTopics': discussionTopics,
        'discussionDetails': discussionDetails,
        'aiDiscussionTopics':
            aiDiscussionTopics.map((topic) => topic.toJson()).toList(),
        'aiDiscussionDetails': aiDiscussionDetails,
        'aiAdditionalNotes': aiAdditionalNotes,
        'aiAllowDiaryReference': aiAllowDiaryReference,
        'medicalInstructionsUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory FollowUpWorkspace.fromMap(Map<String, dynamic> map) {
    final rawUpdatedAt = map['updatedAt'];
    final rawInstructionsUpdatedAt = map['medicalInstructionsUpdatedAt'];
    return FollowUpWorkspace(
      medicalInstructions: (map['medicalInstructions'] ?? '').toString(),
      discussionTopics: (map['discussionTopics'] as List?)
              ?.map((topic) => topic.toString())
              .where((topic) => topic.trim().isNotEmpty)
              .toList() ??
          const [],
      discussionDetails: (map['discussionDetails'] ?? '').toString(),
      aiDiscussionTopics: (map['aiDiscussionTopics'] as List?)
              ?.whereType<Map>()
              .map((raw) => raw.cast<String, dynamic>())
              .map(
                (item) => FollowUpDiscussionTopicInput(
                  type: (item['type'] ?? '').toString(),
                  label: (item['label'] ?? '').toString(),
                  selected: item['selected'] == true,
                  note: (item['note'] ?? '').toString(),
                ),
              )
              .where((topic) => topic.type.trim().isNotEmpty)
              .toList() ??
          const [],
      aiAdditionalNotes: (map['aiAdditionalNotes'] ?? '').toString(),
      aiAllowDiaryReference: map['aiAllowDiaryReference'] == true,
      aiDiscussionDetails: (map['aiDiscussionDetails'] ?? '').toString(),
      medicalInstructionsUpdatedAt: rawInstructionsUpdatedAt is Timestamp
          ? rawInstructionsUpdatedAt.toDate()
          : null,
      updatedAt: rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : null,
    );
  }
}

class FollowUpInstructionHistoryItem {
  final String id;
  final String medicalInstructions;
  final DateTime? recordedAt;
  final DateTime? archivedAt;

  const FollowUpInstructionHistoryItem({
    required this.id,
    required this.medicalInstructions,
    this.recordedAt,
    this.archivedAt,
  });

  factory FollowUpInstructionHistoryItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return FollowUpInstructionHistoryItem.fromData(
      doc.id,
      doc.data() ?? const <String, dynamic>{},
    );
  }

  factory FollowUpInstructionHistoryItem.fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawRecordedAt = data['recordedAt'];
    final rawArchivedAt = data['archivedAt'];
    return FollowUpInstructionHistoryItem(
      id: id,
      medicalInstructions: (data['medicalInstructions'] ?? '').toString(),
      recordedAt: rawRecordedAt is Timestamp ? rawRecordedAt.toDate() : null,
      archivedAt: rawArchivedAt is Timestamp ? rawArchivedAt.toDate() : null,
    );
  }
}

/// 管理使用者的「回診日期」列表（支援多科別、多醫療院所）
class FollowUpService {
  FollowUpService._();

  static final _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _workspaceRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('followUpWorkspace')
        .doc('current');
  }

  static CollectionReference<Map<String, dynamic>> _instructionHistoryRef(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('followUpInstructionHistory');
  }

  static CollectionReference<Map<String, dynamic>> _summaryHistoryRef(
    String uid,
  ) =>
      _firestore.collection('users').doc(uid).collection('followUpSummaries');

  static Future<FollowUpWorkspace> getWorkspace() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const FollowUpWorkspace();

    try {
      final doc = await _workspaceRef(uid).get();
      final data = doc.data() == null
          ? null
          : await HealthDataEncryptionService.decryptData(doc.data()!);
      return data == null
          ? const FollowUpWorkspace()
          : FollowUpWorkspace.fromMap(data);
    } catch (e) {
      debugPrint('❌ 讀取回診工作區失敗：$e');
      return const FollowUpWorkspace();
    }
  }

  static Future<void> saveMedicalInstructions(String instructions) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('儲存回診工作區前需要先登入');
    }

    final workspaceRef = _workspaceRef(uid);
    final historyRef = _instructionHistoryRef(uid).doc();
    final nextInstructions = instructions.trim();

    final current = await workspaceRef.get();
    final currentData = current.data() == null
        ? const <String, dynamic>{}
        : await HealthDataEncryptionService.decryptData(current.data()!);
    final previousInstructions =
        (currentData['medicalInstructions'] ?? '').toString().trim();

    if (previousInstructions.isNotEmpty &&
        previousInstructions != nextInstructions) {
      await HealthDataEncryptionService.setEncrypted(
        historyRef,
        {
          'medicalInstructions': previousInstructions,
          'recordedAt': currentData['medicalInstructionsUpdatedAt'] ??
              currentData['updatedAt'] ??
              FieldValue.serverTimestamp(),
          'archivedAt': FieldValue.serverTimestamp(),
        },
        merge: false,
      );
    }

    await HealthDataEncryptionService.setEncrypted(
      workspaceRef,
      {
        'medicalInstructions': nextInstructions,
        'medicalInstructionsUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<void> saveDiscussion({
    required List<String> topics,
    required String details,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('儲存回診工作區前需要先登入');
    }
    await HealthDataEncryptionService.setEncrypted(
      _workspaceRef(uid),
      {
        'discussionTopics': topics,
        'discussionDetails': details.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<void> saveAiPreparation({
    required List<FollowUpDiscussionTopicInput> discussionTopics,
    required String discussionDetails,
    required String additionalNotes,
    bool? allowDiaryReference,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再儲存回診準備。');
    final values = <String, dynamic>{
      'aiDiscussionTopics':
          discussionTopics.map((topic) => topic.toJson()).toList(),
      'aiDiscussionDetails': discussionDetails.trim(),
      'aiAdditionalNotes': additionalNotes.trim(),
      if (allowDiaryReference != null)
        'aiAllowDiaryReference': allowDiaryReference,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await HealthDataEncryptionService.setEncrypted(
      _workspaceRef(uid),
      values,
    );
  }

  static Future<void> saveAiSummary(
    FollowUpAiOutput output, {
    String additionalNotes = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再儲存 AI 回診摘要。');
    await HealthDataEncryptionService.setEncrypted(
      _workspaceRef(uid),
      {
        'latestAiSummary': output.toJson(),
        'latestAiSummaryAdditionalNotes': additionalNotes.trim(),
        'latestAiSummaryConfirmedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<FollowUpSummaryRecord> createFormalSummary({
    required FollowUpAiV1Input input,
    required FollowUpAiOutput output,
    DateTime? appointmentDate,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再儲存回診摘要。');
    final reference = _summaryHistoryRef(uid).doc();
    final now = DateTime.now();
    final duration = input.sleep['durationHours'];
    final durationMap = duration is Map
        ? Map<String, dynamic>.from(duration)
        : const <String, dynamic>{};
    final trend = durationMap['dailyTrend'] is List
        ? (durationMap['dailyTrend'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final sleepSummary = Map<String, dynamic>.from(input.sleep)
      ..remove('durationHours');
    sleepSummary['durationHours'] = Map<String, dynamic>.from(durationMap)
      ..remove('dailyTrend');
    final record = FollowUpSummaryRecord(
      id: reference.id,
      createdAt: now,
      updatedAt: now,
      confirmedAt: now,
      // A formal summary may reference an appointment only when the user
      // explicitly selected one in the preparation form. The aggregator's
      // currentAppointmentDate is used solely to calculate the period.
      appointmentDate: appointmentDate,
      periodStart: input.statistics.periodStart,
      periodEnd: input.statistics.periodEnd,
      validRecordDays: input.statistics.validRecordDays,
      selectedTopics: input.discussionTopics
          .where((topic) => topic.selected)
          .map((topic) => {'type': topic.type, 'label': topic.label})
          .toList(),
      discussionDetails: input.discussionDetails,
      additionalNotes: input.additionalNotes,
      aiOutput: output,
      sleepSummary: sleepSummary,
      sleepTrend: trend,
      medicationTimeline: input.medicationTimeline,
      highFrequencySymptoms: input.highFrequencySymptoms,
      bodyMeasurements: input.bodyMeasurements,
    );
    final values = record.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await HealthDataEncryptionService.setEncrypted(
      reference,
      values,
      merge: false,
    );
    return record;
  }

  static Future<List<FollowUpSummaryRecord>> listFormalSummaries() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    final documents = await HealthDataEncryptionService.getEncrypted(
      _summaryHistoryRef(uid).orderBy('createdAt', descending: true),
    );
    return documents
        .map((doc) => FollowUpSummaryRecord.fromMap(doc.id, doc.data))
        .toList();
  }

  static Future<FollowUpSummaryRecord?> getFormalSummary(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snapshot = await _summaryHistoryRef(uid).doc(id).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final data =
        await HealthDataEncryptionService.decryptData(snapshot.data()!);
    return FollowUpSummaryRecord.fromMap(snapshot.id, data);
  }

  static Future<FollowUpSummaryRecord> updateFormalSummary(
    FollowUpSummaryRecord record,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再更新回診摘要。');
    final updated = record.copyWith(updatedAt: DateTime.now());
    final values = updated.toMap()
      ..remove('createdAt')
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await HealthDataEncryptionService.setEncrypted(
      _summaryHistoryRef(uid).doc(record.id),
      values,
    );
    return updated;
  }

  static Future<void> deleteFormalSummary(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('請先登入後再刪除回診摘要。');
    await _summaryHistoryRef(uid).doc(id).delete();
  }

  static Future<List<FollowUpInstructionHistoryItem>>
      getInstructionHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];

    try {
      final documents = await HealthDataEncryptionService.getEncrypted(
        _instructionHistoryRef(uid).orderBy('archivedAt', descending: true),
      );
      return documents
          .map(
            (doc) => FollowUpInstructionHistoryItem.fromData(doc.id, doc.data),
          )
          .where((item) => item.medicalInstructions.trim().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('❌ 讀取歷次回診醫囑失敗：$e');
      return const [];
    }
  }

  /// 取得所有回診日期（依日期排序）
  static Future<List<FollowUpAppointment>> getAppointments() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      final userRef = _firestore.collection('users').doc(uid);
      final doc = await userRef.get();
      final healthDoc =
          await userRef.collection('healthProfile').doc('current').get();
      final healthData = healthDoc.data() == null
          ? const <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(healthDoc.data()!);

      final raw = healthData['followUpAppointments'] ??
          doc.data()?['followUpAppointments'];
      if (raw is List) {
        final list = raw
            .map((e) =>
                FollowUpAppointment.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) => a.date.compareTo(b.date));
        return list;
      }

      // 向後相容：舊的單一日期格式
      final oldTs =
          healthData['nextFollowUpDate'] ?? doc.data()?['nextFollowUpDate'];
      if (oldTs is Timestamp) {
        return [
          FollowUpAppointment(
            id: 'legacy',
            date: oldTs.toDate(),
            label: '回診',
          ),
        ];
      }

      return [];
    } catch (e) {
      debugPrint('❌ 讀取回診日期失敗：$e');
      return [];
    }
  }

  /// 新增一筆回診
  static Future<void> addAppointment(FollowUpAppointment appointment) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final appointments = await getAppointments();
    final alreadyExists = appointments.any((existing) =>
        _sameDay(existing.date, appointment.date) &&
        existing.label.trim() == appointment.label.trim() &&
        (existing.note ?? '').trim() == (appointment.note ?? '').trim());
    if (alreadyExists) return;
    appointments.add(appointment);
    await _saveAppointments(uid, appointments);
  }

  /// 更新一筆回診
  static Future<void> updateAppointment(FollowUpAppointment updated) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final appointments = await getAppointments();
    final index = appointments.indexWhere((a) => a.id == updated.id);
    if (index == -1) return;

    appointments[index] = updated;
    await _saveAppointments(uid, appointments);
  }

  /// 刪除一筆回診
  static Future<void> deleteAppointment(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final appointments = await getAppointments();
    appointments.removeWhere((a) => a.id == id);
    await _saveAppointments(uid, appointments);
  }

  static Future<void> _saveAppointments(
      String uid, List<FollowUpAppointment> appointments) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await HealthDataEncryptionService.setEncrypted(
        userRef.collection('healthProfile').doc('current'),
        {
          'followUpAppointments': appointments.map((a) => a.toMap()).toList(),
          'followUpAppointmentsUpdatedAt': FieldValue.serverTimestamp(),
        },
      );
      await userRef.set({
        'followUpAppointments': FieldValue.delete(),
        'followUpAppointmentsUpdatedAt': FieldValue.delete(),
        'nextFollowUpDate': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ 儲存回診日期失敗：$e');
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
