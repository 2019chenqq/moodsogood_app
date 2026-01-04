import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sign_in_page.dart';
import '../daily/daily_record_screen.dart'; // 你的主畫面

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 還在判斷登入狀態
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 已登入 → 主畫面
        if (snapshot.hasData) {
          return const DailyRecordScreen();
        }

        // 未登入 → 登入頁
        return const SignInPage();
      },
    );
  }
}
