// lib/app_globals.dart
import 'package:flutter/material.dart';

// 全域用的 ScaffoldMessenger Key
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// 導航用的 GlobalKey，方便從通知點擊時直接導向特定頁面
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();