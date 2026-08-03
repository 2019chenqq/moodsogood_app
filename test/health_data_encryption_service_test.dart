import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/health_data_encryption_service.dart';

void main() {
  final key = encrypt_lib.Key(
    Uint8List.fromList(List<int>.generate(32, (index) => index)),
  );

  test('keeps only query metadata outside the encrypted payload', () {
    final date = Timestamp.fromDate(DateTime.utc(2026, 7, 29));
    final encrypted = HealthDataEncryptionService.encryptForTesting(
      {
        'date': date,
        'emotions': [
          {'name': 'anxious', 'value': 4},
        ],
        'sleep': {'note': 'private sleep note'},
        'stateChanges': {
          'energy_change': 2,
          'appetite_change': 5,
        },
        'bodyMeasurement': {
          'weightKg': 75.5,
          'bodyFatPercent': 40.0,
          'measurementTiming': 'beforeSleep',
        },
      },
      key: key,
      collectionName: 'dailyRecords',
    );

    expect(encrypted['date'], date);
    expect(encrypted.containsKey('emotions'), isFalse);
    expect(encrypted.containsKey('sleep'), isFalse);
    expect(encrypted.containsKey('stateChanges'), isFalse);
    expect(encrypted.containsKey('bodyMeasurement'), isFalse);
    expect(encrypted['healthDataEncrypted'], isTrue);
    expect(
      encrypted['encryptedHealthData'],
      isNot(contains('private sleep note')),
    );
    expect(
      encrypted['encryptedHealthData'],
      isNot(contains('energy_change')),
    );
    expect(
      encrypted['encryptedHealthData'],
      isNot(contains('75.5')),
    );

    final decrypted = HealthDataEncryptionService.decryptForTesting(
      encrypted,
      key: key,
    );
    expect(decrypted['stateChanges'], {
      'energy_change': 2,
      'appetite_change': 5,
    });
    expect(
      (decrypted['bodyMeasurement'] as Map)['weightKg'],
      75.5,
    );
  });

  test('round trips nested Firestore timestamps and health values', () {
    final takenAt = Timestamp.fromDate(DateTime.utc(2026, 7, 29, 8, 30));
    final original = <String, dynamic>{
      'date': Timestamp.fromDate(DateTime.utc(2026, 7, 29)),
      'statuses': {'med-a|morning': 'taken'},
      'takenAt': {
        'med-a|morning': takenAt,
      },
      'actualAmount': {'med-a|morning': 0.5},
    };

    final encrypted = HealthDataEncryptionService.encryptForTesting(
      original,
      key: key,
      collectionName: 'medicationCheckins',
    );
    final decrypted = HealthDataEncryptionService.decryptForTesting(
      encrypted,
      key: key,
    );

    expect(decrypted, original);
  });

  test('encrypts AI conversation content while keeping query metadata', () {
    final encrypted = HealthDataEncryptionService.encryptForTesting(
      {
        'dateKey': '2026-07-30',
        'mode': 'dailyRecord',
        'messages': [
          {
            'role': 'user',
            'text': 'private conversation',
          },
        ],
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 30)),
      },
      key: key,
      collectionName: 'aiConversations',
    );

    expect(encrypted['dateKey'], '2026-07-30');
    expect(encrypted.containsKey('mode'), isFalse);
    expect(encrypted.containsKey('messages'), isFalse);
    expect(
      encrypted['encryptedHealthData'],
      isNot(contains('private conversation')),
    );
    expect(
      HealthDataEncryptionService.decryptForTesting(encrypted, key: key),
      containsPair('mode', 'dailyRecord'),
    );
  });

  test('encrypts AI reflection and draft private fields', () {
    final reflection = HealthDataEncryptionService.encryptForTesting(
      {
        'summary': 'private reflection',
        'crisisDetected': false,
        'generatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 30)),
      },
      key: key,
      collectionName: 'aiJournalReflections',
    );
    final draft = HealthDataEncryptionService.encryptForTesting(
      {
        'dateKey': '2026-07-30',
        'rawUserEntries': ['private draft'],
        'diaryText': 'private diary',
      },
      key: key,
      collectionName: 'aiRecordDrafts',
    );

    expect(reflection.containsKey('summary'), isFalse);
    expect(reflection.containsKey('crisisDetected'), isFalse);
    expect(reflection['generatedAt'], isA<Timestamp>());
    expect(draft['dateKey'], '2026-07-30');
    expect(draft.containsKey('rawUserEntries'), isFalse);
    expect(draft.containsKey('diaryText'), isFalse);
  });

  test('keeps legacy plaintext documents readable during migration', () {
    final legacy = <String, dynamic>{
      'name': 'legacy medicine',
      'dose': 5,
    };

    expect(
      HealthDataEncryptionService.decryptForTesting(legacy, key: key),
      legacy,
    );
  });

  test('rejects a modified authenticated health payload', () {
    final encrypted = HealthDataEncryptionService.encryptForTesting(
      {'name': 'private medicine', 'dose': 10},
      key: key,
      collectionName: 'medications',
    );
    final payload = encrypted['encryptedHealthData'] as String;
    final tamperIndex = payload.indexOf(':') + 1;
    encrypted['encryptedHealthData'] = '${payload.substring(0, tamperIndex)}'
        '${payload[tamperIndex] == 'A' ? 'B' : 'A'}'
        '${payload.substring(tamperIndex + 1)}';

    expect(
      () => HealthDataEncryptionService.decryptForTesting(
        encrypted,
        key: key,
      ),
      throwsStateError,
    );
  });
}
