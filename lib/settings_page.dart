import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 需要安裝這個來存設定
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'utils/notification_helper.dart';
import 'providers/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _appLockEnabled = false;
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  bool _isReminderOn = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 22, minute: 0); // 預設晚上 10 點
@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          if (kDebugMode)
  ElevatedButton(
    onPressed: () async {
      await NotificationHelper().showNow(
        id: 999,
        title: '測試通知',
        body: '這是一則測試通知（立刻跳出）',
      );
    },
    child: const Text('測試通知（立刻跳出）'),
  ),
          SwitchListTile(
            title: const Text('每日提醒'),
            subtitle: Text(_isReminderOn 
                ? '將於每天 ${_reminderTime.format(context)} 提醒' 
                : '提醒已關閉'),
            value: _isReminderOn,
            onChanged: (val) {
              _updateSettings(val, _reminderTime);
            },
          ),
          if (_isReminderOn)
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('提醒時間'),
              trailing: Text(
                _reminderTime.format(context),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _reminderTime,
                );
                if (picked != null) {
                  _updateSettings(true, picked);
                }
              },
            ),
            const Divider(), // 分隔線
          
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('外觀', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('跟隨系統'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('淺色模式'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('深色模式 🌙'),
                        ),
                      ],
                      selected: {themeProvider.themeMode},
                      onSelectionChanged: (selection) {
                        final mode = selection.first;
                        themeProvider.setTheme(mode);
                      },
                    ),
                  ),
                const Divider(),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('隱私', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),

          SwitchListTile(
            title: const Text('啟用 App 密碼鎖定'),
            subtitle: const Text('打開 App 時需要輸入密碼才能查看日記'),
            value: _appLockEnabled,
            onChanged: (val) async {
              if (val) {
                // 開啟時先設定一組密碼
                final ok = await _showSetPinDialog();
                if (ok) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('appLockEnabled', true);
                  setState(() => _appLockEnabled = true);
                }
              } else {
                // 關閉鎖定
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('appLockEnabled', false);
                // 可以選擇是否刪除密碼
                // await prefs.remove('appLockPin');
                setState(() => _appLockEnabled = false);
              }
            },
          ),

          if (_appLockEnabled)
            ListTile(
  leading: const Icon(Icons.password),
  title: const Text('變更解鎖密碼'),
  subtitle: const Text('修改打開 App 時使用的解鎖密碼'),
  enabled: _appLockEnabled,                 // 只有開啟密碼鎖定時才能按
  onTap: _appLockEnabled ? _showChangePinDialog : null,
),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 讀取設定 (這裡建議加裝 shared_preferences 套件)
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isReminderOn = prefs.getBool('isReminderOn') ?? false;
      final h = prefs.getInt('reminderHour') ?? 22;
      final m = prefs.getInt('reminderMinute') ?? 0;
      _reminderTime = TimeOfDay(hour: h, minute: m);
      _appLockEnabled = prefs.getBool('appLockEnabled') ?? false;
    });
  }

  // 儲存並設定通知
Future<void> _updateSettings(bool isOn, TimeOfDay time) async {
  // 1. 更新畫面上的開關與時間
  setState(() {
    _isReminderOn = isOn;
    _reminderTime = time;
  });

  // 2. 儲存設定
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isReminderOn', isOn);
  await prefs.setInt('reminderHour', time.hour);
  await prefs.setInt('reminderMinute', time.minute);

  // 3. 初始化通知（保險再呼叫一次）
  final helper = NotificationHelper();
  await helper.init();

  if (!mounted) return;

  // 4. 要求權限
  final platform = helper.notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (platform != null) {
    await platform.requestExactAlarmsPermission();
    await platform.requestNotificationsPermission();
  }

//   // 5. 根據開關決定行為
  if (isOn) {
    // 先取消舊的，避免重複排
    await helper.cancelNotification(1);

    // 檢查權限是否真的被授予
    final android = helper.notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final notifEnabled = await android?.areNotificationsEnabled() ?? false;
    debugPrint('🔔 通知已啟用: $notifEnabled');


    if (!notifEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 需要允許通知權限才能使用提醒功能'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

//     // 🕐 若設定時間已過，改成明天
    final now = TimeOfDay.now();
    bool isAfterNow = time.hour > now.hour ||
        (time.hour == now.hour && time.minute > now.minute);
    final adjustedTime = isAfterNow
        ? time
        : TimeOfDay(hour: (time.hour + 24) % 24, minute: time.minute);

    // 使用 WorkManager（適用於小米等嚴格系統）
    final success = await helper.scheduleDailyNotificationWithWorkManager(
      time: adjustedTime,
      payload: '/home',
    );

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final adjustedTimeLabel = adjustedTime.format(context);

    debugPrint('✅ 已建立每日提醒（WorkManager）：$adjustedTimeLabel');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success 
            ? '已設定每日提醒：$adjustedTimeLabel ✅\n' 
            : '設定提醒失敗，請檢查權限'
        ),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );
  } else {
    // 關閉提醒
    await helper.cancelDailyNotificationWithWorkManager();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已關閉每日提醒 ❎')),
      );
    }
  }
  }
  Future<bool> _showSetPinDialog() async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('設定解鎖密碼'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '密碼（6 位數字）',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: '再次輸入密碼',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final pin = pinController.text.trim();
                    final confirm = confirmController.text.trim();

                    if (pin.length < 4 || pin.length > 6) {
                      setState(() {
                        error = '請輸入 6 位數字密碼';
                      });
                      return;
                    }
                    if (pin != confirm) {
                      setState(() {
                        error = '兩次輸入的密碼不一致';
                      });
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('appLockPin', pin);

                    if (!mounted) return;

                    navigator.pop(true);
                  },
                  child: const Text('確認'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }
  Future<void> _showChangePinDialog() async {
  final prefs = await SharedPreferences.getInstance();
  // ⚠️ 一定要用 app_lock_screen.dart 裡用的同一個 key
  final savedPin = prefs.getString('appLockPin') ?? '';

  if (!mounted) return;

  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('變更解鎖密碼'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _oldPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '目前密碼',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '新密碼（6 位數）',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '再次輸入新密碼',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _oldPinController.clear();
                  _newPinController.clear();
                  _confirmPinController.clear();
                  Navigator.of(context).pop();
                },
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final oldPin = _oldPinController.text.trim();
                  final newPin = _newPinController.text.trim();
                  final confirmPin = _confirmPinController.text.trim();

                  // 1. 已經有舊密碼時，要先驗證
                  if (savedPin.isNotEmpty && oldPin != savedPin) {
                    setState(() => errorText = '目前密碼輸入錯誤');
                    return;
                  }

                  // 2. 新密碼不能空白
                  if (newPin.isEmpty) {
                    setState(() => errorText = '新密碼不能為空白');
                    return;
                  }

                  // 3. 兩次新密碼要一樣
                  if (newPin != confirmPin) {
                    setState(() => errorText = '兩次輸入的新密碼不一致');
                    return;
                  }

                  // 4. 寫回 SharedPreferences（跟 AppLockScreen 用同一個 key）
                  await prefs.setString('appLockPin', newPin);

                  _oldPinController.clear();
                  _newPinController.clear();
                  _confirmPinController.clear();

                  if (!mounted) return;

                  navigator.pop();

                  messenger.showSnackBar(
                    const SnackBar(content: Text('解鎖密碼已更新')),
                  );
                },
                child: const Text('儲存'),
              ),
            ],
          );
        },
      );
    },
  );
}
}