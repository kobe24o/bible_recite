final class EbbinghausSettings {
  const EbbinghausSettings({
    required this.enabled,
    required this.passThreshold,
    this.enabledAt,
  });

  final bool enabled;
  final double passThreshold;
  final DateTime? enabledAt;
}

final class EbbinghausReview {
  const EbbinghausReview({
    required this.id,
    required this.cycleId,
    required this.translationId,
    required this.bookId,
    required this.chapter,
    required this.intervalDays,
    required this.dueDate,
    required this.completed,
  });

  final int id;
  final int cycleId;
  final String translationId;
  final String bookId;
  final int chapter;
  final int intervalDays;
  final DateTime dueDate;
  final bool completed;
}
