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
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '這裡很安全，\n只有你能打開。',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '輸入解鎖密碼，\n讓日記只為你保留位置。',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    _buildPinDots(),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                    _buildKeypad(),
                    const Spacer(),
                    const Text(
                      '＊忘記密碼的話，只能刪除 App 重裝（雲端資料還在）',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
