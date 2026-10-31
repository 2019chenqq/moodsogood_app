import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'clinic/demo_sleep_share_client.dart';
import 'clinic/demo_health_event_share_client.dart';
import 'clinic/demo_check_in_share_client.dart';
import 'clinic/demo_medication_share_client.dart';
import 'clinic/demo_daily_record_share_client.dart';
import 'clinic/demo_summary_share_client.dart';

/// Separate entry point: never imports production Firebase options or health data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const apiKey = String.fromEnvironment('DEMO_FIREBASE_API_KEY');
  const appId = String.fromEnvironment('DEMO_FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('DEMO_FIREBASE_SENDER_ID');
  const siteKey = String.fromEnvironment('DEMO_APP_CHECK_SITE_KEY');
  if ([apiKey, appId, senderId, siteKey].any((v) => v.isEmpty)) {
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text('請先設定隔離 demo 的 Firebase 與 App Check 公開設定。')))));
    return;
  }
  final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: 'innera-demo',
    authDomain: 'innera-demo.firebaseapp.com',
  ));
  await FirebaseAppCheck.instanceFor(app: app).activate(
    webProvider: ReCaptchaEnterpriseProvider(siteKey),
  );
  runApp(MaterialApp(
      home: DemoSleepPatientPage(
    auth: FirebaseAuth.instanceFor(app: app),
    functions: FirebaseFunctions.instanceFor(app: app, region: 'us-central1'),
  )));
}

class DemoSleepPatientPage extends StatefulWidget {
  const DemoSleepPatientPage(
      {super.key, required this.auth, required this.functions});
  final FirebaseAuth auth;
  final FirebaseFunctions functions;
  @override
  State<DemoSleepPatientPage> createState() => _DemoSleepPatientPageState();
}

