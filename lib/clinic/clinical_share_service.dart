import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sleep_record.dart';
import '../daily/daily_check_in_service.dart';
import '../daily/health_event_repository.dart';
import '../daily/sleep_record_service.dart';
import '../meds/medication_local_db.dart';
import '../utils/health_data_encryption_service.dart';

/// 將 App 已解密的睡眠資料，整理成「醫療端可讀」的分享資料。
///
/// 建議放在與 sleep_record_service.dart 相同的資料夾。
///
/// Firestore 路徑：
/// clinicalShares/{uid}/clinics/{clinicId}/sleepRecords/{yyyy-MM-dd}
///
/// 注意：
/// 1. 這裡寫入的是「分享用明文資料」，不是原始加密 health data。
/// 2. 只應在使用者明確同意分享後呼叫。
/// 3. 正式上線前，必須搭配 Firestore Security Rules 限制可讀取的院所/醫師。
class ClinicalShareService {
  ClinicalShareService({
  FirebaseFirestore? firestore,
  FirebaseAuth? auth,
  SleepRecordService? sleepRecordService,
  MedicationLocalDB? medicationDb,
  HealthEventRepository? healthEventRepository,
  DailyCheckInService? dailyCheckInService,
})  : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance,
      _sleepRecordService = sleepRecordService ?? SleepRecordService(),
      _medicationDb = medicationDb ?? MedicationLocalDB(),
      _healthEventRepository = healthEventRepository ?? HealthEventRepository(),
      _dailyCheckInService = dailyCheckInService ?? DailyCheckInService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SleepRecordService _sleepRecordService;
  final MedicationLocalDB _medicationDb;
  final HealthEventRepository _healthEventRepository;
  final DailyCheckInService _dailyCheckInService;

  static const int shareVersion = 1;

  Future<int> syncHealthEvents({required String clinicId}) async {
    if (clinicId.trim().isEmpty) {
      throw ArgumentError('clinicId 不可為空');
    }
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入，無法分享快速紀錄。');
    }

