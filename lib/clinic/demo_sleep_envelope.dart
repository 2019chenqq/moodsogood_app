import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' show RSAKeyParser;
import 'package:pointycastle/export.dart';

/// Dedicated synthetic-data pilot protocol. No patient personal AES key is used.
class DemoSleepEnvelope {
  static const project = 'innera-demo';
  static const algorithm = 'AES-256-GCM';
  static const wrappingAlgorithm = 'RSA-OAEP-3072-SHA256';

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }

  static String documentId() => base64UrlEncode(_random(18));

  static Map<String, dynamic> encrypt({
    required String uid,
    required String clinicId,
    required String documentId,
    required int epoch,
    required String keyVersion,
    required String publicKeyPem,
    required Map<String, dynamic> sleep,
    String type = 'sleepRecords',
  }) {
    final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
    if (![
          'sleepRecords',
          'healthEvents',
          'checkIns',
          'medications',
          'dailyRecords',
          'aiSummaries'
        ].contains(type) ||
        ![uid, clinicId, documentId].every(idPattern.hasMatch) ||
        epoch <= 0 ||
        !RegExp(r'^projects/innera-demo/locations/[a-z0-9-]+/keyRings/[a-zA-Z0-9_-]+/cryptoKeys/[a-zA-Z0-9_-]+/cryptoKeyVersions/[1-9][0-9]*$')
            .hasMatch(keyVersion)) {
      throw ArgumentError('Invalid demo encryption context');
    }
    final publicKey = RSAKeyParser().parse(publicKeyPem) as RSAPublicKey;
    if (publicKey.modulus!.bitLength != 3072) {
      throw ArgumentError('Expected RSA-3072 public key');
    }
    final key = _random(32);
    final nonce = _random(12);
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(sleep)));
    final aad = Uint8List.fromList(utf8.encode(jsonEncode([
      project,
      uid,
      clinicId,
      type,
      documentId,
      1,
      epoch,
      keyVersion,
      algorithm,
      wrappingAlgorithm,
    ])));
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
      final combined = cipher.process(plaintext);
      final random = FortunaRandom()..seed(KeyParameter(_random(32)));
      final wrapper = OAEPEncoding.withSHA256(RSAEngine())
        ..init(
            true,
            ParametersWithRandom(
                PublicKeyParameter<RSAPublicKey>(publicKey), random));
      return {
        'schemaVersion': 1,
        'algorithm': algorithm,
        'wrappingAlgorithm': wrappingAlgorithm,
        'keyVersion': keyVersion,
        'epoch': epoch,
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(combined.sublist(0, combined.length - 16)),
        'authenticationTag':
            base64Encode(combined.sublist(combined.length - 16)),
        'wrappedDataKey': base64Encode(wrapper.process(key)),
      };
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }
}
