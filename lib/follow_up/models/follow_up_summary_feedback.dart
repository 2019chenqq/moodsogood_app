enum FollowUpFeedbackAnswer { yes, no, unsure }

enum FollowUpDoctorAnswer { yes, no, notMentioned }

class FollowUpSummaryFeedback {
  FollowUpSummaryFeedback({
    required this.shownToDoctor,
    FollowUpFeedbackAnswer? surfacedForgottenInfo,
    FollowUpFeedbackAnswer? hadDeeperDiscussion,
    FollowUpDoctorAnswer? doctorRequestedAgain,
    required this.submittedAt,
  })  : surfacedForgottenInfo = shownToDoctor ? surfacedForgottenInfo : null,
        hadDeeperDiscussion = shownToDoctor ? hadDeeperDiscussion : null,
        doctorRequestedAgain = shownToDoctor ? doctorRequestedAgain : null {
    if (shownToDoctor &&
        (surfacedForgottenInfo == null ||
            hadDeeperDiscussion == null ||
            doctorRequestedAgain == null)) {
      throw ArgumentError('請完成回饋選項');
    }
  }

  final bool shownToDoctor;
  final FollowUpFeedbackAnswer? surfacedForgottenInfo;
  final FollowUpFeedbackAnswer? hadDeeperDiscussion;
  final FollowUpDoctorAnswer? doctorRequestedAgain;
  final DateTime submittedAt;

  Map<String, dynamic> toMap() => {
        'shownToDoctor': shownToDoctor,
        'surfacedForgottenInfo': surfacedForgottenInfo?.name,
        'hadDeeperDiscussion': hadDeeperDiscussion?.name,
        'doctorRequestedAgain': doctorRequestedAgain?.name,
        'submittedAt': submittedAt.toUtc().toIso8601String(),
      };

  static FollowUpSummaryFeedback? fromMap(dynamic raw) {
    if (raw is! Map || raw['shownToDoctor'] is! bool) return null;
    try {
      return FollowUpSummaryFeedback(
        shownToDoctor: raw['shownToDoctor'] as bool,
        surfacedForgottenInfo: raw['surfacedForgottenInfo'] == null
            ? null
            : FollowUpFeedbackAnswer.values
                .byName(raw['surfacedForgottenInfo'] as String),
        hadDeeperDiscussion: raw['hadDeeperDiscussion'] == null
            ? null
            : FollowUpFeedbackAnswer.values
                .byName(raw['hadDeeperDiscussion'] as String),
        doctorRequestedAgain: raw['doctorRequestedAgain'] == null
            ? null
            : FollowUpDoctorAnswer.values
                .byName(raw['doctorRequestedAgain'] as String),
        submittedAt: DateTime.parse(raw['submittedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
