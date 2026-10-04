/// Records only the foreground portion of a single day's devotion reading.
///
/// The owner is responsible for mapping app lifecycle and route events onto
/// [start], [pause], [resume], and [stop].  Keeping this class Flutter-free
/// makes its time accounting deterministic and easy to exercise in isolation.
final class DevotionReadingSession {
  DevotionReadingSession({
    required this.day,
    required this.clock,
    required this.onElapsed,
  });

  final DateTime day;
  final DateTime Function() clock;
  final Future<void> Function(DateTime day, int seconds) onElapsed;

  DateTime? _activeSince;
  int _activeSeconds = 0;
  bool _stopped = false;
  Future<void> _pendingFlush = Future.value();

  void start() {
    if (_stopped || _activeSince != null) return;
    final now = clock();
    if (!_isSameDay(now, day)) {
      _stopped = true;
      return;
    }
    _activeSince = now;
  }

  Future<void> pause() {
    if (_stopped || _activeSince == null) return _pendingFlush;
    final now = clock();
    if (!_isSameDay(now, day)) {
      _activeSince = null;
      _stopped = true;
      return _flush();
    }
    _accumulateUntil(now);
    return _pendingFlush;
  }

  void resume() {
    if (_stopped || _activeSince != null) return;
    final now = clock();
    if (!_isSameDay(now, day)) {
      _stopped = true;
      return;
    }
    _activeSince = now;
  }

  Future<void> stop() {
    if (_stopped) return _pendingFlush;
    _stopped = true;
    final now = clock();
    if (_activeSince != null && _isSameDay(now, day)) {
      _accumulateUntil(now);
    } else {
      _activeSince = null;
    }
    return _flush();
  }

  Future<void> dispose() => stop();

  void _accumulateUntil(DateTime now) {
    final startedAt = _activeSince;
    if (startedAt == null) return;
    _activeSince = null;
    final seconds = now.difference(startedAt).inSeconds;
    if (seconds > 0) _activeSeconds += seconds;
  }

  Future<void> _flush() {
    final seconds = _activeSeconds;
    _activeSeconds = 0;
    if (seconds <= 0) return _pendingFlush;
    _pendingFlush = _pendingFlush.then((_) => onElapsed(day, seconds));
    return _pendingFlush;
  }

  static bool _isSameDay(DateTime value, DateTime expected) =>
      value.year == expected.year &&
      value.month == expected.month &&
      value.day == expected.day;
}
