import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'clinical_share_service.dart';
import 'clinic_link_service.dart';

class ClinicalSharePage extends StatefulWidget {
  const ClinicalSharePage({super.key});

  @override
  State<ClinicalSharePage> createState() => _ClinicalSharePageState();
}

class _ClinicalSharePageState extends State<ClinicalSharePage> {
  String? _clinicId;
  final _service = ClinicalShareService();
  final TextEditingController _inviteCodeController =
    TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _sleepEnabled = false;
  bool _healthEventsEnabled = false;
  bool _dailyCheckInsEnabled = false;
  bool _medicationsEnabled = false;
  bool _linkingClinic = false;

  @override
  void initState() {
    super.initState();
    _loadSharingStatus();
  }

@override
void dispose() {
  _inviteCodeController.dispose();
  super.dispose();
}

  Future<void> _loadSharingStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return;
      if (_clinicId == null) {
        final links = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('clinicLinks')
            .where('status', isEqualTo: 'active')
            .get();
        final sortedLinks = links.docs.toList()
          ..sort((a, b) {
            final aTime = a.data()['linkedAt'];
            final bTime = b.data()['linkedAt'];
            return (bTime is Timestamp ? bTime.millisecondsSinceEpoch : 0)
                .compareTo(aTime is Timestamp ? aTime.millisecondsSinceEpoch : 0);
          });
        if (!mounted) return;
        if (sortedLinks.isNotEmpty) {
          _clinicId = sortedLinks.first.id;
        }
      }
      final clinicId = _clinicId;
      if (clinicId == null) return;
      final status = await Future.wait([
        _service.isSleepSharingEnabled(clinicId: clinicId),
        _service.isHealthEventSharingEnabled(clinicId: clinicId),
        _service.isDailyCheckInSharingEnabled(clinicId: clinicId),
        _service.isMedicationSharingEnabled(clinicId: clinicId),
      ]);
      if (!mounted) return;
      setState(() {
        _sleepEnabled = status[0];
        _healthEventsEnabled = status[1];
        _dailyCheckInsEnabled = status[2];
        _medicationsEnabled = status[3];
      });
    } catch (error) {
      _showMessage('讀取分享狀態失敗：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _changeSleep(bool enabled) async {
    final clinicId = _clinicId;
    if (clinicId == null || _linkingClinic) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        await _service.syncRecentSleepRecords(clinicId: clinicId, days: 30);
      } else {
        await _service.stopSharingSleep(clinicId: clinicId);
      }
      if (!mounted) return;
      setState(() => _sleepEnabled = enabled);
      _showMessage(enabled ? '已開啟睡眠資料分享' : '已停止分享睡眠資料');
    } catch (error) {
      _showMessage('更新睡眠分享失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeMedications(bool enabled) async {
    final clinicId = _clinicId;
    if (clinicId == null || _linkingClinic) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        await _service.syncMedications(clinicId: clinicId);
      } else {
        await _service.stopSharingMedications(clinicId: clinicId);
      }
      if (!mounted) return;
      setState(() => _medicationsEnabled = enabled);
      _showMessage(enabled ? '已開啟目前用藥分享' : '已停止分享目前用藥');
    } catch (error) {
      _showMessage('更新用藥分享失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeHealthEvents(bool enabled) async {
    final clinicId = _clinicId;
    if (clinicId == null || _linkingClinic) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        await _service.syncHealthEvents(clinicId: clinicId);
      } else {
        await _service.stopSharingHealthEvents(clinicId: clinicId);
      }
      if (!mounted) return;
      setState(() => _healthEventsEnabled = enabled);
      _showMessage(enabled ? '已開啟快速紀錄分享' : '已停止分享快速紀錄');
    } catch (error) {
      _showMessage('更新快速紀錄分享失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeDailyCheckIns(bool enabled) async {
    final clinicId = _clinicId;
    if (clinicId == null || _linkingClinic) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        await _service.syncDailyCheckIns(clinicId: clinicId);
      } else {
        await _service.stopSharingDailyCheckIns(clinicId: clinicId);
      }
      if (!mounted) return;
      setState(() => _dailyCheckInsEnabled = enabled);
      _showMessage(enabled ? '已開啟每日 Check-in 分享' : '已停止分享每日 Check-in');
    } catch (error) {
      _showMessage('更新每日 Check-in 分享失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncEnabledData() async {
    final clinicId = _clinicId;
    if (clinicId == null || _linkingClinic) return;
    setState(() => _busy = true);
    try {
      if (_sleepEnabled) {
        await _service.syncRecentSleepRecords(clinicId: clinicId, days: 30);
      }
      if (_healthEventsEnabled) {
        await _service.syncHealthEvents(clinicId: clinicId);
      }
      if (_dailyCheckInsEnabled) {
        await _service.syncDailyCheckIns(clinicId: clinicId);
      }
      if (_medicationsEnabled) {
        await _service.syncMedications(clinicId: clinicId);
      }
      _showMessage('已同步授權分享的資料');
    } catch (error) {
      _showMessage('同步失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

Future<void> _redeemInviteCode() async {
  final code = _inviteCodeController.text.trim();

  if (code.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('請輸入邀請碼'),
      ),
    );
    return;
  }

  setState(() {
    _linkingClinic = true;
  });

  try {
    final result =
        await ClinicLinkService().redeemInvite(code);

    if (!mounted) return;
    setState(() {
      _clinicId = result.clinicId;
      _sleepEnabled = false;
      _healthEventsEnabled = false;
      _dailyCheckInsEnabled = false;
      _medicationsEnabled = false;
    });

    // 先切換至剛連結的院所，再同步最近 30 天睡眠。
    try {
      await _service.syncRecentSleepRecords(
        clinicId: result.clinicId,
        days: 30,
      );
    } catch (error) {
      _showMessage('院所已連結，但睡眠同步失敗，請稍後重試：$error');
    }
    if (!mounted) return;
    await _loadSharingStatus();

    if (!mounted) return;

    _inviteCodeController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '連結成功：${result.legalName}（${result.patientId}）',
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('連結失敗：$e'),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _linkingClinic = false;
      });
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sharingDisabled = _busy || _linkingClinic || _clinicId == null;
    return Scaffold(
      appBar: AppBar(title: const Text('醫療資料分享')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _clinicId == null
                      ? '尚未連結院所，請先輸入邀請碼以啟用分享'
                      : '選擇要分享給醫療端的資料',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('睡眠資料'),
                        subtitle: const Text('分享最近 30 天的睡眠紀錄'),
                        value: _sleepEnabled,
                        onChanged: sharingDisabled ? null : _changeSleep,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('快速紀錄'),
                        subtitle: const Text('分享即時記錄的情緒、症狀與狀態'),
                        value: _healthEventsEnabled,
                        onChanged: sharingDisabled ? null : _changeHealthEvents,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('每日 Check-in'),
                        subtitle: const Text('分享每日整體情緒與身心狀態'),
                        value: _dailyCheckInsEnabled,
                        onChanged: sharingDisabled ? null : _changeDailyCheckIns,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('目前用藥'),
                        subtitle: const Text('分享目前使用中的藥物'),
                        value: _medicationsEnabled,
                        onChanged: sharingDisabled ? null : _changeMedications,
                      ),
                      Card(
  margin: const EdgeInsets.all(16),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '測試：連結醫療院所',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          '輸入醫療端產生的一次性邀請碼',
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: '邀請碼',
            hintText: '例如 YIK7DEU4G',
            border: OutlineInputBorder(),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                _linkingClinic || _busy ? null : _redeemInviteCode,
            child: Text(
              _linkingClinic
                  ? '連結中...'
                  : '確認連結',
            ),
          ),
        ),
      ],
    ),
  ),
)
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              _loading ||
                  sharingDisabled ||
                  (!_sleepEnabled &&
                      !_healthEventsEnabled &&
                      !_dailyCheckInsEnabled &&
                      !_medicationsEnabled)
                  ? null
                  : _syncEnabledData,
          child: const Text('同步已授權資料'),
        ),
      ),
    );
  }
}
