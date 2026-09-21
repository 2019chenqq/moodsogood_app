// clinic_link_example.dart
//
// 這段不是完整頁面，只示範「確認連結」按鈕該怎麼接。
// 成功後再呼叫你現有的 ClinicalShareService，把近 7 日睡眠同步給該院所。
import 'package:flutter/foundation.dart';

import 'clinic_link_service.dart';
import 'clinical_share_service.dart';



Future<void> redeemClinicInvite(String code) async {
  final result = await ClinicLinkService().redeemInvite(code);

  // 你現有的服務已支援 clinicId。
  await ClinicalShareService().syncRecentSleepRecords(
    clinicId: result.clinicId,
    days: 7,
  );

  // 如果要一起測藥物，取消下面註解：
  // await ClinicalShareService().syncMedications(
  //   clinicId: result.clinicId,
  // );

  debugPrint(
    '連結成功：${result.legalName} / '
    '${result.patientId} / ${result.clinicId}',
  );
}
