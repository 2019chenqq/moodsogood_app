import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/Home_shell.dart';

void main() {
  test('returning to Today changes its revision so timeline reloads', () {
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 1,
        selectedIndex: 0,
        currentRevision: 3,
      ),
      4,
    );
  });

  test('selecting other destinations does not rebuild Today', () {
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 0,
        selectedIndex: 1,
        currentRevision: 3,
      ),
      3,
    );
    expect(
      homeShellTodayRevisionAfterSelection(
        currentIndex: 0,
        selectedIndex: 0,
        currentRevision: 3,
      ),
      3,
    );
  });
}
