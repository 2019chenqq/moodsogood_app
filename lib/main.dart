import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// Firebase + Google Sign-In
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

import 'Sign_in_page.dart';
import 'app_globals.dart';
import 'utils/notification_helper.dart';
import 'utils/firebase_sync_config.dart';
import 'providers/theme_provider.dart';
import 'providers/firebase_sync_provider.dart';
import 'daily/daily_record_screen.dart';
import 'pages/hub_pages.dart';
import 'daily/daily_record_repository.dart';
import 'app_lock_screen.dart';
import 'service/iap_service.dart';
import 'providers/pro_provider.dart';
import 'PDF/pdf_export_provider.dart'; // 引入 PDFExportProvider
import 'utils/data_migration.dart';
import 'UI/fortune_cookie_screen.dart';
import 'community/providers/rooms_provider.dart';
import 'community/community_home_page.dart';
import 'community/room_page.dart';
import 'community/post_detail_page.dart';
import 'community/compose_post_page.dart';
import 'onboarding_page.dart';
import 'utils/secure_storage_service.dart';
import 'pin_setup_screen.dart';
/* =========================== main =========================== */

Future<void> main() async {
  debugPrint('🚀 App startup starting...');

  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager
      .initialize(); // :contentReference[oaicite:3]{index=3}

  debugPrint('🔥 Firebase initializing...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('✅ Firebase initialized');

  // 先載入主題設定
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  debugPrint('🎨 Theme loaded');

  // Initialize Firebase Sync Config
  await FirebaseSyncConfig().init();
  debugPrint('📡 Firebase Sync Config initialized');

  // Initialize Daily Record Repository
  await DailyRecordRepository().init();
  debugPrint('💾 Daily Record Repository initialized');

  // ⭐ 啟動時初始化通知（會印出 🕐 這行）
  await NotificationHelper().init();
  debugPrint('🔔 Notifications initialized');

  // Only init IAP on release builds (skip on emulator/debug)
  //  Ted add this for testing inapp purchase on emulator
  if (!kDebugMode) {
    await IAPService.instance.init();
    debugPrint('🛍️ IAP Service initialized');
  }
  debugPrint('📱 Running app...');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
        ),
        ChangeNotifierProvider<FirebaseSyncProvider>(
          create: (_) => FirebaseSyncProvider()..init(),
        ),
        ChangeNotifierProvider<ProProvider>(
          create: (_) => ProProvider()..init(),
        ),
        ChangeNotifierProvider<PDFExportProvider>(
          create: (_) => PDFExportProvider(),
        ),
        ChangeNotifierProvider<RoomsProvider>(
          create: (_) => RoomsProvider(),
        ),
      ],
      child: const MainApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 在應用初始化後，註冊 Pro 狀態回調和升級回調
    final globalContext = rootNavigatorKey.currentContext;
    if (globalContext != null) {
      final proProvider =
          Provider.of<ProProvider>(globalContext, listen: false);
      final repository = DailyRecordRepository();

      // 🔧 修復：正確設置 Pro 狀態回調，讓 Firebase 同步與本地存儲保持同步
      FirebaseSyncConfig.setProStatusCallback(() {
        debugPrint('📡 Checking Pro status: ${proProvider.isPro}');
        return proProvider.isPro;
      });

      // 📱 應用啟動時：如果是 Pro 用戶，自動同步本地數據到 Firebase
      Future.delayed(const Duration(milliseconds: 500), () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && proProvider.isPro) {
          debugPrint(
              '🔄 Pro user detected - syncing local data to Firebase...');
          try {
            // final result = await DataMigration().migrateLocalToFirebase(
            //   userId: user.uid,
            //   repository: repository,
            // );
            // debugPrint('✅ 應用啟動同步完成: $result');
          } catch (e) {
            debugPrint('⚠️  應用啟動同步失敗: $e');
          }
        }
      });

      proProvider.setOnUpgradeCallback(() async {
        // 升級時自動遷移本地數據到 Firebase
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // final result = await DataMigration().migrateLocalToFirebase(
          //   userId: user.uid,
          //   repository: repository,
          // );
          // debugPrint('📊 用戶升級 - 數據遷移結果: $result');
        }
      });
    }

    NotificationHelper().processPendingNavigation();
  });
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootMessengerKey,
      debugShowCheckedModeBanner: false,

      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // 淺色主題
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'LXGWWenKai',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 154, 170, 221),
          brightness: Brightness.light,
        ),
      ),

      // 深色主題
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF80CBC4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'LXGWWenKai',
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Colors.grey.shade600),
        ),
      ),

      // 關鍵：跟著 ThemeProvider 切換
      themeMode: themeProvider.themeMode,
      routes: {
        CommunityHomePage.routeName: (_) => const CommunityHomePage(),
        RoomPage.routeName: (_) => const RoomPage(),
        PostDetailPage.routeName: (_) => const PostDetailPage(),
        ComposePostPage.routeName: (_) => const ComposePostPage(),
      },

      home: const FirstLaunchGate(),
    );
  }
}

