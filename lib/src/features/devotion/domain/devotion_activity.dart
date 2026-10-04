final class DevotionStats {
  const DevotionStats({
    required this.devotionDays,
    required this.totalSeconds,
    required this.currentDayStreak,
    required this.maxDayStreak,
  });

  final int devotionDays;
  final int totalSeconds;
  final int currentDayStreak;
  final int maxDayStreak;
}
