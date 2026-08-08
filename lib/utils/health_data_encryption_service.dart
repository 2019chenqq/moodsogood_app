import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'encryption_service.dart';
import 'secure_storage_service.dart';

/// Encrypts health and AI records as one authenticated JSON payload.
///
/// Only fields needed by Firestore range queries and server bookkeeping remain
/// outside the payload. Legacy plaintext documents are still readable and are
/// replaced with encrypted envelopes by [migrateAllForCurrentUser].
class HealthDataEncryptionService {
  HealthDataEncryptionService._();

  static const int encryptionVersion = 1;
  static const int migrationVersion = 3;
  static const String payloadField = 'encryptedHealthData';
  static const String versionField = 'healthEncryptionVersion';
  static const String encryptedFlagField = 'healthDataEncrypted';

  static const _collections = <String>[
    'dailyRecords',
    'healthEvents',
    'medications',
    'medicationCheckins',
    'medAdjustments',
    'periodCycles',
    'healthProfile',
    'followUpWorkspace',
    'followUpInstructionHistory',
    'followUpSummaries',
    'aiConversations',
    'aiJournalReflections',
    'aiRecordDrafts',
  ];

  static const _queryFieldsByCollection = <String, Set<String>>{
    'dailyRecords': {'date', 'isTestData', 'isDevSeedOwned'},
    'healthEvents': {'timestamp'},
    'medications': <String>{},
    'medicationCheckins': {'date'},
    'medAdjustments': {'date'},
    'periodCycles': {'startDate'},
    'healthProfile': <String>{},
    'followUpWorkspace': <String>{},
    'followUpInstructionHistory': {'archivedAt'},
    'followUpSummaries': <String>{},
    'periodTracker': <String>{},
    'aiConversations': {'dateKey'},
    'aiJournalReflections': {'generatedAt'},
    'aiRecordDrafts': {'dateKey'},
  };

  static const _legacyUserHealthFields = <String>{
    'diagnosis',
    'sexAssignedAtBirth',
    'birthday',
    'followUpAppointments',
    'followUpAppointmentsUpdatedAt',
    'nextFollowUpDate',
  };

  static const _operationalFields = <String>{
    'createdAt',
    'updatedAt',
  };

  static Future<Map<String, dynamic>> decryptData(
    Map<String, dynamic> raw,
  ) async {
    final encryptedPayload = raw[payloadField];
    if (encryptedPayload is! String || encryptedPayload.isEmpty) {
      return _legacyData(raw);
    }

    final key = await _requireKey();
    return _decryptWith(raw, EncryptionService(key));
  }

  @visibleForTesting
  static Map<String, dynamic> encryptForTesting(
    Map<String, dynamic> values, {
    required encrypt_lib.Key key,
    required String collectionName,
  }) {
    return _encryptWith(
      values,
      EncryptionService(key),
      queryFields: _queryFieldsByCollection[collectionName] ?? const <String>{},
    );
  }

  @visibleForTesting
  static Map<String, dynamic> decryptForTesting(
    Map<String, dynamic> raw, {
    required encrypt_lib.Key key,
  }) =>
      _decryptWith(raw, EncryptionService(key));

