import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  String? _savedPin;
  bool _initializing = true;

  Color get _primary => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _loadSavedPin();
  }

  Future<void> _loadSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ 這個 key 要跟你「設定 / 變更密碼」那邊用的一樣
    final pin = prefs.getString('appLockPin');

    if (!mounted) return;

    // 還沒設定過密碼 → 直接放行，不顯示鎖畫面
    if (pin == null || pin.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onUnlocked();
      });
      return;
    }

    setState(() {
      _savedPin = pin;
      _initializing = false;
    });
  }

  Future<void> _checkPin() async {
    if (_savedPin == null || _savedPin!.isEmpty) {
      // 理論上不會走到這裡，但保險再放一次
      widget.onUnlocked();
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    if (_input == _savedPin) {
      widget.onUnlocked();
    } else {
      setState(() {
        _loading = false;
        _errorText = '密碼錯誤，請再試一次';
        _input = '';
      });
    }
  }

  void _onDigitPressed(String digit) {
    if (_loading) return;
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
    if (_loading) return;
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _errorText = null;
    });
  }

  // ---------- 上方：簡單插畫感 header ----------
  Widget _buildHeader() {
  final bg = _primary.withOpacity(0.06);
  final circleBg = _primary.withOpacity(0.14);

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 鎖頭圓圈：置中
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: circleBg,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.lock_rounded,
                size: 34,
                color: _primary,
              ),
              Positioned(
                top: 14,
                right: 16,
                child: Icon(
                  Icons.shield_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 標題文字：置中
        const Text(
          '這裡很安全，\n只有你能打開。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        // 副標文字：置中
        Text(
          '輸入解鎖密碼，\n讓日記只為你保留位置。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
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
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
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
                              color: Colors.white.withOpacity(0.28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.7),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
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
                                Positioned(
                                  bottom: 18,
                                  child: Icon(
                                    Icons.lock_outline, // 鎖
                                    size: 22,
                                    color: Colors.white,
                                  ),
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
                              color: Colors.white.withOpacity(0.92),
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

                          // 忘記密碼提示（白色半透明）
                          Text(
                            '＊忘記密碼的話，只能刪除 App 重裝（雲端資料還在）',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.88),
                            ),
                            textAlign: TextAlign.center,
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
    );}
  }                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        