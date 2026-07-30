import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../utils/encryption_service.dart';
import '../utils/secure_storage_service.dart';
import 'innera_ai_message.dart';

class InneraAiChatImageService {
  InneraAiChatImageService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const maxImageBytes = 5 * 1024 * 1024;
  static const encryptedImageVersion = 1;
  static const _maxEncryptedImageBytes = maxImageBytes + 1024;

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  /// Saves the long-lived chat copy as authenticated ciphertext. The returned
  /// attachment intentionally has no public download URL.
  Future<InneraAiImageAttachment> uploadEncryptedPermanent({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('A signed-in user is required.');
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const InneraAiChatImageException('照片大小必須小於 5 MB。');
    }
    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) {
      throw const InneraAiChatImageException(
        '找不到加密金鑰，請先解鎖或復原帳號。',
      );
    }

    final contentType = _contentType(fileName);
    final encrypted = EncryptionService(key).encryptBytes(bytes);
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    final storagePath = 'users/${user.uid}/ai_chat_images_encrypted/$dateKey/'
        '${_randomFileName()}.innera';
    await _storage.ref().child(storagePath).putData(
          encrypted,
          SettableMetadata(
            contentType: 'application/octet-stream',
            customMetadata: {
              'purpose': 'innera-ai-chat-permanent',
              'clientEncrypted': 'true',
              'encryption': 'AES-256-GCM',
              'formatVersion': '$encryptedImageVersion',
              'originalContentType': contentType,
            },
          ),
        );
    return InneraAiImageAttachment(
      storagePath: storagePath,
      downloadUrl: '',
      contentType: contentType,
      encryptionVersion: encryptedImageVersion,
    );
  }

  /// Downloads an attachment and returns plaintext only in process memory.
  /// Legacy plaintext attachments remain readable during migration.
  Future<Uint8List> downloadForDisplay(
    InneraAiImageAttachment attachment,
  ) async {
    if (!attachment.isValid) {
      throw const InneraAiChatImageException('圖片附件格式無效。');
    }
    final storedBytes =
        await _storage.ref().child(attachment.storagePath).getData(
              attachment.isEncrypted ? _maxEncryptedImageBytes : maxImageBytes,
            );
    if (storedBytes == null || storedBytes.isEmpty) {
      throw const InneraAiChatImageException('找不到聊天圖片。');
    }
    if (!attachment.isEncrypted) return storedBytes;

    final key = await SecureStorageService.getOrRecoverKey();
    if (key == null) {
      throw const InneraAiChatImageException(
        '找不到加密金鑰，請先解鎖或復原帳號。',
      );
    }
    try {
      return EncryptionService(key).decryptBytes(storedBytes);
    } on FormatException {
      throw const InneraAiChatImageException('無法解密聊天圖片。');
    }
  }

  /// Uploads a short-lived plaintext copy that the AI backend can read.
  /// This path must never be persisted in a conversation document.
  Future<InneraAiTemporaryImage> uploadTemporaryForAi({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('A signed-in user is required.');
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const InneraAiChatImageException('照片大小必須小於 5 MB。');
    }

    final contentType = _contentType(fileName);
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final now = DateTime.now();
    final storagePath = 'ai_chat_temp/${user.uid}/${_dateKey(now)}/'
        '${_randomFileName()}.$extension';
    final expiresAt = now.toUtc().add(const Duration(hours: 1));
    await _storage.ref().child(storagePath).putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            customMetadata: {
              'purpose': 'innera-ai-chat-temporary',
              'expiresAt': expiresAt.toIso8601String(),
            },
          ),
        );
    return InneraAiTemporaryImage(
      storagePath: storagePath,
      contentType: contentType,
    );
  }

  Future<InneraAiTemporaryImage> prepareTemporaryForAi(
    InneraAiImageAttachment attachment,
  ) async {
    final bytes = await downloadForDisplay(attachment);
    return uploadTemporaryForAi(
      bytes: bytes,
      fileName: 'image.${_extensionFor(attachment.contentType)}',
    );
  }

  Future<InneraAiImageAttachment> migrateLegacyAttachment(
    InneraAiImageAttachment attachment,
  ) async {
    if (attachment.isEncrypted) return attachment;
    final bytes = await downloadForDisplay(attachment);
    return uploadEncryptedPermanent(
      bytes: bytes,
      fileName: 'image.${_extensionFor(attachment.contentType)}',
    );
  }

  Future<InneraAiImageAttachment> upload({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('A signed-in user is required.');
    if (bytes.isEmpty || bytes.length > maxImageBytes) {
      throw const InneraAiChatImageException('照片大小必須小於 5 MB。');
    }

    final contentType = _contentType(fileName);
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final now = DateTime.now();
    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final storagePath =
        'users/${user.uid}/ai_chat_images/$dateKey/${now.microsecondsSinceEpoch}.$extension';
    final reference = _storage.ref().child(storagePath);
    await reference.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: const {'purpose': 'innera-ai-chat'},
      ),
    );
    return InneraAiImageAttachment(
      storagePath: storagePath,
      downloadUrl: await reference.getDownloadURL(),
      contentType: contentType,
    );
  }

  Future<void> deleteAll(Iterable<String> storagePaths) async {
    for (final path in storagePaths.toSet()) {
      if (path.trim().isEmpty) continue;
      try {
        await _storage.ref().child(path).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
  }

  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _randomFileName() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _contentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _extensionFor(String contentType) => switch (contentType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

class InneraAiTemporaryImage {
  const InneraAiTemporaryImage({
    required this.storagePath,
    required this.contentType,
  });

  final String storagePath;
  final String contentType;
}

class InneraAiChatImageException implements Exception {
  const InneraAiChatImageException(this.message);

  final String message;

  @override
  String toString() => message;
}
