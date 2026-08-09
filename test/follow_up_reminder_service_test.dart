import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('follow-up reminder defaults to three days with AI check-in off',
      () async {
    final settings = await FollowUpReminderService().loadSettings();

    expect(settings.reminderDays, 3);
    expect(settings.aiCheckInEnabled, isFalse);
    expect(settings.reminderHour, 9);
    expect(settings.reminderMinute, 0);
  });

  test('follow-up reminder settings persist independently', () async {
    final service = FollowUpReminderService();
    final schedule = await service.saveAndReschedule(
      settings: const FollowUpReminderSettings(
        reminderDays: 7,
        aiCheckInEnabled: true,
        reminderHour: 18,
        reminderMinute: 30,
      ),
      appointments: const [],
    );
    expect(schedule.count, 0);

    final restored = await service.loadSettings();
    expect(restored.reminderDays, 7);
    expect(restored.aiCheckInEnabled, isTrue);
    expect(restored.reminderHour, 18);
    expect(restored.reminderMinute, 30);
  });

  test('unsupported stored day falls back to three days', () async {
    SharedPreferences.setMockInitialValues({
      'followUpReminderDays': 5,
      'followUpAiCheckInEnabled': true,
      'followUpReminderHour': 25,
      'followUpReminderMinute': 80,
    });

    final restored = await FollowUpReminderService().loadSettings();
    expect(restored.reminderDays, 3);
    expect(restored.aiCheckInEnabled, isTrue);
    expect(restored.reminderHour, 9);
    expect(restored.reminderMinute, 0);
  });
}
