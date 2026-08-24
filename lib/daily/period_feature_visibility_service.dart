import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/health_data_encryption_service.dart';

class PeriodFeatureVisibilityService {
  PeriodFeatureVisibilityService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Period features are hidden only when the profile explicitly says male.
  /// Missing or temporarily unavailable profile data must not hide the option.
  static bool shouldShowForSex(String? sexAssignedAtBirth) =>
      sexAssignedAtBirth?.trim() != '男性';

  Future<bool> shouldShowForCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      final userRef = _firestore.collection('users').doc(uid);
      final results = await Future.wait([
        userRef.get(),
        userRef.collection('healthProfile').doc('current').get(),
      ]);
      final profile = results[0].data() ?? const <String, dynamic>{};
      final healthSnapshot = results[1];
      final healthData = healthSnapshot.data() == null
          ? const <String, dynamic>{}
          : await HealthDataEncryptionService.decryptData(
              healthSnapshot.data()!,
            );
      final sex =
          (healthData['sexAssignedAtBirth'] ?? profile['sexAssignedAtBirth'])
              ?.toString();
      return shouldShowForSex(sex);
    } catch (error) {
      debugPrint('Period feature visibility check failed: $error');
      return true;
    }
  }
}
