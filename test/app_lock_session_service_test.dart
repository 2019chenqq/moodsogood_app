import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/app_lock_session_service.dart';

void main() {
  tearDown(AppLockSessionService.resetForTesting);

  test('verification survives a short background interval', () {
    final start = DateTime(2026, 8, 5, 9);
    AppLockSessionService.markVerified(now: start);
    AppLockSessionService.markBackgrounded(now: start);
    AppLockSessionService.markResumed(
      now: start.add(const Duration(minutes: 2, seconds: 59)),
    );
    expect(AppLockSessionService.isVerified, isTrue);
  });

  test('verification expires after three minutes in background', () {
    final start = DateTime(2026, 8, 5, 9);
    AppLockSessionService.markVerified(now: start);
    AppLockSessionService.markBackgrounded(now: start);
    AppLockSessionService.markResumed(
      now: start.add(const Duration(minutes: 3)),
    );
    expect(AppLockSessionService.isVerified, isFalse);
  });
}
