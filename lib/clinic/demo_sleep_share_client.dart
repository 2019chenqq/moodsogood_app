import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'demo_sleep_envelope.dart';

class DemoSleepShareClient {
  DemoSleepShareClient(this.auth, this.functions) {
    if (auth.app.options.projectId != DemoSleepEnvelope.project ||
        functions.app.options.projectId != DemoSleepEnvelope.project ||
        functions.app.name != auth.app.name) {
      throw StateError('僅限隔離 demo 專案');
    }
  }
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    if (auth.currentUser == null || auth.currentUser!.isAnonymous) {
      throw StateError('請先登入測試患者帳號');
    }
    final result = await functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Deliberately accepts no real records in phase one.
  Future<void> shareSyntheticSleep(String clinicId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('請先登入');
    final context = await _call('demoSleepContext', {'clinicId': clinicId});
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    final epoch = context['epoch'] as int;
    final records = <Map<String, dynamic>>[];
    for (var day = 1; day <= 3; day++) {
      final id = DemoSleepEnvelope.documentId();
      records.add({
        'id': id,
        'envelope': DemoSleepEnvelope.encrypt(
          uid: uid,
          clinicId: clinicId,
          documentId: id,
          epoch: epoch + 1,
          keyVersion: context['keyVersion'] as String,
          publicKeyPem: context['publicKeyPem'] as String,
          sleep: {
            'date': '2026-10-0$day',
            'bedTime': '22:30',
            'sleepStart': '23:00',
            'wakeTime': '07:00',
            'activityWakeTime': '07:15',
            'durationMinutes': 480,
            'quality': 4,
            'sleepConditions': ['合成測試紀錄'],
          },
        ),
      });
    }
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    await _call('demoPublishSleep', {
      'clinicId': clinicId,
      'expectedEpoch': epoch,
      'consentVersion': 1,
      'records': records,
    });
  }

  Future<void> revoke(String clinicId) async {
    await _call('demoRevokeSleep', {'clinicId': clinicId});
  }
}
