final class EbbinghausScheduler {
  const EbbinghausScheduler();

  static const intervals = <int>[1, 2, 4, 7, 15, 30];

  List<DateTime> reviewDates(DateTime baseDate) {
    final date = DateTime(baseDate.year, baseDate.month, baseDate.day);
    return [for (final days in intervals) date.add(Duration(days: days))];
  }

  bool passes({required double accuracy, required double threshold}) =>
      accuracy >= threshold;
}
