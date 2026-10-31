import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/health_event.dart';
import 'demo_sleep_envelope.dart';
import 'demo_sleep_share_client.dart';

/// Only constructed synthetic HealthEvent models; never reads a repository.
class DemoHealthEventShareClient {
  DemoHealthEventShareClient(this.auth, this.functions) {
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
        await _call('demoHealthEventContext', {'clinicId': clinicId});
    final epoch = context['epoch'] as int;
    final records = <Map<String, dynamic>>[];
    for (var day = 1; day <= 2; day++) {
      final id = DemoSleepEnvelope.documentId();
      final event = HealthEvent(
        id: id,
        timestamp: DateTime.utc(2026, 10, day, 12),
        symptoms: [HealthEventSymptom(name: '合成症狀$day', severity: day + 1)],
        emotions: const [HealthEventEmotion(name: '合成情緒', intensity: 3)],
        stateChanges: const {'energy_change': 3},
        timePrecision: null,
        context: '合成測試情境',
        note: 'HealthEvent 合成驗收紀錄，非真實醫療資料',
      );
      final payload = {
        'timestamp': event.timestamp.toUtc().toIso8601String(),
        'symptoms': event.symptoms.map((x) => x.toMap()).toList(),
        'emotions': event.emotions.map((x) => x.toMap()).toList(),
        'stateChanges': event.stateChanges,
        'timePrecision': event.timePrecision,
        'context': event.context,
        'note': event.note,
        'createdAt': null,
        'updatedAt': null,
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
          type: 'healthEvents',
        )
      });
    }
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    await _call('demoPublishHealthEvents', {
      'clinicId': clinicId,
      'expectedEpoch': epoch,
      'consentVersion': 1,
      'records': records
    });
  }

  Future<void> revoke(String clinicId) async {
    await _call('demoRevokeHealthEvents', {'clinicId': clinicId});
  }
}
