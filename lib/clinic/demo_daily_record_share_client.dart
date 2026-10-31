import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'demo_sleep_envelope.dart';
import 'demo_sleep_share_client.dart';

/// Only constructed new synthetic writer maps; never reads legacy records; never reads a repository.
class DemoDailyRecordShareClient {
  DemoDailyRecordShareClient(this.auth, this.functions) {
    DemoSleepShareClient(auth, functions); // Same project/app isolation guard.
  }
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (auth.currentUser == null || auth.currentUser!.isAnonymous) {
      throw StateError('請先登入測試患者');
    }
    final result = await functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> shareSynthetic(String clinicId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('請先登入');
    final context =
        await _call('demoDailyRecordContext', {'clinicId': clinicId});
    final epoch = context['epoch'] as int;
    final records = <Map<String, dynamic>>[];
    for (var day = 1; day <= 2; day++) {
      final id = DemoSleepEnvelope.documentId();
      final date = DateTime.utc(2026, 10, day).toIso8601String();
      final payload = <String, dynamic>{
        'date': date,
        'emotions': day == 1
            ? {'合成情緒': 3}
            : [
                {'name': '合成情緒', 'value': 4}
              ],
        'symptoms': ['合成每日症狀'],
        'bodySymptoms': ['合成每日症狀'],
        'stateChanges': {'energy_change': 3},
        'symptomSectionCompleted': true,
        'emotionSectionCompleted': true,
        'stateSectionCompleted': true,
        'overallMood': day == 1 ? 3 : 4,
        'moodScale': 5,
        'updatedAt': date,
        if (day == 1) ...{
          'createdAt': date,
          'savedAt': date,
          'isPeriod': false,
          'periodStartId': null,
          'periodCycleLength': 28,
          'periodNextExpectedStart': null,
          'periodArrivalDeltaDays': null,
          'dailyActivities': null,
          'medicines': null,
          'periodData': {
            'isPeriod': false,
            'periodStartId': null,
            'periodEndId': null,
            'cycleLength': 28,
            'nextExpectedStart': null,
            'arrivalDeltaDays': null,
          },
        } else ...{
          'bodyMeasurement': {
            'weightKg': 60.0,
            'bodyFatPercent': 20.0,
            'waistCm': 75.0,
            'measuredAt': date,
            'measurementTiming': 'afterWaking',
            'customMeasurementTime': null,
          },
          'sleep': {
            'sleepTime': '23:00',
            'wakeTime': '07:00',
            'finalWakeTime': '06:50',
            'quality': 4,
            'midWakeList': '合成夜醒文字',
            'flags': ['synthetic'],
            'naps': <dynamic>[]
          },
        },
      };
      records.add({
        'id': id,
        'envelope': DemoSleepEnvelope.encrypt(
          uid: uid,
          clinicId: clinicId,
          documentId: id,
          epoch: epoch + 1,
          keyVersion: context['keyVersion'] as String,
          publicKeyPem: context['publicKeyPem'] as String,
          sleep: payload,
          type: 'dailyRecords',
        )
      });
    }
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    await _call('demoPublishDailyRecords', {
      'clinicId': clinicId,
      'expectedEpoch': epoch,
      'consentVersion': 1,
      'records': records
    });
  }

  Future<void> revoke(String clinicId) async {
    await _call('demoRevokeDailyRecords', {'clinicId': clinicId});
  }
}
