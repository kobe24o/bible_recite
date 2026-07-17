enum PlanSourceKind { local, preset, cloud }

final class NewPlanTask {
  const NewPlanTask({
    required this.dayIndex,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
    this.bookId,
  });

  final int dayIndex;
  final String? bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
}

final class NewMemorizationPlan {
  const NewMemorizationPlan({
    required this.title,
    required this.translationId,
    required this.bookId,
    required this.startChapter,
    required this.endChapter,
    required this.startDate,
    required this.endDate,
    required this.tasks,
    this.sourceKind = PlanSourceKind.local,
    this.sourceUrl,
    this.externalId,
    this.revision = 0,
    this.contentLocked = false,
  });

  final String title;
  final String translationId;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final DateTime startDate;
  final DateTime endDate;
  final List<NewPlanTask> tasks;
  final PlanSourceKind sourceKind;
  final String? sourceUrl;
  final String? externalId;
  final int revision;
  final bool contentLocked;

  int get days => endDate.difference(startDate).inDays + 1;

  NewMemorizationPlan copyWith({
    String? title,
    String? translationId,
    String? bookId,
    int? startChapter,
    int? endChapter,
    DateTime? startDate,
    DateTime? endDate,
    List<NewPlanTask>? tasks,
    PlanSourceKind? sourceKind,
    String? sourceUrl,
    String? externalId,
    int? revision,
    bool? contentLocked,
  }) => NewMemorizationPlan(
    title: title ?? this.title,
    translationId: translationId ?? this.translationId,
    bookId: bookId ?? this.bookId,
    startChapter: startChapter ?? this.startChapter,
    endChapter: endChapter ?? this.endChapter,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    tasks: tasks ?? this.tasks,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    externalId: externalId ?? this.externalId,
    revision: revision ?? this.revision,
    contentLocked: contentLocked ?? this.contentLocked,
  );
}

final class MemorizationPlan {
  const MemorizationPlan({
    required this.id,
    required this.title,
    required this.translationId,
    required this.bookId,
    required this.startChapter,
    required this.endChapter,
    required this.days,
    required this.startDate,
    required this.endDate,
    required this.completedTasks,
    required this.totalTasks,
    required this.sourceKind,
    required this.sourceUrl,
    required this.externalId,
    required this.revision,
    required this.contentLocked,
  });

  final int id;
  final String title;
  final String translationId;
  final String bookId;
  final int startChapter;
  final int endChapter;
  final int days;
  final DateTime startDate;
  final DateTime endDate;
  final int completedTasks;
  final int totalTasks;
  final PlanSourceKind sourceKind;
  final String? sourceUrl;
  final String? externalId;
  final int revision;
  final bool contentLocked;
}

final class PlanTask {
  const PlanTask({
    required this.id,
    required this.planId,
    required this.dayIndex,
    required this.dueDate,
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
    required this.completed,
  });

  final int id;
  final int planId;
  final int dayIndex;
  final DateTime dueDate;
  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
  final bool completed;
}