    final events = await _healthEventRepository.getAll(userId: user.uid);
    final collection = _healthEventShareCollection(
      uid: user.uid,
      clinicId: clinicId,
    );
    for (final event in events) {
      await collection.doc(event.id).set({
        'timestamp': Timestamp.fromDate(event.timestamp),
        'emotions': event.emotions.map((item) => item.toMap()).toList(),
        'symptoms': event.symptoms.map((item) => item.toMap()).toList(),
        'stateChanges': event.stateChanges,
        'context': event.context,
        'note': event.note,
        'updatedAt': event.updatedAt == null
            ? null
            : Timestamp.fromDate(event.updatedAt!),
        'source': 'innera_app',
        'shareVersion': shareVersion,
      });
    }
    await _clinicShareReference(uid: user.uid, clinicId: clinicId).set({
      'healthEventSharingEnabled': true,
      'lastHealthEventSyncAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return events.length;
  }

  Future<int> syncDailyCheckIns({required String clinicId}) async {
    if (clinicId.trim().isEmpty) {
      throw ArgumentError('clinicId 不可為空');
    }
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入，無法分享每日 Check-in。');
    }

    final checkIns = await _dailyCheckInService.getAll();
    final collection = _dailyCheckInShareCollection(
      uid: user.uid,
      clinicId: clinicId,
    );
    for (final checkIn in checkIns) {
      await collection.doc(DailyCheckInService.dateId(checkIn.date)).set({
        'date': Timestamp.fromDate(checkIn.date),
        'overallMood': checkIn.overallMood,
        'healthStatus': checkIn.healthStatus,
        'noSpecialEvent': checkIn.noSpecialEvent,
        'updatedAt': checkIn.updatedAt == null
            ? null
            : Timestamp.fromDate(checkIn.updatedAt!),
        'source': 'innera_app',
        'shareVersion': shareVersion,
      });
    }
    await _clinicShareReference(uid: user.uid, clinicId: clinicId).set({
      'dailyCheckInSharingEnabled': true,
      'lastDailyCheckInSyncAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return checkIns.length;
  }

  /// 將已解密的每日紀錄同步到醫療分享區。
  Future<int> syncDailyRecords({
    required String clinicId,
  }) async {
    if (clinicId.trim().isEmpty) {
      throw ArgumentError('clinicId 不可為空');
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入，無法分享每日紀錄。');
    }

    final uid = user.uid;
    final records = await HealthDataEncryptionService.getEncrypted(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('dailyRecords'),
    );
    final collection = _dailyRecordShareCollection(
      uid: uid,
      clinicId: clinicId,
    );

    for (final record in records) {
      await collection.doc(record.id).set(
            _toClinicalDailyRecordMap(record.data),
          );
    }

    await _clinicShareReference(
      uid: uid,
      clinicId: clinicId,
    ).set(
      {
        'dailyRecordSharingEnabled': true,
        'dailyRecordShareVersion': shareVersion,
        'lastDailyRecordSyncAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return records.length;
  }

  /// 同步最近 [days] 天有資料的睡眠紀錄到醫療分享區。
  ///
  /// 回傳實際成功寫入的紀錄筆數。
  Future<int> syncRecentSleepRecords({
    required String clinicId,
    int days = 30,
  }) async {
    if (clinicId.trim().isEmpty) {
      throw ArgumentError('clinicId 不可為空');
    }

    if (days <= 0) {
      throw ArgumentError('days 必須大於 0');
    }

    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入，無法分享睡眠資料。');
    }

    final uid = user.uid;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int syncedCount = 0;

    for (int offset = 0; offset < days; offset++) {
      final date = today.subtract(Duration(days: offset));

      final record = await _sleepRecordService.get(
        userId: uid,
        date: date,
      );

      if (record == null || !record.hasData) {
        continue;
      }

      await _sleepShareReference(
        uid: uid,
        clinicId: clinicId,
        date: record.date,
      ).set(
        _toClinicalSleepMap(
          uid: uid,
          clinicId: clinicId,
          record: record,
        ),
        SetOptions(merge: true),
      );

      syncedCount++;
    }

    await _clinicShareReference(
      uid: uid,
      clinicId: clinicId,
    ).set(
      {
        'uid': uid,
        'clinicId': clinicId,
        'sleepSharingEnabled': true,
        'sleepShareVersion': shareVersion,
        'lastSleepSyncAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return syncedCount;
  }

Future<int> syncMedications({
  required String clinicId,
}) async {
  if (clinicId.trim().isEmpty) {
    throw ArgumentError('clinicId 不可為空');
  }

  final user = _auth.currentUser;

  if (user == null || user.isAnonymous) {
    throw StateError('使用者尚未登入，無法分享藥物資料。');
  }

  final uid = user.uid;

  // 這裡拿到的已經是 App 解密後的資料
  final medications =
      await _medicationDb.getMedications(uid);

  // 第一版醫療端只分享「目前使用中」的藥物
  final activeMedications = medications
      .where((med) => med['isActive'] != false)
      .toList();

  final collection = _medicationShareCollection(
    uid: uid,
    clinicId: clinicId,
  );

  // 先取得原本分享出去的藥物。
  // 避免 App 停藥之後，醫療端還殘留舊藥。
  final existing = await collection.get();

  final batch = _firestore.batch();

  for (final doc in existing.docs) {
    batch.delete(doc.reference);
  }

  for (final med in activeMedications) {
    final medicationId =
        med['id']?.toString().trim();

    if (medicationId == null ||
        medicationId.isEmpty) {
      continue;
    }

    batch.set(
      collection.doc(medicationId),
      _toClinicalMedicationMap(
        uid: uid,
        clinicId: clinicId,
        medication: med,
      ),
    );
  }

  batch.set(
    _clinicShareReference(
      uid: uid,
      clinicId: clinicId,
    ),
    {
      'medicationSharingEnabled': true,
      'medicationShareVersion': shareVersion,
      'lastMedicationSyncAt':
          FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  await batch.commit();

  return activeMedications.length;
}
  /// 使用者停止分享睡眠資料時呼叫。
  ///
  /// 會移除該院所目前已分享的 sleepRecords，
  /// 並把 sleepSharingEnabled 設成 false。
  Future<void> stopSharingSleep({
    required String clinicId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入。');
    }

    final uid = user.uid;

    final sleepCollection = _sleepShareCollection(
      uid: uid,
      clinicId: clinicId,
    );

    final snapshot = await sleepCollection.get();

    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    batch.set(
      _clinicShareReference(
        uid: uid,
        clinicId: clinicId,
      ),
      {
        'sleepSharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// 給 App 顯示目前是否有開啟睡眠分享。
  Future<bool> isSleepSharingEnabled({
    required String clinicId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }

    final snapshot = await _clinicShareReference(
      uid: user.uid,
      clinicId: clinicId,
    ).get();

    return snapshot.data()?['sleepSharingEnabled'] == true;
  }

  Future<bool> isDailyRecordSharingEnabled({
    required String clinicId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }

    final snapshot = await _clinicShareReference(
      uid: user.uid,
      clinicId: clinicId,
    ).get();

    return snapshot.data()?['dailyRecordSharingEnabled'] == true;
  }

  Future<bool> isHealthEventSharingEnabled({required String clinicId}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    final snapshot = await _clinicShareReference(
      uid: user.uid,
      clinicId: clinicId,
    ).get();
    return snapshot.data()?['healthEventSharingEnabled'] == true;
  }

  Future<bool> isDailyCheckInSharingEnabled({required String clinicId}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return false;
    final snapshot = await _clinicShareReference(
      uid: user.uid,
      clinicId: clinicId,
    ).get();
    return snapshot.data()?['dailyCheckInSharingEnabled'] == true;
  }

  Future<void> stopSharingHealthEvents({required String clinicId}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入。');
    }
    final collection = _healthEventShareCollection(
      uid: user.uid,
      clinicId: clinicId,
    );
    final snapshot = await collection.get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.set(
      _clinicShareReference(uid: user.uid, clinicId: clinicId),
      {
        'healthEventSharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> stopSharingDailyCheckIns({required String clinicId}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入。');
    }
    final collection = _dailyCheckInShareCollection(
      uid: user.uid,
      clinicId: clinicId,
    );
    final snapshot = await collection.get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.set(
      _clinicShareReference(uid: user.uid, clinicId: clinicId),
      {
        'dailyCheckInSharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> stopSharingDailyRecords({
    required String clinicId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入。');
    }

    final uid = user.uid;
    final collection = _dailyRecordShareCollection(
      uid: uid,
      clinicId: clinicId,
    );
    final snapshot = await collection.get();
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    batch.set(
      _clinicShareReference(uid: uid, clinicId: clinicId),
      {
        'dailyRecordSharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

Future<bool> isMedicationSharingEnabled({
  required String clinicId,
}) async {
  final user = _auth.currentUser;

  if (user == null || user.isAnonymous) {
    return false;
  }

  final snapshot =
      await _clinicShareReference(
    uid: user.uid,
    clinicId: clinicId,
  ).get();

  return snapshot.data()?[
          'medicationSharingEnabled'] ==
      true;
}

  /// 停止分享用藥，並移除已分享給該院所的用藥資料。
  Future<void> stopSharingMedications({
    required String clinicId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('使用者尚未登入。');
    }

    final uid = user.uid;
    final collection = _medicationShareCollection(
      uid: uid,
      clinicId: clinicId,
    );
    final snapshot = await collection.get();
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    batch.set(
      _clinicShareReference(uid: uid, clinicId: clinicId),
      {
        'medicationSharingEnabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Map<String, dynamic> _toClinicalSleepMap({
    required String uid,
    required String clinicId,
    required SleepRecord record,
  }) {
    return {
      'uid': uid,
      'clinicId': clinicId,
      'date': Timestamp.fromDate(
        DateTime(
          record.date.year,
          record.date.month,
          record.date.day,
        ),
      ),
      'bedTime': _formatTime(record.bedTime),
      'sleepStart': _formatTime(record.sleepStart),
      'wakeTime': _formatTime(record.wakeTime),
      'activityWakeTime': _formatTime(record.activityWakeTime),
      'durationMinutes': record.durationMinutes,
      'quality': record.quality,
      'sleepConditions': List<String>.from(record.sleepConditions),
      'source': 'innera_app',
      'shareVersion': shareVersion,
      'sharedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String? _formatTime(TimeOfDay? value) {
    if (value == null) return null;

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  DocumentReference<Map<String, dynamic>> _clinicShareReference({
    required String uid,
    required String clinicId,
  }) {
    return _firestore
        .collection('clinicalShares')
        .doc(uid)
        .collection('clinics')
        .doc(clinicId);
  }

  CollectionReference<Map<String, dynamic>> _sleepShareCollection({
    required String uid,
    required String clinicId,
  }) {
    return _clinicShareReference(
      uid: uid,
      clinicId: clinicId,
    ).collection('sleepRecords');
  }

  CollectionReference<Map<String, dynamic>> _dailyRecordShareCollection({
    required String uid,
    required String clinicId,
  }) {
    return _clinicShareReference(
      uid: uid,
      clinicId: clinicId,
    ).collection('dailyRecords');
  }

  CollectionReference<Map<String, dynamic>> _healthEventShareCollection({
    required String uid,
    required String clinicId,
  }) {
    return _clinicShareReference(uid: uid, clinicId: clinicId)
        .collection('healthEvents');
  }

  CollectionReference<Map<String, dynamic>> _dailyCheckInShareCollection({
    required String uid,
    required String clinicId,
  }) {
    return _clinicShareReference(uid: uid, clinicId: clinicId)
        .collection('dailyCheckIns');
  }

  Map<String, dynamic> _toClinicalDailyRecordMap(
    Map<String, dynamic> record,
  ) {
    final symptoms = record['symptoms'] ?? record['bodySymptoms'];
    return {
      'date': record['date'],
      'overallMood': record['overallMood'],
      'moodScale': record['moodScale'],
      'emotions': record['emotions'],
      'symptoms': symptoms is Iterable
          ? symptoms.map((item) => item.toString()).toList()
          : const <String>[],
      'stateChanges': record['stateChanges'],
      'symptomSectionCompleted': record['symptomSectionCompleted'],
      'emotionSectionCompleted': record['emotionSectionCompleted'],
      'stateSectionCompleted': record['stateSectionCompleted'],
      'updatedAt': record['updatedAt'],
    };
  }

CollectionReference<Map<String, dynamic>>
    _medicationShareCollection({
  required String uid,
  required String clinicId,
}) {
  return _clinicShareReference(
    uid: uid,
    clinicId: clinicId,
  ).collection('medications');
}

  DocumentReference<Map<String, dynamic>> _sleepShareReference({
    required String uid,
    required String clinicId,
    required DateTime date,
  }) {
    return _sleepShareCollection(
      uid: uid,
      clinicId: clinicId,
    ).doc(SleepRecordService.dateId(date));
  }
  Map<String, dynamic> _toClinicalMedicationMap({
  required String uid,
  required String clinicId,
  required Map<String, dynamic> medication,
}) {
  String firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  final times = medication['times'] is Iterable
      ? (medication['times'] as Iterable)
          .map((item) => item.toString())
          .toList()
      : <String>[];

  final name = firstNonEmpty([
    medication['name'],
    medication['medicationName'],
    medication['drugName'],
    medication['brandName'],
  ]);

  return {
    'uid': uid,
    'clinicId': clinicId,
    'medicationId':
        medication['id']?.toString() ?? '',

    'name': name,
    'nameEn': medication['nameEn']?.toString().trim() ?? '',

    'dose': medication['dose'],
    'dosePerUnit': medication['dosePerUnit'],
    'pillCount': medication['pillCount'],
    'unit': medication['unit']?.toString() ?? '',

    'times': times,

    'isActive':
        medication['isActive'] != false,

    'startDate': medication['startDate'],
    'lastChangeAt':
        medication['lastChangeAt'],

    'source': 'innera_app',
    'shareVersion': shareVersion,

    'sharedAt':
        FieldValue.serverTimestamp(),
    'updatedAt':
        FieldValue.serverTimestamp(),
  };
}
}