class FirstLaunchGate extends StatefulWidget {
  const FirstLaunchGate({super.key});

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  bool _ready = false;
  bool _openingOnboarding = false;
  bool _postOnboardingToRecordHub = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('has_seen_onboarding') ?? false;

    if (!seen && !_openingOnboarding) {
      _openingOnboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final result = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const OnboardingPage()),
        );
        if (!mounted) return;
        setState(() {
          _postOnboardingToRecordHub = result == true;
          _ready = true;
        });
      });
      return;
    }

    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_postOnboardingToRecordHub) {
      // 導覽結束後仍需經過登入流程，避免直接進入主頁造成「無法登出／看不到 Google 登入」
      return const AuthGate();
    }

    return FortuneCookieScreen(
      onEnterApp: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthGate()),
        );
      },
    );
  }
}

/* =========================== Auth Gate =========================== */
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('首頁')),
      body: const Center(child: Text('登入成功')),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) {
          return const SignInPage(); // 未登入
        }
        // 👇 把原本的 return const LockWrapper(); 改成這行 👇
        return const EncryptionGate(); // 已登入，先檢查端到端加密金鑰
      },
    );
  }
}

/* =========================== Login =========================== */
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      if (kIsWeb) {
        // Web 版：用 popup
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
        return;
      }

      // Android/iOS
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // 使用者取消

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      // 登入成功後，authStateChanges() 會讓 AuthGate 自動切到 HomePage
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('登入失敗：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, size: 72, color: Colors.teal[200]),
                const SizedBox(height: 12),
                Text('心域', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _signInWithGoogle(context),
                  icon: const Icon(Icons.login),
                  label: const Text('使用 Google 登入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LockWrapper extends StatefulWidget {
  const LockWrapper({super.key});

  @override
  State<LockWrapper> createState() => _LockWrapperState();
}

class _LockWrapperState extends State<LockWrapper> {
  bool _loading = true;
  bool _needLock = false;

  @override
  void initState() {
    super.initState();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('appLockEnabled') ?? false;
    setState(() {
      _needLock = enabled;
      _loading = false;
    });
  }

  void _onUnlocked() {
    setState(() {
      _needLock = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_needLock) {
      return AppLockScreen(onUnlocked: _onUnlocked);
    }

    // ✅ 解鎖後，或沒開啟鎖定，就進入紀錄首頁
    return const RecordHubPage();
  }
}
/* =========================== Encryption Gate (端到端加密守門員) =========================== */
class EncryptionGate extends StatefulWidget {
  const EncryptionGate({super.key});

  @override
  State<EncryptionGate> createState() => _EncryptionGateState();
}

class _EncryptionGateState extends State<EncryptionGate> {
  bool _loading = true;
  bool _hasKey = false;
  bool _e2eConfigured = false;

  @override
  void initState() {
    super.initState();
    _checkEncryptionKey();
  }

  Future<void> _checkEncryptionKey() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = (prefs.getBool('e2eConfigured') ?? false) ||
        (prefs.getString('e2ePin')?.isNotEmpty ?? false);

    // 去手機的硬體保險箱找鑰匙
    final key = await SecureStorageService.getOrRecoverKey();
    if (mounted) {
      setState(() {
        _hasKey = (key != null);
        _e2eConfigured = configured;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasKey && !_e2eConfigured) {
      // 找不到保險箱金鑰，代表是剛下載的新用戶，或是剛更新的舊用戶
      // 強制進入設定 6 位數安全碼的畫面！
      return const PinSetupScreen();
    }

    // 金鑰確認無誤！放行進入原本的 App 鎖檢查與首頁
    return const LockWrapper();
  }
}