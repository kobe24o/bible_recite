/// Daily quotas derive duration; fixed durations distribute whole units evenly.
enum ReadingScheduleMode {
  dailyChapters,
  dailyVerses,
  daysByChapters,
  daysByVerses;

  bool get usesChapters => this == dailyChapters || this == daysByChapters;
  bool get usesDailyQuota => this == dailyChapters || this == dailyVerses;
}

List<List<T>> distributeReadingUnits<T>(
  List<T> units,
  ReadingScheduleMode mode,
  int amount,
) {
  if (amount < 1) {
    throw ArgumentError.value(amount, 'amount', 'Must be positive');
  }
  if (units.isEmpty) return [];
  final days = mode.usesDailyQuota
      ? (units.length + amount - 1) ~/ amount
      : amount;
  var cursor = 0;
  return [
    for (var day = 0; day < days; day++)
      () {
        final count = mode.usesDailyQuota
            ? amount.clamp(0, units.length - cursor)
            : units.length ~/ days + (day < units.length % days ? 1 : 0);
        final group = units.sublist(cursor, cursor + count);
        cursor += count;
        return group;
      }(),
  ];
}