class _DemoSleepPatientPageState extends State<DemoSleepPatientPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool consent = false;
  bool healthConsent = false;
  bool checkConsent = false;
  bool medicationConsent = false;
  bool dailyConsent = false;
  bool summaryConsent = false;
  bool openAiConsent = false;
  bool busy = false;
  String message = '';
  static const clinic = String.fromEnvironment('DEMO_CLINIC_ID',
      defaultValue: 'demo-sleep-clinic');

  Future<void> perform(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
    } catch (_) {
      if (mounted) setState(() => message = '操作未完成，請確認帳號、授權與 demo 設定。');
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('睡眠分享測試（只有假資料）')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              '此入口只分享三筆假睡眠、兩筆假 HealthEvent 、兩筆假 Check-in 、三筆假 Medication 及兩筆新假 dailyRecords，不讀取你的健康資料。'),
          TextField(
              controller: email,
              decoration: const InputDecoration(labelText: '測試患者 Email')),
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密碼')),
          FilledButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await widget.auth.signInWithEmailAndPassword(
                            email: email.text.trim(), password: password.text);
                      }, '已登入測試帳號'),
              child: const Text('登入')),
          CheckboxListTile(
              value: consent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => consent = value ?? false),
              title: Text('我同意將三筆假睡眠紀錄分享給 $clinic 的有效醫師，可隨時撤銷。')),
          FilledButton(
              onPressed: busy || !consent
                  ? null
                  : () => perform(
                      () => DemoSleepShareClient(widget.auth, widget.functions)
                          .shareSyntheticSleep(clinic),
                      '已加密分享三筆假資料'),
              child: const Text('同意並分享')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoSleepShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        consent = false;
                      }, '已撤銷，後續讀取已阻擋'),
              child: const Text('撤銷睡眠分享')),
          const Divider(),
          const Text('HealthEvent 合成測試（不是您的真實事件）'),
          CheckboxListTile(
              value: healthConsent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => healthConsent = value ?? false),
              title: Text('我同意分享兩筆假 HealthEvent 給 $clinic 的有效醫師，可隨時撤銷。')),
          FilledButton(
              onPressed: busy || !healthConsent
                  ? null
                  : () => perform(
                      () => DemoHealthEventShareClient(
                              widget.auth, widget.functions)
                          .shareSynthetic(clinic),
                      '已加密分享兩筆假 HealthEvent'),
              child: const Text('同意並分享假 HealthEvent')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoHealthEventShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        healthConsent = false;
                      }, 'HealthEvent 已撤銷，後續讀取已阻擋'),
              child: const Text('撤銷 HealthEvent 分享')),
          const Divider(),
          const Text('Check-in 合成測試（不是您的真實每日狀態）'),
          CheckboxListTile(
              value: checkConsent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => checkConsent = value ?? false),
              title: Text('我同意分享兩筆假 Check-in 給 $clinic 的有效醫師，可獨立撤銷。')),
          FilledButton(
              onPressed: busy || !checkConsent
                  ? null
                  : () => perform(
                      () =>
                          DemoCheckInShareClient(widget.auth, widget.functions)
                              .shareSynthetic(clinic),
                      '已加密分享兩筆假 Check-in'),
              child: const Text('同意並分享假 Check-in')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoCheckInShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        checkConsent = false;
                      }, 'Check-in 已撤銷，其他分享不受影響'),
              child: const Text('撤銷 Check-in 分享')),
          const Divider(),
          const Text('Medication 合成測試（不是您的真實用藥）'),
          CheckboxListTile(
              value: medicationConsent,
              onChanged: busy
                  ? null
                  : (value) =>
                      setState(() => medicationConsent = value ?? false),
              title:
                  Text('我同意分享三筆假 Medication（口服／需要時／注射）給 $clinic 的有效醫師，可獨立撤銷。')),
          FilledButton(
              onPressed: busy || !medicationConsent
                  ? null
                  : () => perform(
                      () => DemoMedicationShareClient(
                              widget.auth, widget.functions)
                          .shareSynthetic(clinic),
                      '已加密分享三筆假 Medication'),
              child: const Text('同意並分享假 Medication')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoMedicationShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        medicationConsent = false;
                      }, 'Medication 已撤銷，其他分享不受影響'),
              child: const Text('撤銷 Medication 分享')),
          const Divider(),
          const Text('dailyRecords 新 synthetic 測試（不讀取或轉換歷史紀錄）'),
          CheckboxListTile(
              value: dailyConsent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => dailyConsent = value ?? false),
              title: Text('我同意分享兩筆新假 dailyRecords 給 $clinic 的有效醫師，可獨立撤銷。')),
          FilledButton(
              onPressed: busy || !dailyConsent
                  ? null
                  : () => perform(
                      () => DemoDailyRecordShareClient(
                              widget.auth, widget.functions)
                          .shareSynthetic(clinic),
                      '已加密分享兩筆新假 dailyRecords'),
              child: const Text('同意並分享新假 dailyRecords')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoDailyRecordShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        dailyConsent = false;
                      }, 'dailyRecords 已撤銷，其他分享不受影響'),
              child: const Text('撤銷 dailyRecords 分享')),
          const Divider(),
          const Text('加密模擬摘要（固定規則，不呼叫任何外部 AI）'),
          CheckboxListTile(
              value: summaryConsent,
              onChanged: busy
                  ? null
                  : (value) => setState(() => summaryConsent = value ?? false),
              title: Text('我同意 $clinic 的有效醫師，使用仍授權的五種假資料產生及查看加密模擬摘要。')),
          FilledButton(
              onPressed: busy || !summaryConsent
                  ? null
                  : () => perform(
                      () =>
                          DemoSummaryShareClient(widget.auth, widget.functions)
                              .consent(clinic),
                      '已同意模擬摘要；請在醫師端明確產生／更新摘要'),
              child: const Text('同意模擬摘要')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await DemoSummaryShareClient(
                                widget.auth, widget.functions)
                            .revoke(clinic);
                        summaryConsent = false;
                      }, '已撤銷模擬摘要；五種原始分享不受影響'),
              child: const Text('撤銷模擬摘要')),
          const Divider(),
          CheckboxListTile(
              value: openAiConsent,
              onChanged: busy ? null : (value) => setState(() => openAiConsent = value ?? false),
              title: const Text('OpenAI 假資料驗收：我同意將仍授權假資料的最小化統計送至 OpenAI；不送備註或身份。撤銷不能保證抹除已送出的請求。最多每日兩次呼叫。')),
          FilledButton(
              onPressed: busy || !openAiConsent ? null : () => perform(
                  () => DemoSummaryShareClient(widget.auth, widget.functions).consentOpenAi(clinic),
                  '已同意 OpenAI 假資料驗收；醫師下次讀取會生成加密摘要'),
              child: const Text('同意 OpenAI 假資料驗收')),
          TextButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                        await widget.auth.signOut();
                        consent = false;
                        healthConsent = false;
                        checkConsent = false;
                        medicationConsent = false;
                        dailyConsent = false;
                        summaryConsent = false;
                        openAiConsent = false;
                      }, '已登出'),
              child: const Text('登出')),
          Text(message),
        ]),
      );
}
