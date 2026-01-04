import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Firebase + Google Sign-In
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';


import 'Home_shell.dart';
import 'Sign_in_page.dart';
import 'app_globals.dart';
import 'utils/notification_helper.dart';
import 'providers/theme_provider.dart';
import 'diary/diary_home_page.dart';
import 'daily/daily_record_screen.dart';
import 'providers/menu_provider.dart';
import 'app_lock_screen.dart';
import 'service/iap_service.dart';
import 'providers/pro_provider.dart';
/* =========================== main =========================== */

final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 先載入主題設定
  final themeProvider = ThemeProvider();
  await themeProvider.loadTheme();

  // ⭐ 啟動時初始化通知（會印出 🕐 這行）
  await NotificationHelper().init();

  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await IAPService.instance.init();

  runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
      ),
      ChangeNotifierProvider<ProProvider>(
        create: (_) => ProProvider()..init(),
      ),
    ],
    child: const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthGate(), // ⭐ 唯一入口（不用改）
    ),
  ),
);
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF80CBC4),
          brightness: Brightness.light,
        ),
      ),

      // 深色主題（你之前設計的那套）
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF80CBC4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
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

      home: const LockWrapper(),
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) {
          return const SignInPage();      // 未登入
        }
        return const DailyRecordScreen();         // 已登入
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
                Text('心晴 Heart shine',
                    style: Theme.of(context).textTheme.headlineSmall),
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

    // ✅ 解鎖後，或沒開啟鎖定，就照原本流程進 AuthGate
    return const AuthGate();
  }
}