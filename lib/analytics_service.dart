import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
  static final Set<String> _loggedPurchaseIds = <String>{};

  static String get platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static Future<void> _safely(Future<void> Function() log) async {
    try {
      await log();
    } catch (error) {
      debugPrint('Analytics event failed: $error');
    }
  }

  static Future<void> logScreenView({
    required String screenName,
  }) async {
    await _safely(
      () => analytics.logScreenView(
        screenName: screenName,
        screenClass: screenName,
      ),
    );
  }

  static Future<void> logPage(String name) async {
    await logScreenView(screenName: name);
  }

  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    await _safely(
      () => analytics.setUserProperty(
        name: name,
        value: value,
      ),
    );
  }

  static Future<void> logProPageView({String source = 'unknown'}) async {
    await _safely(
      () => analytics.logEvent(
        name: 'pro_page_view',
        parameters: {
          'source': source.trim().isEmpty ? 'unknown' : source,
          'platform': platform,
        },
      ),
    );
  }

  static Future<void> logPurchaseClick({
    required String productId,
    required double price,
    required String currency,
  }) async {
    await _safely(
      () => analytics.logEvent(
        name: 'purchase_click',
        parameters: {
          'product_id': productId,
          'price': price,
          'currency': currency,
          'platform': platform,
        },
      ),
    );
  }

  static Future<void> logPurchase({
    required String transactionId,
    required double value,
    required String currency,
    required String productId,
  }) async {
    if (transactionId.isEmpty || _loggedPurchaseIds.contains(transactionId)) {
      return;
    }

    var logged = false;
    await _safely(() async {
      await analytics.logPurchase(
        transactionId: transactionId,
        value: value,
        currency: currency,
        parameters: {'product_id': productId},
      );
      logged = true;
    });
    if (logged) _loggedPurchaseIds.add(transactionId);
  }

  static Future<void> logPurchaseError({
    required String productId,
    required String errorCode,
    required String errorStage,
  }) async {
    await _safely(
      () => analytics.logEvent(
        name: 'purchase_error',
        parameters: {
          'product_id': productId.isEmpty ? 'unknown' : productId,
          'error_code': errorCode,
          'error_stage': errorStage,
          'platform': platform,
        },
      ),
    );
  }
}
