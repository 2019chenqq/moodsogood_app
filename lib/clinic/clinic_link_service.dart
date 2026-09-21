import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClinicLinkResult {
  const ClinicLinkResult({
    required this.patientId,
    required this.clinicId,
    required this.legalName,
  });

  final String patientId;
  final String clinicId;
  final String legalName;
}

class ClinicLinkService {
  ClinicLinkService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<ClinicLinkResult> redeemInvite(String rawCode) async {
    final user = _auth.currentUser;

    if (user == null || user.isAnonymous) {
      throw StateError('請先登入心域帳號。');
    }

    final code = rawCode.trim().toUpperCase();

    if (code.isEmpty) {
      throw ArgumentError('請輸入邀請碼。');
    }

    final response = await _functions
        .httpsCallable('redeemClinicInvite')
        .call<Map<String, dynamic>>({'code': code});
    final data = response.data;
    return ClinicLinkResult(
      patientId: data['patientId'] as String,
      clinicId: data['clinicId'] as String,
      legalName: data['legalName'] as String,
    );
  }
}
