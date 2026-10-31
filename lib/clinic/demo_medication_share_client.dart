import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'demo_sleep_envelope.dart';
import 'demo_sleep_share_client.dart';

/// Only constructed synthetic medication maps; never reads a repository.
class DemoMedicationShareClient {
  DemoMedicationShareClient(this.auth, this.functions) {
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
        await _call('demoMedicationContext', {'clinicId': clinicId});
    final epoch = context['epoch'] as int;
    final records = <Map<String, dynamic>>[];
    for (final variant in ['tablet', 'prn', 'injection']) {
      final id = DemoSleepEnvelope.documentId();
      final injection = variant == 'injection';
      final payload = <String, dynamic>{
        'name': '合成測試藥物-$variant',
        'nameEn': 'Synthetic-$variant',
        'dose': injection ? 50 : 10,
        'dosePerUnit': injection ? 50 : 10,
        'pillCount': 1,
        'concentrationMg': null,
        'concentrationMl': null,
        'intakeMl': null,
        'unit': 'mg',
        'type': injection ? 'injection' : 'tablet',
        'drugForm': injection ? '合成注射劑' : '合成錠劑',
        'compoundType': '合成單方',
        'drugConcentration': '',
        'packageAmount': '1',
        'packageUnit': injection ? '支' : '錠',
        'ingredientLines': ['合成測試成分'],
        'intervalDays': injection ? 28 : null,
        'scheduleType': 'daily',
        'scheduleIntervalDays': null,
        'scheduleAnchorDate': null,
        'weekdays': <int>[],
        'times': injection ? <String>[] : [variant == 'prn' ? '需要時' : '早上'],
        'purposes': ['合成測試用途'],
        'note': 'Medication 合成驗收紀錄，非真實處方',
        'startDate': DateTime.utc(2026, 10, 1).toIso8601String(),
        'isActive': true,
        'bodySymptoms': <String>[],
        'purposeOther': null,
        'createdAt': DateTime.utc(2026, 10, 1).toIso8601String(),
        'updatedAt': DateTime.utc(2026, 10, 1).toIso8601String(),
        'lastChangeAt': null,
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
          type: 'medications',
        )
      });
    }
    if (auth.currentUser?.uid != uid) throw StateError('登入狀態已改變');
    await _call('demoPublishMedications', {
      'clinicId': clinicId,
      'expectedEpoch': epoch,
      'consentVersion': 1,
      'records': records
    });
  }

  Future<void> revoke(String clinicId) async {
    await _call('demoRevokeMedications', {'clinicId': clinicId});
  }
}
