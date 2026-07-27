import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/encryption_service.dart';

void main() {
  group('EncryptionService binary encryption', () {
    final key = encrypt_lib.Key(
      Uint8List.fromList(List<int>.generate(32, (index) => index)),
    );

    test('round trips image bytes without exposing plaintext', () {
      final service = EncryptionService(key);
      final original = Uint8List.fromList(
        List<int>.generate(64, (index) => index % 256),
      );

      final encrypted = service.encryptBytes(original);
      final decrypted = service.decryptBytes(encrypted);

      expect(encrypted, isNot(equals(original)));
      expect(decrypted, equals(original));
    });

    test('rejects modified authenticated ciphertext', () {
      final service = EncryptionService(key);
      final encrypted = service.encryptBytes(Uint8List.fromList([1, 2, 3]));
      encrypted[encrypted.length - 1] ^= 1;

      expect(service.tryDecryptBytes(encrypted), isNull);
    });

    test('uses a different random IV for every encryption', () {
      final service = EncryptionService(key);
      final original = Uint8List.fromList([1, 2, 3]);

      expect(
        service.encryptBytes(original),
        isNot(equals(service.encryptBytes(original))),
      );
    });
  });
}
