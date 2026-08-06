class AppLockSessionService {
  const AppLockSessionService._();

  static const backgroundTimeout = Duration(minutes: 3);
  static DateTime? _verifiedAt;
  static DateTime? _backgroundedAt;

  static bool get isVerified => _verifiedAt != null;

  static void markVerified({DateTime? now}) {
    _verifiedAt = now ?? DateTime.now();
    _backgroundedAt = null;
  }

  static void markBackgrounded({DateTime? now}) {
    _backgroundedAt ??= now ?? DateTime.now();
  }

  static void markResumed({DateTime? now}) {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;
    if ((now ?? DateTime.now()).difference(backgroundedAt) >=
        backgroundTimeout) {
      clear();
    }
  }

  static void clear() {
    _verifiedAt = null;
  }

  static void resetForTesting() {
    _verifiedAt = null;
    _backgroundedAt = null;
  }
}
