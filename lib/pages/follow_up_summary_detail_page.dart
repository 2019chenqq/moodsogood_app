import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/healing_design_system.dart';
import '../models/follow_up_ai_summary.dart';
import '../services/follow_up_service.dart';
import '../services/follow_up_summary_pdf_service.dart';
import '../services/follow_up_summary_share_service.dart';
import '../utils/app_lock_session_service.dart';
import '../widgets/follow_up_sleep_trend_card.dart';
import 'follow_up_share_preview_page.dart';
import 'follow_up_summary_access_guard.dart';

class FollowUpSummaryDetailPage extends StatefulWidget {
  const FollowUpSummaryDetailPage({super.key, required this.summary});
  final FollowUpSummaryRecord summary;

  @override
  State<FollowUpSummaryDetailPage> createState() =>
      _FollowUpSummaryDetailPageState();
}

class _FollowUpSummaryDetailPageState extends State<FollowUpSummaryDetailPage>
    with WidgetsBindingObserver {
  late FollowUpSummaryRecord _summary;
  FollowUpShareSession? _activeShare;
  FollowUpSummaryShareOptions _activeShareOptions =
      FollowUpSummaryShareOptions.none;
  final _shareService = FollowUpSummaryShareService();
  bool _working = false;
  bool _authorized = false;
  bool _checkingAccess = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _summary = widget.summary;
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyAccess());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >=
              AppLockSessionService.backgroundTimeout) {
        AppLockSessionService.clear();
        if (mounted) {
          setState(() => _authorized = false);
          _verifyAfterBackgroundTimeout();
        }
      }
    }
  }

  Future<void> _verifyAfterBackgroundTimeout() async {
    final preferences = await SharedPreferences.getInstance();
    final globalLockEnabled = preferences.getBool('appLockEnabled') ?? false;
    if (!mounted || globalLockEnabled) return;
    await _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    if (_checkingAccess || !mounted) return;
    _checkingAccess = true;
    final verified = await FollowUpSummaryAccessGuard.ensureVerified(context);
    _checkingAccess = false;
    if (!mounted) return;
    if (!verified) {
      Navigator.maybePop(context, false);
      return;
    }
    setState(() => _authorized = true);
    _loadActiveShare();
  }

  Future<void> _loadActiveShare() async {
    try {
      final shares = await _shareService.activeShares([_summary.id]);
      if (mounted && shares[_summary.id] != null) {
        setState(() => _activeShare = shares[_summary.id]);
      }
    } catch (_) {
      // The detail remains usable; share actions expose their own retry errors.
    }
  }

  Future<void> _edit() async {
    final edited = await showDialog<FollowUpSummaryRecord>(
      context: context,
      builder: (_) => _SummaryEditor(summary: _summary),
    );
    if (edited == null) return;
    setState(() => _working = true);
    try {
      final saved = await FollowUpService.updateFormalSummary(edited);
      if (mounted) setState(() => _summary = saved);
    } catch (error) {
      if (mounted) _showError('更新摘要失敗', error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportPdf(FollowUpSummaryShareOptions options) async {
    setState(() => _working = true);
    try {
      await const FollowUpSummaryPdfService().sharePdf(
        _summary,
        options: options,
      );
    } catch (error) {
      if (mounted) {
        _showError('匯出 PDF 失敗', error, retry: () => _exportPdf(options));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareQr(FollowUpSummaryShareOptions options) async {
    _activeShareOptions = options;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TimedShareDialog(
        summary: _summary,
        options: options,
        initialSession: _activeShare,
        onSessionChanged: (session) {
          if (mounted) setState(() => _activeShare = session);
        },
      ),
    );
  }

  Future<void> _shareWithDoctor() async {
    final result = await Navigator.push<FollowUpSharePreviewResult>(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpSharePreviewPage(summary: _summary),
      ),
    );
    if (!mounted || result == null) return;
    switch (result.type) {
      case FollowUpShareActionType.pdf:
        await _exportPdf(result.options);
        break;
      case FollowUpShareActionType.qr:
        await _shareQr(result.options);
        break;
    }
  }

  Future<void> _stopActiveShare() async {
    final session = _activeShare;
    if (session == null) return;
    final confirmed = await _confirmStopShare(context);
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await _shareService.revoke(session);
      if (!mounted) return;
      setState(() => _activeShare = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享已停止，原 QR Code 與連結已立即失效。')),
      );
    } catch (error) {
      if (!mounted) return;
      if (error is FollowUpShareException && error.shareStopped) {
        setState(() => _activeShare = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享已停止。')),
        );
      } else {
        _showError('停止分享失敗', error, retry: _stopActiveShare);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這份摘要？'),
        content: const Text('刪除後無法復原。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    try {
      await FollowUpService.deleteFormalSummary(_summary.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError('刪除摘要失敗', error, retry: _delete);
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String title, Object error, {VoidCallback? retry}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$title：$error'),
      action:
          retry == null ? null : SnackBarAction(label: '重試', onPressed: retry),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return Scaffold(
        backgroundColor: HealingDesignSystem.adaptiveBackground(context),
        appBar: AppBar(
          title: const Text('回診摘要詳情'),
          backgroundColor: HealingDesignSystem.primaryBlue,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final display = FollowUpSummaryDisplayModel.fromRecord(_summary);
    final hasActiveShare =
        _activeShare != null && _activeShare!.expiresAt.isAfter(DateTime.now());
    return Scaffold(
      backgroundColor: HealingDesignSystem.adaptiveBackground(context),
      appBar: AppBar(
        title: const Text('回診摘要詳情'),
        backgroundColor: HealingDesignSystem.primaryBlue,
      ),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card('基本資訊', display.visitInfo, bullets: false),
            _discussionCard(display),
            _card('主要變化', display.keyChanges),
            FollowUpSleepTrendCard.fromRecord(record: _summary),
            _card('身體症狀', display.symptoms,
                emptyText: '此摘要沒有可顯示的症狀資料'),
            _card('身體測量', display.bodyMeasurements,
                emptyText: '此摘要沒有可顯示的體重、體脂率或腰圍資料'),
            _card('藥物調整時間軸', display.medicationTimeline,
                emptyText: '此摘要沒有藥物調整紀錄'),
            _card('其他想跟醫師說的內容', display.userSharedNotes,
                emptyText: '沒有其他想跟醫師說的內容'),
            _card('資料限制', display.dataLimitations),
            _card('AI 整理時間', [display.generatedAt], bullets: false),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('摘要僅供回診溝通參考，不取代醫師判斷。'),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: _working ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('編輯摘要')),
              OutlinedButton.icon(
                  onPressed: _working ? null : _shareWithDoctor,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('分享給醫師')),
              if (hasActiveShare)
                OutlinedButton.icon(
                    onPressed:
                        _working ? null : () => _shareQr(_activeShareOptions),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('管理有效 QR Code')),
              if (hasActiveShare)
                TextButton.icon(
                    onPressed: _working ? null : _stopActiveShare,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('提前停止分享')),
              TextButton.icon(
                  onPressed: _working ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('刪除摘要')),
            ]),
            const SizedBox(height: 24),
          ],
        ),
        if (_working) const LinearProgressIndicator(),
      ]),
    );
  }

  Widget _card(String title, List<String> items,
      {String emptyText = '尚無資料', bool bullets = true}) {
    return Card(
      elevation: 0,
      color: HealingDesignSystem.adaptiveSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: HealingDesignSystem.titleSmall),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(emptyText,
                style: TextStyle(
                    color: HealingDesignSystem.adaptiveSecondaryText(context)))
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(bullets ? '• $item' : item,
                      style: const TextStyle(height: 1.45)),
                )),
        ]),
      ),
    );
  }

  Widget _discussionCard(FollowUpSummaryDisplayModel display) => Card(
        elevation: 0,
        color: HealingDesignSystem.adaptiveSurface(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('想跟醫師討論的事', style: HealingDesignSystem.titleSmall),
            if (display.topicLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: display.topicLabels
                    .map((label) => Chip(label: Text(label)))
                    .toList(),
              ),
            ],
            if (display.discussionItems.isEmpty && display.topicLabels.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('尚無資料',
                    style: TextStyle(
                        color: HealingDesignSystem.adaptiveSecondaryText(
                            context))),
              )
            else
              ...display.discussionItems.map((item) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child:
                        Text('• $item', style: const TextStyle(height: 1.45)),
                  )),
          ]),
        ),
      );

  static String _date(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  static String _dateTime(DateTime value) =>
      '${_date(value.toLocal())} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}

class _SummaryEditor extends StatefulWidget {
  const _SummaryEditor({required this.summary});
  final FollowUpSummaryRecord summary;
  @override
  State<_SummaryEditor> createState() => _SummaryEditorState();
}

class _SummaryEditorState extends State<_SummaryEditor> {
  late final Map<String, TextEditingController> _controllers;
  @override
  void initState() {
    super.initState();
    final output = widget.summary.aiOutput;
    _controllers = {
      'details': TextEditingController(text: widget.summary.discussionDetails),
      'notes': TextEditingController(text: widget.summary.additionalNotes),
      'changes': TextEditingController(text: output.keyChanges.join('\n')),
      'discussionItems': TextEditingController(
        text: FollowUpSummaryTextFormatter.safeDiscussionItems([
          if (widget.summary.discussionDetails.trim().isNotEmpty)
            widget.summary.discussionDetails,
          ...output.discussionItems,
          ...output.discussionPriorities,
        ]).join('\n'),
      ),
      'sharedNotes':
          TextEditingController(text: output.userSharedNotes.join('\n')),
      'limitations':
          TextEditingController(text: output.dataLimitations.join('\n')),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _lines(String key) => _controllers[key]!
      .text
      .split(RegExp(r'[\r\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('編輯摘要'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(children: [
              _field('想討論的內容', 'details'),
              _field('其他想討論的事', 'notes'),
              _field('主要變化（每行一項）', 'changes'),
              _field('想跟醫師討論的事（每行一項）', 'discussionItems'),
              _field('其他想跟醫師說的內容（每行一項）', 'sharedNotes'),
              _field('資料限制（每行一項）', 'limitations'),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final old = widget.summary.aiOutput;
                Navigator.pop(
                    context,
                    widget.summary.copyWith(
                        discussionDetails: _controllers['details']!.text.trim(),
                        additionalNotes: _controllers['notes']!.text.trim(),
                        aiOutput: FollowUpAiOutput(
                            keyChanges: _lines('changes'),
                            timelineRelations: old.timelineRelations,
                            discussionPriorities: const [],
                            discussionItems: _lines('discussionItems'),
                            followUpResponses: old.followUpResponses,
                            userSharedNotes: _lines('sharedNotes'),
                            userReportedConcerns: old.userReportedConcerns,
                            diaryHighlights: old.diaryHighlights,
                            dataLimitations: _lines('limitations'),
                            generatedAt: old.generatedAt,
                            usedFallback: old.usedFallback)));
              },
              child: const Text('儲存'))
        ],
      );
  Widget _field(String label, String key) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
          controller: _controllers[key],
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder())));
}