  static Future<void> setEncrypted(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> values, {
    bool merge = true,
    String? policyName,
  }) async {
    final key = await _requireKey();
    final encryption = EncryptionService(key);
    final collectionName = policyName ?? reference.parent.id;

    if (!merge) {
      final encoded = _encryptWith(
        values,
        encryption,
        queryFields: _queryFieldsByCollection[collectionName] ?? const {},
      );
      await reference.set(encoded);
      return;
    }

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data() == null
          ? <String, dynamic>{}
          : _decryptWith(snapshot.data()!, encryption);
      current.addAll(values);
      final encoded = _encryptWith(
        current,
        encryption,
        queryFields: _queryFieldsByCollection[collectionName] ?? const {},
      );
      transaction.set(reference, encoded);
    });
  }

  static Future<void> updateEncrypted(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> values,
  ) =>
      setEncrypted(reference, values);

  static Future<void> mutateEncrypted(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> Function(Map<String, dynamic> current) mutate,
  ) async {
    final key = await _requireKey();
    final encryption = EncryptionService(key);
    final queryFields =
        _queryFieldsByCollection[reference.parent.id] ?? const <String>{};

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data() == null
          ? <String, dynamic>{}
          : _decryptWith(snapshot.data()!, encryption);
      final next = mutate(Map<String, dynamic>.from(current));
      transaction.set(
        reference,
        _encryptWith(next, encryption, queryFields: queryFields),
      );
    });
  }

  static Future<List<HealthDocument>> getEncrypted(
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get();
    final key = await _requireKey();
    final encryption = EncryptionService(key);
    return snapshot.docs
        .map(
          (doc) => HealthDocument(
            id: doc.id,
            reference: doc.reference,
            data: _decryptWith(doc.data(), encryption),
          ),
        )
        .toList(growable: false);
  }

  static Stream<List<HealthDocument>> watchEncrypted(
    Query<Map<String, dynamic>> query,
  ) {
    return query.snapshots().asyncMap((snapshot) async {
      final key = await _requireKey();
      final encryption = EncryptionService(key);
      return snapshot.docs
          .map(
            (doc) => HealthDocument(
              id: doc.id,
              reference: doc.reference,
              data: _decryptWith(doc.data(), encryption),
            ),
          )
          .toList(growable: false);
    });
  }

  static Future<void> migrateAllForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final key = await _requireKey();
    final encryption = EncryptionService(key);
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userSnapshot = await userRef.get();
    final completedVersion =
        (userSnapshot.data()?['healthEncryptionMigrationVersion'] as num?)
                ?.toInt() ??
            0;
    if (completedVersion >= migrationVersion) return;

    for (final collectionName in _collections) {
      final snapshot = await userRef.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        final raw = doc.data();
        if (raw[encryptedFlagField] == true &&
            raw[payloadField] is String &&
            raw[versionField] == encryptionVersion) {
          continue;
        }
        final encoded = _encryptWith(
          _legacyData(raw),
          encryption,
          queryFields:
              _queryFieldsByCollection[collectionName] ?? const <String>{},
        );
        await doc.reference.set(encoded);
      }
    }

    final periodTrackerRef =
        userRef.collection('settings').doc('periodTracker');
    final periodTrackerSnapshot = await periodTrackerRef.get();
    final periodTrackerData = periodTrackerSnapshot.data();
    if (periodTrackerData != null &&
        periodTrackerData[payloadField] is! String) {
      await setEncrypted(
        periodTrackerRef,
        periodTrackerData,
        merge: false,
        policyName: 'periodTracker',
      );
    }

    final legacyUserData = userSnapshot.data() ?? <String, dynamic>{};
    final legacyHealthData = <String, dynamic>{
      for (final field in _legacyUserHealthFields)
        if (legacyUserData.containsKey(field)) field: legacyUserData[field],
    };
    if (legacyHealthData.isNotEmpty) {
      final healthProfileRef =
          userRef.collection('healthProfile').doc('current');
      await setEncrypted(healthProfileRef, legacyHealthData);
      await userRef.update({
        for (final field in legacyHealthData.keys) field: FieldValue.delete(),
      });
    }

    await userRef.set({
      'healthEncryptionMigrationVersion': migrationVersion,
      'healthEncryptionMigratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Re-wraps health envelopes after a KDF upgrade changes the local AES key.
  static Future<void> reencryptAllForKeyChange({
    required String uid,
    required encrypt_lib.Key oldKey,
    required encrypt_lib.Key newKey,
  }) async {
    final oldEncryption = EncryptionService(oldKey);
    final newEncryption = EncryptionService(newKey);
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    for (final collectionName in _collections) {
      final snapshot = await userRef.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        final raw = doc.data();
        if (raw[payloadField] is! String) continue;
        final plain = _decryptWith(raw, oldEncryption);
        final encoded = _encryptWith(
          plain,
          newEncryption,
          queryFields:
              _queryFieldsByCollection[collectionName] ?? const <String>{},
        );
        await doc.reference.set(encoded);
      }
    }

    final periodTrackerRef =
        userRef.collection('settings').doc('periodTracker');
    final periodTrackerSnapshot = await periodTrackerRef.get();
    final periodTrackerRaw = periodTrackerSnapshot.data();
    if (periodTrackerRaw?[payloadField] is String) {
      final plain = _decryptWith(periodTrackerRaw!, oldEncryption);
      await periodTrackerRef.set(
        _encryptWith(
          plain,
          newEncryption,
          queryFields: const <String>{},
        ),
      );
    }
  }

  static Map<String, dynamic> _encryptWith(
    Map<String, dynamic> values,
    EncryptionService encryption, {
    required Set<String> queryFields,
  }) {
    final cleartext = <String, dynamic>{};
    final privateData = <String, dynamic>{};

    for (final entry in values.entries) {
      if (_isEnvelopeField(entry.key)) continue;
      if (queryFields.contains(entry.key) ||
          _operationalFields.contains(entry.key) ||
          entry.value is FieldValue) {
        cleartext[entry.key] = entry.value;
      } else {
        privateData[entry.key] = entry.value;
      }
    }

    return <String, dynamic>{
      ...cleartext,
      payloadField: encryption.encryptData(jsonEncode(_encode(privateData))),
      versionField: encryptionVersion,
      encryptedFlagField: true,
    };
  }

  static Map<String, dynamic> _decryptWith(
    Map<String, dynamic> raw,
    EncryptionService encryption,
  ) {
    final encryptedPayload = raw[payloadField];
    if (encryptedPayload is! String || encryptedPayload.isEmpty) {
      return _legacyData(raw);
    }

    final plaintext = encryption.tryDecryptData(encryptedPayload);
    if (plaintext == null || plaintext == encryptedPayload) {
      throw StateError('Health data could not be decrypted with this key.');
    }
    final decoded = jsonDecode(plaintext);
    if (decoded is! Map) {
      throw const FormatException('Invalid encrypted health data payload.');
    }

    return <String, dynamic>{
      for (final entry in raw.entries)
        if (!_isEnvelopeField(entry.key)) entry.key: entry.value,
      ...Map<String, dynamic>.from(_decode(decoded) as Map),
    };
  }

  static Map<String, dynamic> _legacyData(Map<String, dynamic> raw) => {
        for (final entry in raw.entries)
          if (!_isEnvelopeField(entry.key)) entry.key: entry.value,
      };

  static bool _isEnvelopeField(String field) =>
      field == payloadField ||
      field == versionField ||
      field == encryptedFlagField;

  static dynamic _encode(dynamic value) {
    if (value is Timestamp) {
      return {
        r'$healthType': 'timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
      };
    }
    if (value is DateTime) {
      return {
        r'$healthType': 'dateTime',
        'value': value.toUtc().toIso8601String(),
      };
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _encode(entry.value),
      };
    }
    if (value is Iterable) return value.map(_encode).toList();
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    throw UnsupportedError(
      'Unsupported health data value: ${value.runtimeType}',
    );
  }

  static dynamic _decode(dynamic value) {
    if (value is List) return value.map(_decode).toList();
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map[r'$healthType'] == 'timestamp') {
        return Timestamp(
          (map['seconds'] as num).toInt(),
          (map['nanoseconds'] as num).toInt(),
        );
      }
      if (map[r'$healthType'] == 'dateTime') {
        return DateTime.parse(map['value'] as String).toLocal();
      }
      return {for (final entry in map.entries) entry.key: _decode(entry.value)};
    }
    return value;
  }

  static Future<encrypt_lib.Key> _requireKey() async {
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) {
      throw StateError('Encryption key is unavailable.');
    }
    return key;
  }
}

class HealthDocument {
  const HealthDocument({
    required this.id,
    required this.reference,
    required this.data,
  });

  final String id;
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> data;
}
