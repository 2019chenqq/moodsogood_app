import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/daily_check_in.dart';
import 'demo_sleep_envelope.dart';
import 'demo_sleep_share_client.dart';

/// Only constructed synthetic CheckIn models; never reads a repository.
class DemoCheckInShareClient {
  DemoCheckInShareClient(this.auth, this.functions) {
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
    final context = await _call('demoCheckInContext', {'clinicId': clinicId});
    final epoch = context['epoch'] as int;
    final records = <Map<String, dynamic>>[];
    for (var day = 1; day <= 2; day++) {
      final id = DemoSleepEnvelope.documentId();
      final event = DailyCheckIn(
        date: DateTime.utc(2026, 10, day),
        overallMood: day + 2,
        healthStatus: day + 1,
        noSpecialEvent: day == 1,
      );
      final payload = {
        'date': event.date.toUtc().toIso8601String(),
        'overallMood': event.overallMood,
        'healthStatus': event.healthStatus,
        'noSpecialEvent': event.noSpecialEvent,
        'createdAt': event.createdAt?.toUtc().toIso8601String(),
        'updatedAt': event.updatedAt?.toUtc().toIso8601String(),
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
          type: 'checkIns',
        )
      });
    }
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    await _call('demoPublishCheckIns', {
      'clinicId': clinicId,
      'expectedEpoch': epoch,
      'consentVersion': 1,
      'records': records
    });
  }

  Future<void> revoke(String clinicId) async {
    await _call('demoRevokeCheckIns', {'clinicId': clinicId});
  }
}
