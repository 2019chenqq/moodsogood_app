import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  const AnalyticsService._();

  static Future<void> logPage(String pageName) {
    return FirebaseAnalytics.instance.logScreenView(
      screenName: pageName,
      screenClass: pageName,
    );
  }

  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) {
    return FirebaseAnalytics.instance.setUserProperty(
      name: name,
      value: value,
    );
  }
}
