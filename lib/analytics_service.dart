import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  // Fixed events/parameters only: never pass summary content or free text.
  static Future<void> logFollowUpSummary(FollowUpSummaryEvent event) => _safely(
        () => analytics.logEvent(name: event.eventName),
      );

  static Future<void> logFollowUpFeedback(bool shownToDoctor) => _safely(
        () => analytics.logEvent(
          name: 'followup_summary_feedback_submitted',
          // Firebase Analytics accepts strings/numbers, not Dart bools.
          parameters: {'shown_to_doctor': shownToDoctor ? 'true' : 'false'},
        ),
      );
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

  static Future<void> logAiFeatureOpen({required String aiMode}) async {
    await _safely(
      () => analytics.logEvent(
        name: 'ai_feature_open',
        parameters: {
          'ai_mode': aiMode,
          'platform': platform,
        },
      ),
    );
  }

  static Future<void> logAiTaskStart({required String aiMode}) async {
    await _safely(
      () => analytics.logEvent(
        name: 'ai_task_start',
        parameters: {
          'ai_mode': aiMode,
          'platform': platform,
        },
      ),
    );
  }

  static Future<void> logAiTaskComplete({required String aiMode}) async {
    await _safely(
      () => analytics.logEvent(
        name: 'ai_task_complete',
        parameters: {
          'ai_mode': aiMode,
          'platform': platform,
        },
      ),
    );
  }

  static Future<void> logAiTaskError({
    required String aiMode,
    required String errorType,
  }) async {
    await _safely(
      () => analytics.logEvent(
        name: 'ai_task_error',
        parameters: {
          'ai_mode': aiMode,
          'error_type': errorType,
          'platform': platform,
        },
      ),
    );
  }
}

enum FollowUpSummaryEvent {
  generated('followup_summary_generated'),
  opened('followup_summary_opened'),
  pdfExported('followup_summary_pdf_exported'),
  qrCreated('followup_summary_qr_created');

  const FollowUpSummaryEvent(this.eventName);
  final String eventName;
}
