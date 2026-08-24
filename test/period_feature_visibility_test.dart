import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/daily/period_feature_visibility_service.dart';

void main() {
  test('period features are hidden only for explicit biological male', () {
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex('女性'),
      isTrue,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex(' 女性 '),
      isTrue,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex('男性'),
      isFalse,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex(' 男性 '),
      isFalse,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex('間性'),
      isTrue,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex(null),
      isTrue,
    );
    expect(
      PeriodFeatureVisibilityService.shouldShowForSex(''),
      isTrue,
    );
  });
}
