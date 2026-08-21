import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/follow_up_ai_summary.dart';
import '../models/follow_up_sleep_summary_view_model.dart';
import '../services/follow_up_summary_section_builder.dart';

class FollowUpSummaryPdfService {
  const FollowUpSummaryPdfService();
  static const _iansuiFontPath = 'assets/font/Iansui/Iansui-Regular.ttf';

  Future<Uint8List> buildPdf(
    FollowUpSummaryRecord record, {
    FollowUpSummaryShareOptions options = FollowUpSummaryShareOptions.all,
  }) async {
    final fontData = await rootBundle.load(_iansuiFontPath);
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
    final sections = FollowUpSummarySectionBuilder.fromDisplay(display);
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
          ...sections.expand((section) => _renderSection(
                section,
                display,
              )),
          pw.Divider(),
          pw.Text('AI 整理時間：${display.generatedAt}',
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return document.save();
  }

  List<pw.Widget> _renderSection(
    FollowUpSummarySection section,
    FollowUpSummaryDisplayModel display,
  ) {
    if (section.id == FollowUpSummarySectionId.basicInfo) {
      return [_heading(section.title), _info(display), pw.SizedBox(height: 8)];
    }
    if (section.id == FollowUpSummarySectionId.sleep) {
      return [
        _heading(section.title),
        if (display.sleepTrend.isNotEmpty)
          pw.SvgImage(svg: _sleepChartSvg(display.sleepTrend), height: 150),
        pw.SizedBox(height: 6),
        _sleepMetricsCards(section.items),
        pw.SizedBox(height: 8),
      ];
    }
    if (section.id == FollowUpSummarySectionId.discussion) {
      return [
        _heading(section.title),
        if (section.labels.isNotEmpty)
          pw.Text('主題標籤：${section.labels.join('、')}'),
        if (section.labels.isNotEmpty) pw.SizedBox(height: 4),
        ...section.items.map((item) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: _bullet(item),
            )),
        pw.SizedBox(height: 8),
      ];
    }
    return _section(section.title, section.items);
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
            child: pw.Text(item),
          ),
        ]),
      );

  pw.Widget _heading(String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(value,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _sleepMetricsCards(List<String> items) {
    final metrics = items
        .map((item) {
          final parsed = item.split('：');
          if (parsed.length < 2) {
            return FollowUpSleepMetric(label: '', value: item);
          }
          final label = parsed.first.trim();
          final value = parsed.sublist(1).join('：').trim();
          return FollowUpSleepMetric(label: label, value: value);
        })
        .where((item) => item.label.isNotEmpty || item.value.isNotEmpty)
        .toList(growable: false);
    if (metrics.isEmpty) {
      return pw.SizedBox.shrink();
    }
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics
          .map((metric) => pw.Container(
                width: 120,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#EEF6FA'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      metric.label,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.blueGrey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      metric.value,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(growable: false),
    );
  }

  String _sleepChartSvg(List<Map<String, dynamic>> trend) {
    final samples = trend
        .map((item) {
          final value = (item['value'] as num?)?.toDouble();
          final rawDate = item['date']?.toString() ?? '';
          final date =
              rawDate.length >= 10 ? rawDate.substring(5, 10) : rawDate;
          return (value: value, date: date);
        })
        .where((sample) => sample.value != null)
        .toList(growable: false);
    if (samples.isEmpty) return '<svg width="600" height="220"></svg>';

    final values =
        samples.map((sample) => sample.value!).toList(growable: false);
    final dataMin = values.reduce((a, b) => a < b ? a : b);
    final dataMax = values.reduce((a, b) => a > b ? a : b);
    final min = (dataMin - 1).floorToDouble().clamp(0, 24);
    final max = (dataMax + 1).ceilToDouble().clamp(min + 1, 24);

    const width = 600.0;
    const height = 220.0;
    const left = 56.0;
    const right = 12.0;
    const top = 14.0;
    const bottom = 34.0;
    final plotWidth = width - left - right;
    final plotHeight = height - top - bottom;
    final yRange = (max - min).clamp(1, 24);

    String point(int index, double value) {
      final x = samples.length == 1
          ? left + plotWidth / 2
          : left + index * plotWidth / (samples.length - 1);
      final y = top + (max - value) / yRange * plotHeight;
      return '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}';
    }

    final polyline = <String>[];
    final circles = <String>[];
    for (var index = 0; index < samples.length; index++) {
      final p = point(index, samples[index].value!);
      polyline.add(p);
      final parts = p.split(',');
      circles.add(
        '<circle cx="${parts[0]}" cy="${parts[1]}" r="3.5" fill="#4E6AA5"/>',
      );
    }

    final yTicks = <String>[];
    for (var tick = 0; tick <= 4; tick++) {
      final value = min + (yRange * (4 - tick) / 4);
      final y = top + tick / 4 * plotHeight;
      yTicks.add(
        '<line x1="$left" y1="${y.toStringAsFixed(1)}" x2="${(width - right).toStringAsFixed(1)}" y2="${y.toStringAsFixed(1)}" stroke="#D9E6ED"/>'
        '<text x="${(left - 8).toStringAsFixed(1)}" y="${(y + 3).toStringAsFixed(1)}" text-anchor="end" font-size="9" fill="#6A7E8D">${value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}</text>',
      );
    }

    final xTicks = <String>[];
    final step = samples.length <= 4 ? 1 : (samples.length / 4).ceil();
    for (var index = 0; index < samples.length; index += step) {
      final x = samples.length == 1
          ? left + plotWidth / 2
          : left + index * plotWidth / (samples.length - 1);
      xTicks.add(
        '<text x="${x.toStringAsFixed(1)}" y="${(height - 10).toStringAsFixed(1)}" text-anchor="middle" font-size="9" fill="#6A7E8D">${samples[index].date}</text>',
      );
    }
    if ((samples.length - 1) % step != 0) {
      final x = width - right;
      final label = samples.last.date;
      xTicks.add(
        '<text x="${x.toStringAsFixed(1)}" y="${(height - 10).toStringAsFixed(1)}" text-anchor="end" font-size="9" fill="#6A7E8D">$label</text>',
      );
    }

    return '''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="220" viewBox="0 0 600 220">
<rect width="600" height="220" fill="#F7FBFD"/>
<line x1="$left" y1="$top" x2="$left" y2="${(height - bottom).toStringAsFixed(1)}" stroke="#AFC4D1"/>
<line x1="$left" y1="${(height - bottom).toStringAsFixed(1)}" x2="${(width - right).toStringAsFixed(1)}" y2="${(height - bottom).toStringAsFixed(1)}" stroke="#AFC4D1"/>
${yTicks.join()}
${xTicks.join()}
<polyline points="${polyline.join(' ')}" fill="none" stroke="#63A8C7" stroke-width="3"/>
${circles.join()}
</svg>''';
  }
}
