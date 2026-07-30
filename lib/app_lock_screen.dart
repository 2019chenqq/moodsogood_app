import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'analytics_service.dart';
import 'utils/app_lock_pin_service.dart';
import 'utils/app_lock_reauthentication_service.dart';
import 'utils/app_lock_second_factor_service.dart';
import 'widgets/app_lock_email_verification_dialog.dart';

enum _SecondFactorChoice {
  retryBiometrics,
  deviceSecurity,
  email,
}

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  static const int _pinLength = 6; // 想改 4 碼就改這裡
  String _input = '';
  String? _errorText;
  bool _loading = false;

  bool _hasPin = false;
  bool _initializing = true;
  bool _processingIncomingEmailLink = false;
  DateTime? _lockedUntil;
  Timer? _lockoutTimer;

  Color get _primary => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('app_lock_screen');
    _initializePin();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializePin() async {
    final hasPin = await AppLockPinService.hasPin();
    final status = await AppLockPinService.getStatus();
    if (!mounted) return;

    if (!hasPin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onUnlocked();
      });
      return;
    }

    setState(() {
      _hasPin = true;
      _lockedUntil = status.lockedUntil;
      _initializing = false;
      _errorText = _lockoutMessage();
    });
    _startLockoutTimerIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumePendingEmailLinkIfNeeded();
    });
  }

  Future<void> _resumePendingEmailLinkIfNeeded() async {
    if (_processingIncomingEmailLink) return;
    final link = await AppLockSecondFactorService.getInitialLink();
    if (!mounted ||
        link == null ||
        !FirebaseAuth.instance.isSignInWithEmailLink(link.toString())) {
      return;
    }

    _processingIncomingEmailLink = true;
    setState(() {
      _loading = true;
      _errorText = null;
      _input = '';
    });

    final result = await AppLockSecondFactorService.verifyEmailLink(link);
    if (!mounted) return;

    if (result.succeeded) {
      await AppLockPinService.resetEmailVerificationFailures();
      if (!mounted) return;
      await _completePinReset();
      return;
    }

    _processingIncomingEmailLink = false;
    setState(() => _loading = false);
    if (result.outcome == AppLockEmailVerificationOutcome.expired) {
      _showMessage('驗證連結已超過 10 分鐘，請重新寄送');
      return;
    }
    if (result.outcome == AppLockEmailVerificationOutcome.userMismatch) {
      _showMessage('請使用原本提出重設申請的帳號與裝置');
      return;
    }
    if (result.outcome == AppLockEmailVerificationOutcome.unavailable) {
      return;
    }

    final failedStatus =
        await AppLockPinService.recordEmailVerificationFailure();
    if (!mounted) return;
    final remaining = failedStatus.remaining(DateTime.now());
    _showMessage(
      remaining > Duration.zero
          ? '驗證失敗次數過多，請在 ${remaining.inSeconds + 1} 秒後再試'
          : '驗證連結無效，請使用最新一封信重新操作',
    );
  }

  Future<void> _checkPin() async {
    if (!_hasPin) {
      widget.onUnlocked();
      return;
    }

    final status = await AppLockPinService.getStatus();
    if (!mounted) return;
    if (status.remaining(DateTime.now()) > Duration.zero) {
      setState(() {
        _lockedUntil = status.lockedUntil;
        _errorText = _lockoutMessage();
        _input = '';
      });
      _startLockoutTimerIfNeeded();
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    final isValid = await AppLockPinService.verifyPin(_input);
    if (!mounted) return;

    if (isValid) {
      await AppLockPinService.resetFailedAttempts();
      widget.onUnlocked();
    } else {
      final failedStatus = await AppLockPinService.recordFailedAttempt();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lockedUntil = failedStatus.lockedUntil;
        _errorText = _lockoutMessage() ?? '密碼錯誤，請再試一次';
        _input = '';
      });
      _startLockoutTimerIfNeeded();
    }
  }

  void _onDigitPressed(String digit) {
    if (_loading || _isLockedOut) return;
    if (_input.length >= _pinLength) return;

    setState(() {
      _input += digit;
      _errorText = null;
    });

    if (_input.length == _pinLength) {
      _checkPin();
    }
  }

  void _onBackspace() {
    if (_loading || _isLockedOut) return;
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _errorText = null;
    });
  }

  bool get _isLockedOut {
    final lockedUntil = _lockedUntil;
    return lockedUntil != null && lockedUntil.isAfter(DateTime.now());
  }

  String? _lockoutMessage() {
    final lockedUntil = _lockedUntil;
    if (lockedUntil == null) return null;
    final remaining = lockedUntil.difference(DateTime.now()).inSeconds + 1;
    if (remaining <= 0) return null;
    return '嘗試次數過多，請在 $remaining 秒後再試';
  }

  void _startLockoutTimerIfNeeded() {
    _lockoutTimer?.cancel();
    if (!_isLockedOut) return;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isLockedOut) {
        timer.cancel();
        setState(() {
          _lockedUntil = null;
          _errorText = null;
        });
        return;
      }
      setState(() => _errorText = _lockoutMessage());
    });
  }

  Future<void> _handleForgotPin() async {
    if (_loading) return;

    final resetStatus = await AppLockPinService.getResetStatus();
    final remaining = resetStatus.remaining(DateTime.now());
    if (!mounted) return;
    if (remaining > Duration.zero) {
      _showMessage(
        '重設嘗試次數過多，請在 ${remaining.inSeconds + 1} 秒後再試',
      );
      return;
    }

    final providers = await AppLockReauthenticationService.availableProviders();
    if (!mounted) return;
    if (providers.isEmpty) {
      _showMessage('目前登入狀態無法重新驗證，請確認帳號仍為登入狀態');
      return;
    }

    final provider = await _chooseProvider(providers);
    if (!mounted || provider == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重設 App 解鎖密碼'),
        content: Text(
          '接下來會使用 ${provider.label} 再次確認是你本人。'
          '\n\n驗證成功後需要設定新的 6 位密碼；日記加密金鑰與雲端資料不會被刪除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('開始驗證'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() {
      _loading = true;
      _errorText = null;
      _input = '';
    });

    final result =
        await AppLockReauthenticationService.reauthenticate(provider);
    if (!mounted) return;

    if (!result.succeeded) {
      setState(() => _loading = false);
      if (result.outcome == AppLockReauthenticationOutcome.canceled) {
        _showMessage('已取消身分驗證');
        return;
      }
      if (result.outcome == AppLockReauthenticationOutcome.networkError) {
        _showMessage('網路連線異常或驗證逾時，請稍後再試');
        return;
      }

      final failedStatus = await AppLockPinService.recordResetFailure();
      if (!mounted) return;
      final failedRemaining = failedStatus.remaining(DateTime.now());
      _showMessage(
        failedRemaining > Duration.zero
            ? '身分驗證失敗，請在 ${failedRemaining.inSeconds + 1} 秒後再試'
            : '身分驗證失敗，請確認使用原本綁定的帳號',
      );
      return;
    }

    final secondFactorVerified = await _verifySecondFactor();
    if (!mounted) return;
    if (!secondFactorVerified) {
      setState(() => _loading = false);
      return;
    }

    await _completePinReset();
  }

  Future<void> _completePinReset() async {
    final newPin = await _showNewPinDialog();
    if (!mounted) return;
    if (newPin == null) {
      setState(() {
        _loading = false;
        _processingIncomingEmailLink = false;
      });
      return;
    }

    try {
      await AppLockPinService.setPin(newPin);
      await AppLockPinService.resetResetFailures();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _processingIncomingEmailLink = false;
        _lockedUntil = null;
        _errorText = null;
        _input = '';
      });
      _showMessage('App 解鎖密碼已更新');
      widget.onUnlocked();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _processingIncomingEmailLink = false;
      });
      _showMessage('無法儲存新密碼，請稍後再試');
    }
  }

  Future<bool> _verifySecondFactor() async {
    final hasBiometrics =
        await AppLockSecondFactorService.hasEnrolledBiometrics();
    final supportsDeviceSecurity =
        await AppLockSecondFactorService.supportsDeviceAuthentication();
    if (!mounted) return false;

    if (hasBiometrics) {
      final authenticated =
          await AppLockSecondFactorService.authenticateWithBiometrics();
      if (!mounted) return false;
      if (authenticated) return true;
    }

    while (mounted) {
      final choice = await _showSecondFactorFallback(
        canRetryBiometrics: hasBiometrics,
        supportsDeviceSecurity: supportsDeviceSecurity,
      );
      if (!mounted || choice == null) return false;

      switch (choice) {
        case _SecondFactorChoice.retryBiometrics:
          final authenticated =
              await AppLockSecondFactorService.authenticateWithBiometrics();
          if (!mounted) return false;
          if (authenticated) return true;
          break;
        case _SecondFactorChoice.deviceSecurity:
          final authenticated =
              await AppLockSecondFactorService.authenticateWithDeviceSecurity();
          if (!mounted) return false;
          if (authenticated) return true;
          break;
        case _SecondFactorChoice.email:
          final verified = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const AppLockEmailVerificationDialog(),
          );
          if (!mounted) return false;
          if (verified == true) return true;
          break;
      }
    }
    return false;
  }

  Future<_SecondFactorChoice?> _showSecondFactorFallback({
    required bool canRetryBiometrics,
    required bool supportsDeviceSecurity,
  }) {
    return showModalBottomSheet<_SecondFactorChoice>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                canRetryBiometrics ? '無法完成生物辨識' : '選擇其他驗證方式',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                '你可以重新嘗試，或改用手機螢幕鎖定與 Email。'
                '生物辨識硬體失敗不會被計入驗證錯誤。',
              ),
              const SizedBox(height: 16),
              if (canRetryBiometrics)
                ListTile(
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('再試一次 Face ID／指紋'),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_SecondFactorChoice.retryBiometrics),
                ),
              if (supportsDeviceSecurity)
                ListTile(
                  leading: const Icon(Icons.screen_lock_portrait_rounded),
                  title: const Text('使用手機螢幕鎖定'),
                  subtitle: const Text('由系統驗證裝置密碼、PIN 或圖形鎖'),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_SecondFactorChoice.deviceSecurity),
                ),
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('使用 Email 驗證連結'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_SecondFactorChoice.email),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('取消重設'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<AppLockAuthProvider?> _chooseProvider(
    List<AppLockAuthProvider> providers,
  ) async {
    if (providers.length == 1) return providers.first;
    return showDialog<AppLockAuthProvider>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('選擇驗證方式'),
        children: [
          for (final provider in providers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(provider),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('使用 ${provider.label} 驗證'),
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _showNewPinDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('設定新的解鎖密碼'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: _pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '新密碼（6 位數字）',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: _pinLength,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '再次輸入新密碼',
                  counterText: '',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final pin = pinController.text.trim();
                final confirmation = confirmController.text.trim();
                if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
                  setDialogState(() => errorText = '請輸入 6 位數字密碼');
                  return;
                }
                if (pin != confirmation) {
                  setDialogState(() => errorText = '兩次輸入的密碼不一致');
                  return;
                }
                Navigator.of(dialogContext).pop(pin);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );

    pinController.dispose();
    confirmController.dispose();
    return result;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- PIN dots ----------
  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLength, (index) {
        final filled = index < _input.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: filled ? _primary : Colors.grey.shade400,
              width: 1.6,
            ),
            color: filled ? _primary : Colors.transparent,
          ),
        );
      }),
    );
  }

  // ---------- keypad ----------
  Widget _buildKeyButton({String? label, IconData? icon, VoidCallback? onTap}) {
    if (label == null && icon == null) {
      return const SizedBox(width: 80, height: 64);
    }

    return SizedBox(
      width: 80,
      height: 64,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: EdgeInsets.zero,
        ),
        child: icon != null
            ? Icon(icon)
            : Text(
                label!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeyButton(label: '1', onTap: () => _onDigitPressed('1')),
            _buildKeyButton(label: '2', onTap: () => _onDigitPressed('2')),
            _buildKeyButton(label: '3', onTap: () => _onDigitPressed('3')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeyButton(label: '4', onTap: () => _onDigitPressed('4')),
            _buildKeyButton(label: '5', onTap: () => _onDigitPressed('5')),
            _buildKeyButton(label: '6', onTap: () => _onDigitPressed('6')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeyButton(label: '7', onTap: () => _onDigitPressed('7')),
            _buildKeyButton(label: '8', onTap: () => _onDigitPressed('8')),
            _buildKeyButton(label: '9', onTap: () => _onDigitPressed('9')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildKeyButton(), // 左邊空白
            _buildKeyButton(label: '0', onTap: () => _onDigitPressed('0')),
            _buildKeyButton(
              icon: Icons.backspace_outlined,
              onTap: _onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      // 讀取密碼中的小過場
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // 背景：和登入頁同風格的藍綠漸層
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6BC8D4),
                  Color(0xFF7F8FD7),
                ],
              ),
            ),
          ),

          // 柔光圓形（上右）
          Positioned(
            top: -80,
            right: -40,
            child: _blurBall(200, const Color(0x66FFFFFF)),
          ),

          // 柔光圓形（下左）
          Positioned(
            bottom: -60,
            left: -30,
            child: _blurBall(240, const Color(0x55FFFFFF)),
          ),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 盾牌＋鎖 icon（往下置中）
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.7),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: const [
                                Icon(
                                  Icons.shield_outlined, // 盾牌
                                  size: 44,
                                  color: Colors.white,
                                ),
                                Icon(
                                  Icons.lock_outline, // 鎖
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // 標題
                          Text(
                            '隱私鎖定',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // 說明文字
                          Text(
                            '為了保護你的日記與情緒紀錄，\n請輸入解鎖密碼。',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.4,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // 上方的 PIN 小圓點
                          _buildPinDots(),

                          const SizedBox(height: 8),

                          // loading 或錯誤訊息
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (_errorText != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _errorText!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          const SizedBox(height: 24),

                          // 下方數字鍵盤（用你原本的 _buildKeypad）
                          _buildKeypad(),

                          const SizedBox(height: 16),

                          TextButton.icon(
                            onPressed: _loading ? null : _handleForgotPin,
                            icon: const Icon(Icons.help_outline_rounded),
                            label: const Text('忘記解鎖密碼'),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  Colors.white.withValues(alpha: 0.94),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurBall(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
