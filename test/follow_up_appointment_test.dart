import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/services/follow_up_service.dart';

void main() {
  test('legacy discussion topic is not shown as appointment label', () {
    final appointment = FollowUpAppointment.fromMap({
      'id': 'legacy-summary-entry',
      'date': '2026-08-10',
      'label': '睡眠品質',
    });

    expect(appointment.label, '回診');
  });

  test('user-entered clinic label remains unchanged', () {
    final appointment = FollowUpAppointment.fromMap({
      'id': 'clinic-entry',
      'date': '2026-08-10',
      'label': '心臟內科／榮總',
    });

    expect(appointment.label, '心臟內科／榮總');
  });
}
