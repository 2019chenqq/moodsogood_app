import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/app_lock_pin_service.dart';
import '../utils/app_lock_second_factor_service.dart';

class AppLockEmailVerificationDialog extends StatefulWidget {
  const AppLockEmailVerificationDialog({super.key});

  @override
  State<AppLockEmailVerificationDialog> createState() =>
      _AppLockEmailVerificationDialogState();
}

class _AppLockEmailVerificationDialogState
    extends State<AppLockEmailVerificationDialog> {
  StreamSubscription<Uri>? _linkSubscription;
  Timer? _timer;
  DateTime? _expiresAt;
  DateTime? _resendAvailableAt;
  String? _maskedEmail;
  String? _message;
  bool _sending = true;
  bool _processingLink = false;
  bool _lockedOut = false;

  @override
  void initState() {
    super.initState();
    _linkSubscription =
        AppLockSecondFactorService.emailLinkStream.listen(_handleLink);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
    _initialize();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final status = await AppLockPinService.getEmailVerificationStatus();
    final remaining = status.remaining(DateTime.now());
    if (!mounted) return;
    if (remaining > Duration.zero) {
      setState(() {
        _sending = false;
        _lockedOut = true;
        _message = '驗證失敗次數過多，請在 ${_durationLabel(remaining)} 後再試';
      });
      return;
    }

    final email = await AppLockSecondFactorService.currentVerifiedEmail();
    if (!mounted) return;
    if (email == null) {
      setState(() {
        _sending = false;
        _message = '目前帳號沒有可用的已驗證 Email';
      });
      return;
    }
    setState(() => _maskedEmail = _maskEmail(email));

    await _sendLink();
    final initialLink = await AppLockSecondFactorService.getInitialLink();
    if (initialLink != null) await _handleLink(initialLink);
  }

  Future<void> _sendLink() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final remaining = await AppLockSecondFactorService.resendRemaining();
      if (remaining > Duration.zero) {
        _resendAvailableAt = DateTime.now().add(remaining);
        _expiresAt = await AppLockSecondFactorService.pendingExpiresAt();
        if (mounted) {
          setState(() {
            _sending = false;
            _message = '驗證信已寄出，請在同一支裝置開啟信件中的連結';
          });
        }
        return;
      }

      final expiresAt =
          await AppLockSecondFactorService.sendEmailVerificationLink();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _expiresAt = expiresAt;
        _resendAvailableAt =
            DateTime.now().add(AppLockSecondFactorService.resendCooldown);
        _message =
            expiresAt == null ? '暫時無法寄送驗證信，請稍後再試' : '驗證信已寄出，請在同一支裝置開啟信件中的連結';
      });
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'App Lock Email Link 寄送失敗，Firebase 錯誤碼：${error.code}',
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = _sendErrorMessage(error.code);
      });
    } catch (error) {
      debugPrint('App Lock Email Link 寄送失敗：${error.runtimeType}');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = '驗證信寄送失敗，請稍後再試';
      });
    }
  }

  String _sendErrorMessage(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return 'Firebase 尚未啟用 Email Link 登入，請先完成 Authentication 設定';
      case 'invalid-continue-uri':
      case 'unauthorized-continue-uri':
        return 'Email 驗證網址尚未加入 Firebase 授權網域';
      case 'dynamic-link-not-activated':
        return 'Firebase Hosting 的 Email Link 尚未完成設定';
      case 'too-many-requests':
        return '寄送次數過多，請稍後再試';
      case 'network-request-failed':
        return '無法連線至驗證服務，請確認網路後再試';
      default:
        return '驗證信寄送失敗（錯誤碼：$code）';
    }
  }

  Future<void> _handleLink(Uri link) async {
    if (_processingLink || _lockedOut) return;
    _processingLink = true;
    final result = await AppLockSecondFactorService.verifyEmailLink(link);
    if (!mounted) return;

    if (result.succeeded) {
      await AppLockPinService.resetEmailVerificationFailures();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    _processingLink = false;
    if (result.outcome == AppLockEmailVerificationOutcome.unavailable) return;

    if (result.outcome == AppLockEmailVerificationOutcome.expired) {
      setState(() => _message = '驗證連結已超過 10 分鐘，請重新寄送');
      return;
    }

    final failedStatus =
        await AppLockPinService.recordEmailVerificationFailure();
    if (!mounted) return;
    final remaining = failedStatus.remaining(DateTime.now());
    setState(() {
      _lockedOut = remaining > Duration.zero;
      _message = _lockedOut
          ? '驗證失敗次數過多，請在 ${_durationLabel(remaining)} 後再試'
          : '驗證連結無效，請使用最新一封信並確認帳號正確';
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final resendRemaining =
        _resendAvailableAt?.difference(now) ?? Duration.zero;
    final expiresRemaining = _expiresAt?.difference(now) ?? Duration.zero;
    final canResend =
        !_sending && !_lockedOut && resendRemaining <= Duration.zero;

    return PopScope(
      canPop: !_processingLink,
      child: AlertDialog(
        title: const Text('Email 身分驗證'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _maskedEmail == null ? '正在確認帳號…' : '驗證連結會寄到 $_maskedEmail',
            ),
            const SizedBox(height: 12),
            if (_sending || _processingLink)
              const Center(child: CircularProgressIndicator())
            else ...[
              Text(_message ?? '請開啟驗證信中的連結'),
              if (expiresRemaining > Duration.zero) ...[
                const SizedBox(height: 8),
                Text(
                  '連結剩餘 ${_durationLabel(expiresRemaining)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '若沒收到驗證信，請至垃圾郵件查看',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed:
                _processingLink ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: canResend ? _sendLink : null,
            child: Text(
              resendRemaining > Duration.zero
                  ? '${resendRemaining.inSeconds + 1} 秒後重寄'
                  : '重新寄送',
            ),
          ),
        ],
      ),
    );
  }

  static String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return '***';
    final local = parts.first;
    final visible = local.substring(0, local.length > 2 ? 2 : 1);
    return '$visible***@${parts.last}';
  }

  static String _durationLabel(Duration duration) {
    final seconds = duration.inSeconds + 1;
    if (seconds >= 60) {
      final minutes = (seconds / 60).ceil();
      return '$minutes 分鐘';
    }
    return '$seconds 秒';
  }
}
