import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/app_lock_reauthentication_service.dart';

void main() {
  test('maps only supported Firebase providers', () {
    final providers = AppLockReauthenticationService.providersFromIds([
      'password',
      'google.com',
      'apple.com',
      'google.com',
    ]);

    expect(
      providers,
      [
        AppLockAuthProvider.google,
        AppLockAuthProvider.apple,
      ],
    );
  });

  test('returns no reset provider for unsupported sign-in methods', () {
    expect(
      AppLockReauthenticationService.providersFromIds([
        'password',
        'phone',
      ]),
      isEmpty,
    );
  });
}
