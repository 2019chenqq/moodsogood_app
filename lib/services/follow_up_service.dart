import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

    return FollowUpAppointment(
      id: (map['id'] as String?) ?? '',
      date: date ?? DateTime.now(),
      label: (map['label'] as String?) ?? '',
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
  final DateTime? medicalInstructionsUpdatedAt;
  final DateTime? updatedAt;

  const FollowUpWorkspace({
    this.medicalInstructions = '',
    this.discussionTopics = const [],
    this.discussionDetails = '',
    this.medicalInstructionsUpdatedAt,
    this.updatedAt,
  });

  FollowUpWorkspace copyWith({
    String? medicalInstructions,
    List<String>? discussionTopics,
    String? discussionDetails,
    DateTime? medicalInstructionsUpdatedAt,
    DateTime? updatedAt,
  }) {
    return FollowUpWorkspace(
      medicalInstructions: medicalInstructions ?? this.medicalInstructions,
      discussionTopics: discussionTopics ?? this.discussionTopics,
      discussionDetails: discussionDetails ?? this.discussionDetails,
      medicalInstructionsUpdatedAt:
          medicalInstructionsUpdatedAt ?? this.medicalInstructionsUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'medicalInstructions': medicalInstructions,
        'discussionTopics': discussionTopics,
        'discussionDetails': discussionDetails,
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
    final data = doc.data() ?? const <String, dynamic>{};
    final rawRecordedAt = data['recordedAt'];
    final rawArchivedAt = data['archivedAt'];
    return FollowUpInstructionHistoryItem(
      id: doc.id,
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

  static Future<FollowUpWorkspace> getWorkspace() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const FollowUpWorkspace();

    try {
      final doc = await _workspaceRef(uid).get();
      final data = doc.data();
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

    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(workspaceRef);
      final currentData = current.data() ?? const <String, dynamic>{};
      final previousInstructions =
          (currentData['medicalInstructions'] ?? '').toString().trim();

      if (previousInstructions.isNotEmpty &&
          previousInstructions != nextInstructions) {
        transaction.set(historyRef, {
          'medicalInstructions': previousInstructions,
          'recordedAt': currentData['medicalInstructionsUpdatedAt'] ??
              currentData['updatedAt'] ??
              FieldValue.serverTimestamp(),
          'archivedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(
        workspaceRef,
        {
          'medicalInstructions': nextInstructions,
          'medicalInstructionsUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> saveDiscussion({
    required List<String> topics,
    required String details,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('儲存回診工作區前需要先登入');
    }
    await _workspaceRef(uid).set(
      {
        'discussionTopics': topics,
        'discussionDetails': details.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<List<FollowUpInstructionHistoryItem>>
      getInstructionHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];

    try {
      final snapshot = await _instructionHistoryRef(uid)
          .orderBy('archivedAt', descending: true)
          .get();
      return snapshot.docs
          .map(FollowUpInstructionHistoryItem.fromFirestore)
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
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return [];

      final raw = doc.data()?['followUpAppointments'];
      if (raw is List) {
        final list = raw
            .map((e) =>
                FollowUpAppointment.fromMap(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) => a.date.compareTo(b.date));
        return list;
      }

      // 向後相容：舊的單一日期格式
      final oldTs = doc.data()?['nextFollowUpDate'];
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
      await _firestore.collection('users').doc(uid).set(
        {
          'followUpAppointments': appointments.map((a) => a.toMap()).toList(),
          'followUpAppointmentsUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('❌ 儲存回診日期失敗：$e');
    }
  }
}
