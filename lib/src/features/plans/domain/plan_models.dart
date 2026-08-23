enum PlanSourceKind { local, preset, cloud }

final class PlanTaskBlock {
  const PlanTaskBlock({
    required this.id,
    required this.taskId,
    required this.sortOrder,
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final int id;
  final int taskId;
  final int sortOrder;
  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;

  String get rangeLabel => startChapter == endChapter
      ? startVerse == endVerse
            ? '$startChapter:$startVerse'
            : '$startChapter:$startVerse–$endVerse'
      : '$startChapter:$startVerse–$endChapter:$endVerse';
}

final class NewPlanTaskBlock {
  const NewPlanTaskBlock({
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final String? bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
}

final class NewPlanTask {
  const NewPlanTask({
    required this.dayIndex,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
    this.bookId,
    this.blocks = const [],
  });

  final int dayIndex;
  final String? bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;
  final List<NewPlanTaskBlock> blocks;

  List<NewPlanTaskBlock> effectiveBlocks(String fallbackBookId) =>
      blocks.isNotEmpty
      ? blocks
      : [
          NewPlanTaskBlock(
            bookId: bookId ?? fallbackBookId,
            startChapter: startChapter,
            startVerse: startVerse,
            endChapter: endChapter,
            endVerse: endVerse,
          ),
        ];
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
    this.ebbinghausEnabled = false,
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
  final bool ebbinghausEnabled;

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
    bool? ebbinghausEnabled,
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
    ebbinghausEnabled: ebbinghausEnabled ?? this.ebbinghausEnabled,
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
    this.ebbinghausEnabled = false,
    this.paused = false,
    this.recitationSessions = 0,
    this.averageAccuracy = 0,
    this.totalRecitationSeconds = 0,
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
  final bool ebbinghausEnabled;
  final bool paused;
  final int recitationSessions;
  final double averageAccuracy;
  final int totalRecitationSeconds;
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
    this.blocks = const [],
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
  final List<PlanTaskBlock> blocks;

  List<PlanTaskBlock> get effectiveBlocks => blocks.isNotEmpty
      ? blocks
      : [
          PlanTaskBlock(
            id: 0,
            taskId: id,
            sortOrder: 0,
            bookId: bookId,
            startChapter: startChapter,
            startVerse: startVerse,
            endChapter: endChapter,
            endVerse: endVerse,
          ),
        ];
}
