import 'dart:convert';
import 'dart:math';

final Random _secureRandom = Random.secure();

/// Creates an opaque ID used to correlate one App request with one server-side
/// AI usage event. It contains no user or health information.
String createAiRequestId() {
  final randomBytes = List<int>.generate(
    18,
    (_) => _secureRandom.nextInt(256),
    growable: false,
  );
  final suffix = base64UrlEncode(randomBytes).replaceAll('=', '');
  return '${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
