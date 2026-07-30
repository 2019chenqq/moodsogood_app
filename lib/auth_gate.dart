import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sign_in_page.dart';
import 'Home_shell.dart'; // 你的主畫面
import 'onboarding_page.dart'; // 初次使用導覽頁

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<bool> _hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_seen_onboarding') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        debugPrint(
          '🔍 AuthGate - Connection: ${snapshot.connectionState}, '
          'HasData: ${snapshot.hasData}, HasError: ${snapshot.hasError}',
        );

        // 還在判斷登入狀態
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 已登入 → 檢查是否需要顯示導覽頁
        if (snapshot.hasData) {
          debugPrint('✅ User logged in');
          return FutureBuilder<bool>(
            future: _hasSeenOnboarding(),
            builder: (context, onboardingSnapshot) {
              if (onboardingSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // 如果沒有看過導覽頁，先顯示導覽頁
              if (onboardingSnapshot.data == false) {
                return const OnboardingPage();
              }

              // 已看過導覽頁，顯示主應用
              return const HomeShell();
            },
          );
        }

        // 未登入 → 登入頁
        debugPrint('❌ User not logged in');
        return const SignInPage();
      },
    );
  }
}
