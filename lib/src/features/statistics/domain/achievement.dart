enum AchievementMetric {
  sessions,
  streak,
  verses,
  accuracy,
  perfectLong,
  chapters,
  plans,
  completedPlans,
}

final class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.metric,
    required this.target,
  });

  final String id;
  final String title;
  final String description;
  final AchievementMetric metric;
  final double target;
}

const achievementDefinitions = <AchievementDefinition>[
  AchievementDefinition(
    id: 'first_recitation',
    title: '初次开口',
    description: '完成第 1 次背诵',
    metric: AchievementMetric.sessions,
    target: 1,
  ),
  AchievementDefinition(
    id: 'sessions_3',
    title: '小小坚持',
    description: '累计背诵 3 次',
    metric: AchievementMetric.sessions,
    target: 3,
  ),
  AchievementDefinition(
    id: 'sessions_10',
    title: '渐入佳境',
    description: '累计背诵 10 次',
    metric: AchievementMetric.sessions,
    target: 10,
  ),
  AchievementDefinition(
    id: 'sessions_25',
    title: '熟能生巧',
    description: '累计背诵 25 次',
    metric: AchievementMetric.sessions,
    target: 25,
  ),
  AchievementDefinition(
    id: 'sessions_50',
    title: '背诵达人',
    description: '累计背诵 50 次',
    metric: AchievementMetric.sessions,
    target: 50,
  ),
  AchievementDefinition(
    id: 'sessions_100',
    title: '经文百炼',
    description: '累计背诵 100 次',
    metric: AchievementMetric.sessions,
    target: 100,
  ),
  AchievementDefinition(
    id: 'streak_3',
    title: '三日同行',
    description: '连续背诵 3 天',
    metric: AchievementMetric.streak,
    target: 3,
  ),
  AchievementDefinition(
    id: 'streak_7',
    title: '一周坚持',
    description: '连续背诵 7 天',
    metric: AchievementMetric.streak,
    target: 7,
  ),
  AchievementDefinition(
    id: 'streak_30',
    title: '月度同行',
    description: '连续背诵 30 天',
    metric: AchievementMetric.streak,
    target: 30,
  ),
  AchievementDefinition(
    id: 'verses_10',
    title: '十节种子',
    description: '累计完成 10 节',
    metric: AchievementMetric.verses,
    target: 10,
  ),
  AchievementDefinition(
    id: 'verses_50',
    title: '五十节成长',
    description: '累计完成 50 节',
    metric: AchievementMetric.verses,
    target: 50,
  ),
  AchievementDefinition(
    id: 'verses_100',
    title: '百节丰收',
    description: '累计完成 100 节',
    metric: AchievementMetric.verses,
    target: 100,
  ),
  AchievementDefinition(
    id: 'accuracy_80',
    title: '初次优秀',
    description: '单次正确率达到 80%',
    metric: AchievementMetric.accuracy,
    target: 0.8,
  ),
  AchievementDefinition(
    id: 'accuracy_90',
    title: '精准背诵',
    description: '单次正确率达到 90%',
    metric: AchievementMetric.accuracy,
    target: 0.9,
  ),
  AchievementDefinition(
    id: 'perfect_100',
    title: '一字不差',
    description: '不少于 20 字且正确率 100%',
    metric: AchievementMetric.perfectLong,
    target: 1,
  ),
  AchievementDefinition(
    id: 'chapter_complete',
    title: '完成一章',
    description: '完成同一章全部经节',
    metric: AchievementMetric.chapters,
    target: 1,
  ),
  AchievementDefinition(
    id: 'first_plan',
    title: '计划启程',
    description: '创建第一个背诵计划',
    metric: AchievementMetric.plans,
    target: 1,
  ),
  AchievementDefinition(
    id: 'plan_complete',
    title: '计划完成',
    description: '完成第一个背诵计划',
    metric: AchievementMetric.completedPlans,
    target: 1,
  ),
];

final class AchievementSnapshot {
  const AchievementSnapshot({
    required this.sessionCount,
    required this.activeDayStreak,
    required this.completedVerses,
    required this.maxAccuracy,
    required this.hasPerfectLongResult,
    required this.completedChapters,
    required this.planCount,
    required this.completedPlanCount,
  });

  final int sessionCount;
  final int activeDayStreak;
  final int completedVerses;
  final double maxAccuracy;
  final bool hasPerfectLongResult;
  final int completedChapters;
  final int planCount;
  final int completedPlanCount;
}

final class AchievementProgress {
  const AchievementProgress({
    required this.definition,
    required this.current,
    required this.satisfied,
    this.unlockedAt,
  });

  final AchievementDefinition definition;
  final double current;
  final bool satisfied;
  final DateTime? unlockedAt;

  double get fraction => (current / definition.target).clamp(0, 1).toDouble();
}

final class AchievementUnlock {
  const AchievementUnlock({
    required this.definition,
    required this.unlockedAt,
    required this.source,
  });

  final AchievementDefinition definition;
  final DateTime unlockedAt;
  final String source;
}
