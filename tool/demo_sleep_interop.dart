import 'dart:convert';
import 'dart:io';
import 'package:moodsogood_app/clinic/demo_sleep_envelope.dart';

/// Test-only pipe protocol. Public key in; synthetic ciphertext out. No files,
/// private keys, patient data, or diagnostic logging are involved.
Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final envelope = DemoSleepEnvelope.encrypt(
    uid: input['uid'] as String,
    clinicId: input['clinicId'] as String,
    documentId: input['documentId'] as String,
    epoch: input['epoch'] as int,
    keyVersion: input['keyVersion'] as String,
    publicKeyPem: input['publicKeyPem'] as String,
    sleep: Map<String, dynamic>.from(input['sleep'] as Map),
    type: input['type'] as String? ?? 'sleepRecords',
  );
  stdout.write(jsonEncode(envelope));
}

