import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_lock_screen.dart';
import '../utils/app_lock_pin_service.dart';
import '../utils/app_lock_second_factor_service.dart';
import '../utils/app_lock_session_service.dart';

class FollowUpSummaryAccessGuard {
  const FollowUpSummaryAccessGuard._();

  static Future<bool> ensureVerified(BuildContext context) async {
    if (FirebaseAuth.instance.currentUser == null) {
      await _message(context, '請先登入後再查看完整摘要。');
      return false;
    }
    if (AppLockSessionService.isVerified) return true;

    final hasPin = await AppLockPinService.hasPin();
    final hasBiometrics =
        await AppLockSecondFactorService.hasEnrolledBiometrics();
    if (!context.mounted) return false;
    if (!hasPin && !hasBiometrics) {
      await _message(context, '請先在設定中啟用 App Lock，才能查看完整摘要。');
      return false;
    }

    final method = hasPin && hasBiometrics
        ? await showModalBottomSheet<_VerificationMethod>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ListTile(
                  title: Text('驗證後查看摘要'),
                  subtitle: Text('驗證失敗或取消時不會顯示摘要內容。'),
                ),
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('使用 Face ID／指紋'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _VerificationMethod.biometrics,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('輸入 App Lock PIN'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _VerificationMethod.pin,
                  ),
                ),
              ]),
            ),
          )
        : hasBiometrics
            ? _VerificationMethod.biometrics
            : _VerificationMethod.pin;
    if (!context.mounted || method == null) return false;

    if (method == _VerificationMethod.biometrics) {
      try {
        final verified =
            await AppLockSecondFactorService.authenticateWithBiometrics();
        if (verified) AppLockSessionService.markVerified();
        if (!verified && context.mounted) {
          await _message(context, '未完成裝置驗證，摘要內容尚未開啟。');
        }
        return verified;
      } catch (_) {
        if (context.mounted) {
          await _message(context, '裝置驗證暫時無法使用，請稍後重試。');
        }
        return false;
      }
    }

    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PinVerificationPage(),
      ),
    );
    if (verified == true) AppLockSessionService.markVerified();
    return verified == true;
  }

  static Future<void> _message(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('無法查看摘要'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

enum _VerificationMethod { pin, biometrics }

class _PinVerificationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        child: Stack(children: [
          AppLockScreen(onUnlocked: () => Navigator.pop(context, true)),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  tooltip: '取消驗證',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
        ]),
      );
}
