import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/follow_up_ai_summary.dart';

class FollowUpSummaryPdfService {
  const FollowUpSummaryPdfService();

  Future<Uint8List> buildPdf(
    FollowUpSummaryRecord record, {
    FollowUpSummaryShareOptions options = FollowUpSummaryShareOptions.all,
  }) async {
    final fontData =
        await rootBundle.load('assets/font/Iansui/Iansui-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      ),
    );
    final display = FollowUpSummaryDisplayModel.fromRecord(
      record,
      options: options,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                '摘要僅供回診溝通參考，不取代醫師判斷。',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.Text('${context.pageNumber} / ${context.pagesCount}'),
          ],
        ),
        build: (_) => [
          pw.Text('AI 回診摘要',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _heading('基本資訊'),
          _info(display),
          if (options.discussionTopics) ..._discussion(display),
          ..._section('主要變化', display.keyChanges),
          if (options.sleep) ...[
            _heading('睡眠趨勢'),
            if (display.sleepTrend.isNotEmpty)
              pw.SvgImage(svg: _sleepChartSvg(display.sleepTrend), height: 125)
            else
              pw.Text('統計期間內沒有可用的睡眠時數紀錄。'),
            pw.SizedBox(height: 6),
            ...display.sleepSummaryItems.map((item) => _bullet(item)),
            pw.SizedBox(height: 8),
          ],
          if (options.emotionsAndSymptoms)
            ..._section(
              '症狀與身體變化',
              display.symptomAndBodyChanges,
              emptyText: '此摘要沒有可顯示的症狀或身體測量資料。',
            ),
          ..._section(
            '藥物調整時間軸',
            display.medicationTimeline,
            emptyText: '此摘要沒有藥物調整紀錄。',
          ),
          if (options.lifeUpdates)
            ..._section(
              '其他想跟醫師說的內容',
              display.userSharedNotes,
              emptyText: '沒有其他想跟醫師說的內容。',
            ),
          ..._section(
            '資料限制',
            display.dataLimitations,
            emptyText: '沒有其他資料限制。',
          ),
          pw.Divider(),
          pw.Text('AI 整理時間：${display.generatedAt}',
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return document.save();
  }

  Future<void> sharePdf(
    FollowUpSummaryRecord record, {
    required FollowUpSummaryShareOptions options,
  }) async {
    final bytes = await buildPdf(record, options: options);
    final opened = await Printing.sharePdf(
      bytes: bytes,
      filename: exportFilename(record.periodEnd),
    );
    if (!opened) {
      throw StateError('系統未能開啟 PDF 分享畫面，請稍後再試。');
    }
  }

  /// File names must not reuse the UI date format because `/` is interpreted
  /// as a directory separator on Android, iOS, Windows, and macOS.
  static String exportFilename(DateTime periodEnd) =>
      'AI回診摘要_${periodEnd.year}-'
      '${periodEnd.month.toString().padLeft(2, '0')}-'
      '${periodEnd.day.toString().padLeft(2, '0')}.pdf';

  pw.Widget _info(FollowUpSummaryDisplayModel display) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue50,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ...display.visitInfo.map(pw.Text.new),
          ],
        ),
      );

  List<pw.Widget> _discussion(FollowUpSummaryDisplayModel display) => [
        _heading('想跟醫師討論的事'),
        if (display.topicLabels.isNotEmpty)
          pw.Text('已選主題：${display.topicLabels.join('、')}'),
        ...display.discussionItems.map(_bullet),
        if (display.topicLabels.isEmpty && display.discussionItems.isEmpty)
          pw.Text('尚無資料'),
        pw.SizedBox(height: 8),
      ];

  List<pw.Widget> _section(
    String title,
    List<String> items, {
    String? emptyText,
  }) {
    final clean =
        items.map((item) => item.trim()).where((item) => item.isNotEmpty);
    if (clean.isEmpty && emptyText == null) return const [];
    return [
      _heading(title),
      if (clean.isEmpty)
        pw.Text(emptyText!, style: const pw.TextStyle(fontSize: 10))
      else
        ...clean.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: _bullet(item),
            )),
      pw.SizedBox(height: 8),
    ];
  }

  pw.Widget _bullet(String item) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child:
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('•  '),
          pw.Expanded(
            child: pw.Text(item, style: const pw.TextStyle(lineSpacing: 2)),
          ),
        ]),
      );

  pw.Widget _heading(String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(value,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      );

  String _sleepChartSvg(List<Map<String, dynamic>> trend) {
    final values = trend
        .map((item) => (item['value'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (values.isEmpty) return '<svg width="600" height="180"></svg>';
    final max = values.reduce((a, b) => a > b ? a : b).clamp(8, 16);
    final width = 600.0;
    final height = 180.0;
    final points = <String>[];
    for (var index = 0; index < values.length; index++) {
      final x =
          values.length == 1 ? width / 2 : index * width / (values.length - 1);
      final y = height - (values[index] / max * (height - 20)) - 10;
      points.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
    }
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="180" viewBox="0 0 600 180">
<rect width="600" height="180" fill="#F7FBFD"/>
<line x1="0" y1="170" x2="600" y2="170" stroke="#CAD9E2"/>
<polyline points="${points.join(' ')}" fill="none" stroke="#63A8C7" stroke-width="4"/>
${points.map((point) {
      final parts = point.split(',');
      return '<circle cx="${parts[0]}" cy="${parts[1]}" r="4" fill="#4E6AA5"/>';
    }).join()}
</svg>''';
  }
}
