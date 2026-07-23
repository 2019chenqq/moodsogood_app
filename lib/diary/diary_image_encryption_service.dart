import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/encryption_service.dart';
import '../utils/secure_storage_service.dart';

/// Client-side encryption and one-time migration for diary attachments.
class DiaryImageEncryptionService {
  static const int migrationVersion = 1;
  static const String storageSourcePrefix = 'storage-path:';
  static const int maxDownloadBytes = 25 * 1024 * 1024;
  static Future<void>? _migrationInFlight;

  static const _privateTextFields = <String>{
    'title',
    'content',
    'themeSong',
    'highlight',
    'metaphor',
    'conceited',
    'proudOf',
    'selfCare',
    'gratitude',
    'themeSongProvider',
    'themeSongProviderId',
    'themeSongTitle',
    'themeSongArtist',
    'themeSongAlbum',
    'themeSongArtworkUrl',
    'themeSongExternalUrl',
    'themeSongIsrc',
    'themeSongRecommendationReason',
  };

  static bool isEncryptedStorageSource(String source) =>
      source.startsWith(storageSourcePrefix);

  static String _pathFromSource(String source) =>
      source.substring(storageSourcePrefix.length);

  static List<String> decodeImageSources(
    Map<String, dynamic> data,
    EncryptionService encryption,
  ) {
    final values = (data['imageUrls'] as List<dynamic>?) ?? const [];
    if (data['imageRefsEncrypted'] != true) {
      return values.map((value) => value.toString()).toList();
    }
    return values
        .map((value) => encryption.tryDecryptData(value.toString()))
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
  }

  static List<String> encodeImageSources(
    Iterable<String> sources,
    EncryptionService encryption,
  ) =>
      sources.map(encryption.encryptData).toList();

  static Future<String> uploadEncrypted({
    required String uid,
    required Uint8List plainBytes,
    encrypt_lib.Key? key,
  }) async {
    final resolvedKey = key ?? await SecureStorageService.getOrRecoverKey();
    if (resolvedKey == null) {
      throw StateError('Encryption key is unavailable.');
    }
    final encrypted = EncryptionService(resolvedKey).encryptBytes(plainBytes);
    final random = Random.secure();
    final opaqueId = base64Url
        .encode(List<int>.generate(18, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final path = 'users/$uid/diary_images/$opaqueId.innera';
    await FirebaseStorage.instance.ref(path).putData(
          encrypted,
          SettableMetadata(
            contentType: 'application/octet-stream',
            customMetadata: const {
              'clientEncrypted': 'true',
              'encryption': 'AES-256-GCM',
              'formatVersion': '1',
            },
          ),
        );
    return '$storageSourcePrefix$path';
  }

  static Future<Uint8List> downloadAndDecrypt(String source) async {
    if (!isEncryptedStorageSource(source)) {
      throw ArgumentError.value(source, 'source', 'Not an encrypted image.');
    }
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) throw StateError('Encryption key is unavailable.');
    final bytes = await FirebaseStorage.instance
        .ref(_pathFromSource(source))
        .getData(maxDownloadBytes);
    if (bytes == null) throw StateError('The encrypted image is empty.');
    return EncryptionService(key).decryptBytes(bytes);
  }

  static Future<void> deleteSource(String source) async {
    try {
      final ref = isEncryptedStorageSource(source)
          ? FirebaseStorage.instance.ref(_pathFromSource(source))
          : FirebaseStorage.instance.refFromURL(source);
      await ref.delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  /// Migrates every existing diary document once. Plain text fields are
  /// encrypted, legacy JPEGs are downloaded and encrypted locally, and the
  /// old Storage object is deleted only after Firestore points to the new one.
  static Future<void> migrateAllForCurrentUser() {
    final running = _migrationInFlight;
    if (running != null) return running;
    final migration = _migrateAllForCurrentUser();
    _migrationInFlight = migration;
    return migration.whenComplete(() {
      if (identical(_migrationInFlight, migration)) {
        _migrationInFlight = null;
      }
    });
  }

  static Future<void> _migrateAllForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) return;

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userSnapshot = await userRef.get();
    final completedVersion =
        (userSnapshot.data()?['diaryEncryptionMigrationVersion'] as num?)
                ?.toInt() ??
            0;
    if (completedVersion >= migrationVersion) return;

    final encryption = EncryptionService(key);
    final diaryDocs = await userRef.collection('diary').get();
    for (final doc in diaryDocs.docs) {
      final data = doc.data();
      final updates = <String, dynamic>{};

      for (final field in _privateTextFields) {
        final value = data[field];
        if (value is! String) continue;
        final decrypted = encryption.tryDecryptData(value);
        final alreadyEncrypted = value.contains(':') && decrypted != value;
        if (!alreadyEncrypted) updates[field] = encryption.encryptData(value);
      }

      final oldSources = decodeImageSources(data, encryption);
      final newSources = <String>[];
      final legacySourcesToDelete = <String>[];
      final newlyUploadedSources = <String>[];
      var firestoreCommitted = false;
      try {
        for (final source in oldSources) {
          if (isEncryptedStorageSource(source)) {
            newSources.add(source);
            continue;
          }
          final legacyRef = FirebaseStorage.instance.refFromURL(source);
          final bytes = await legacyRef.getData(maxDownloadBytes);
          if (bytes == null) throw StateError('Legacy diary image is empty.');
          final encryptedSource = await uploadEncrypted(
            uid: user.uid,
            plainBytes: bytes,
            key: key,
          );
          newSources.add(encryptedSource);
          newlyUploadedSources.add(encryptedSource);
          legacySourcesToDelete.add(source);
        }

        updates.addAll({
          'imageUrls': encodeImageSources(newSources, encryption),
          'imageRefsEncrypted': true,
          'imageEncryptionVersion': migrationVersion,
          'isEncrypted': true,
        });
        await doc.reference.set(updates, SetOptions(merge: true));
        firestoreCommitted = true;
        for (final source in legacySourcesToDelete) {
          try {
            await deleteSource(source);
          } catch (_) {
            // The encrypted copy is already committed. A failed cleanup must
            // never make Firestore point at a deleted replacement image.
          }
        }
      } catch (_) {
        if (!firestoreCommitted) {
          for (final source in newlyUploadedSources) {
            try {
              await deleteSource(source);
            } catch (_) {}
          }
        }
        rethrow;
      }
    }

    await userRef.set({
      'diaryEncryptionMigrationVersion': migrationVersion,
      'diaryEncryptionMigratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
