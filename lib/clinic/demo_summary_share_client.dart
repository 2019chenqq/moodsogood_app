import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'demo_sleep_share_client.dart';

/// Patient consent only. No source data, real repository or AI provider access.
class DemoSummaryShareClient {
  DemoSummaryShareClient(this.auth, this.functions) {
    DemoSleepShareClient(auth, functions);
  }
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  Future<void> _call(String name, String clinicId, {bool openAi = false}) async {
    if (auth.currentUser == null || auth.currentUser!.isAnonymous) {
      throw StateError('Signed-in synthetic patient required');
    }
    await functions.httpsCallable(name).call({
      'clinicId': clinicId,
      if (name == 'demoSummaryConsent') 'consentVersion': 1,
      if (openAi) 'provider': 'openai',
    });
  }

  Future<void> consent(String clinicId) =>
      _call('demoSummaryConsent', clinicId);
  Future<void> consentOpenAi(String clinicId) =>
      _call('demoSummaryConsent', clinicId, openAi: true);
  Future<void> revoke(String clinicId) => _call('demoRevokeSummary', clinicId);
}
