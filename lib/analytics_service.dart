import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  static Future<void> logScreenView({
    required String screenName,
  }) async {
    await FirebaseAnalytics.instance.logScreenView(
      screenName: screenName,
      screenClass: screenName,
    );
  }

  static Future<void> logPage(String name) async {
    await logScreenView(screenName: name);
  }

  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    await FirebaseAnalytics.instance.setUserProperty(
      name: name,
      value: value,
    );
  }
}