class _TimedShareDialog extends StatefulWidget {
  const _TimedShareDialog({
    required this.summary,
    required this.options,
    required this.initialSession,
    required this.onSessionChanged,
  });
  final FollowUpSummaryRecord summary;
  final FollowUpSummaryShareOptions options;
  final FollowUpShareSession? initialSession;
  final ValueChanged<FollowUpShareSession?> onSessionChanged;
  @override
  State<_TimedShareDialog> createState() => _TimedShareDialogState();
}

class _TimedShareDialogState extends State<_TimedShareDialog> {
  final _service = FollowUpSummaryShareService();
  FollowUpShareSession? _session;
  Timer? _timer;
  bool _loading = false;
  bool _stopped = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    if (_session == null) _create();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final previous = _session;
      if (previous != null) {
        await _service.revoke(previous);
        widget.onSessionChanged(null);
        if (mounted) {
          setState(() {
            _session = null;
            _stopped = true;
          });
        }
      }
      final next = await _service.create(
        widget.summary,
        options: widget.options,
      );
      widget.onSessionChanged(next);
      if (mounted) {
        setState(() {
          _session = next;
          _stopped = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '建立分享失敗：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke() async {
    final current = _session;
    if (current == null) return;
    final confirmed = await _confirmStopShare(context);
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _service.revoke(current);
      widget.onSessionChanged(null);
      if (mounted) {
        setState(() {
          _session = null;
          _stopped = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        if (e is FollowUpShareException && e.shareStopped) {
          widget.onSessionChanged(null);
          setState(() {
            _session = null;
            _stopped = true;
            _error = null;
          });
        } else {
          setState(() => _error = '停止分享失敗：$e');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final remaining = session?.remainingAt(DateTime.now()) ?? Duration.zero;
    final isActive = session != null && remaining > Duration.zero;
    return AlertDialog(
      title: const Text('36 小時限時 QR Code'),
      content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            if (isActive) ...[
              if (session.url.isNotEmpty)
                Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: SizedBox.square(
                        dimension: 220,
                        child: CustomPaint(painter: _QrPainter(session.url))))
              else
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('原連結不會儲存在伺服器。你仍可停止分享，或重新產生新的 QR Code。'),
                ),
              const SizedBox(height: 10),
              Text(
                  '到期時間：${_FollowUpSummaryDetailPageState._dateTime(session.expiresAt)}'),
              Text(
                  '剩餘時間：約 ${remaining.inHours} 小時 ${remaining.inMinutes.remainder(60)} 分'),
              if (session.url.isNotEmpty)
                TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: session.url));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('已複製連結')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('複製連結'))
            ],
            if (!_loading && !isActive && _error == null)
              Text(_stopped
                  ? '分享已停止。原 QR Code 與連結已失效。'
                  : session == null
                      ? '尚未建立分享。'
                      : '分享已過期。'),
            if (!_loading && !widget.options.hasSelection)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('如要重新產生，請關閉後從「分享給醫師」重新選擇內容。'),
              ),
          ])),
      actions: [
        if (isActive)
          TextButton(
              onPressed: _loading ? null : _revoke,
              child: const Text('提前停止分享')),
        TextButton(
            onPressed:
                _loading || !widget.options.hasSelection ? null : _create,
            child: Text(isActive || _stopped || session != null
                ? '重新產生 QR Code'
                : '產生 QR Code')),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('關閉'))
      ],
    );
  }
}

Future<bool?> _confirmStopShare(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('提前停止分享？'),
      content: const Text('停止後，目前的 QR Code 與分享連結會立即失效，且無法恢復。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('停止分享'),
        ),
      ],
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(String data)
      : _image = QrImage(QrCode.fromData(
            data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
  final QrImage _image;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final scale = size.shortestSide / _image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < _image.moduleCount; y++) {
      for (var x = 0; x < _image.moduleCount; x++) {
        if (_image.isDark(y, x)) {
          canvas.drawRect(
              Rect.fromLTWH(x * scale, y * scale, scale.ceilToDouble(),
                  scale.ceilToDouble()),
              paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => false;
}
