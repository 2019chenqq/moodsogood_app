import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/utils/sleep_record_parser.dart';

void main() {
  test('unknown scale stays unknown even for apparently plausible values', () {
    for (final value in [1, 3, 5, 7, 10, '4']) {
      expect(SleepRecordParser.quality({'quality': value}), isNull);
    }
  });
  test('known schema scale and explicit legacy scale normalize safely', () {
    expect(SleepRecordParser.quality({'quality': 4}, knownScale: 5), 4);
    expect(SleepRecordParser.quality({'quality': '4', 'qualityScale': '5'}), 4);
    expect(
        SleepRecordParser.quality({'sleepQuality': 8, 'sleepQualityScale': 10}),
        4);
    expect(
        SleepRecordParser.quality({'qualityScore': 10, 'qualityScale': 10}), 5);
    expect(
        SleepRecordParser.quality(null,
            record: {'sleepQuality': 6, 'sleepQualityScale': 10}),
        3);
    expect(SleepRecordParser.quality({'quality': 1, 'qualityScale': 10}), 1);
  });
  test('missing and invalid scores never become zero or normal', () {
    for (final value in [
      null,
      '',
      'bad',
      0,
      -1,
      6,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      'NaN',
      'Infinity'
    ]) {
      expect(
          SleepRecordParser.quality({'quality': value}, knownScale: 5), isNull);
    }
    expect(
        SleepRecordParser.quality({'quality': 11, 'qualityScale': 10}), isNull);
  });
  test('invalid explicit scale cannot be overridden by known schema', () {
    for (final scale in [
      0,
      -5,
      4,
      100,
      '',
      'bad',
      double.nan,
      double.infinity
    ]) {
      expect(
          SleepRecordParser.quality({'quality': 4, 'qualityScale': scale},
              knownScale: 5),
          isNull);
    }
    expect(SleepRecordParser.quality({'quality': 4}, knownScale: 100), isNull);
  });
  test('invalid preferred score is not silently replaced by legacy score', () {
    expect(
        SleepRecordParser.quality(
            {'quality': 'bad', 'sleepQuality': 4, 'qualityScale': 5}),
        isNull);
  });
}
