import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../devotion/application/devotion_providers.dart';
import '../../devotion/domain/devotion_models.dart';
import '../../devotion/presentation/devotion_schedule_screen.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../statistics/domain/achievement.dart';
import '../../statistics/presentation/achievement_unlock_dialog.dart';
import '../../plans/domain/plan_models.dart';
import '../../plans/domain/plan_task_summary.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../../recitation/application/plan_recitation_builder.dart';
import '../../recitation/presentation/recitation_practice_screen.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../../widgets/completion_confetti.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int _revision = 0;
  bool _celebrating = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final repository = ref.watch(planRepositoryProvider);
    final bookNames = ref.watch(bookNameCatalogProvider);
    final devotion = ref
        .watch(cachedDevotionManifestProvider)
        .asData
        ?.value
        ?.dayFor(ref.watch(devotionTodayProvider));
    return Scaffold(
      appBar: AppBar(title: Text(localizations.todayTitle)),
      body: Stack(
        children: [
          repository.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _EmptyToday(localizations: localizations),
            data: (repository) => FutureBuilder<_TodayData>(
              key: ValueKey(_revision),
              future: _load(repository, devotionDay: devotion?.date),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (devotion == null &&
                    data.tasks.isEmpty &&
                    data.reviews.isEmpty) {
                  return _EmptyToday(
                    localizations: localizations,
                    showStartJourney: !data.hasActivePlan,
                  );
                }
                final pending = data.tasks
                    .where((task) => !task.completed)
                    .toList(growable: false);
                final completed = data.tasks
                    .where((task) => task.completed)
                    .toList(growable: false);
                final pendingReviews = data.reviews
                    .where((review) => !review.completed)
                    .toList(growable: false);
                final completedReviews = data.reviews
                    .where((review) => review.completed)
                    .toList(growable: false);
                final chinese =
                    Localizations.localeOf(context).languageCode == 'zh';
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (pending.isNotEmpty ||
                        pendingReviews.isNotEmpty ||
                        data.devotionPending) ...[
                      Text(
                        chinese ? '待完成' : 'To do',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (devotion != null && data.devotionPending)
                        _DevotionCard(
                          devotion: devotion,
                          bookNameFor: (bookId) => bookNames.nameFor(
                            bookId,
                            Localizations.localeOf(context),
                          ),
                          completed: false,
                          onOpen: () => _openDevotion(devotion.date),
                        ),
                      for (final review in pendingReviews)
                        _ReviewCard(
                          review: review,
                          bookName: bookNames.nameFor(
                            review.bookId,
                            Localizations.localeOf(context),
                          ),
                          onStart: () => _startReview(
                            review,
                            hasTodayDevotion: devotion != null,
                          ),
                        ),
                      for (final task in pending)
                        _TaskCard(
                          task: task,
                          plan: data.plans[task.planId],
                          bookNameFor: (bookId) => bookNames.nameFor(
                            bookId,
                            Localizations.localeOf(context),
                          ),
                          completed: false,
                          onChanged: () => setState(() => _revision++),
                          onAllTodayCompleted: () async {
                            if (await _allTodayCompleted(
                              repository,
                              hasTodayDevotion: devotion != null,
                            )) {
                              await _celebrate();
                            }
                          },
                          repository: repository,
                          onStart: () => _startTask(
                            task,
                            data.plans[task.planId],
                            repository,
                          ),
                        ),
                    ],
                    if (completed.isNotEmpty ||
                        completedReviews.isNotEmpty ||
                        data.devotionCompleted) ...[
                      const SizedBox(height: 16),
                      Text(
                        chinese ? '今日已完成' : 'Completed today',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (devotion != null && data.devotionCompleted)
                        _DevotionCard(
                          devotion: devotion,
                          bookNameFor: (bookId) => bookNames.nameFor(
                            bookId,
                            Localizations.localeOf(context),
                          ),
                          completed: true,
                          completionReason: data.devotionCompletionReason,
                          onOpen: () => _openDevotion(devotion.date),
                        ),
                      for (final review in completedReviews)
                        _ReviewCard(
                          review: review,
                          bookName: bookNames.nameFor(
                            review.bookId,
                            Localizations.localeOf(context),
                          ),
                          onStart: () => _startReview(
                            review,
                            hasTodayDevotion: devotion != null,
                          ),
                        ),
                      for (final task in completed)
                        _TaskCard(
                          task: task,
                          plan: data.plans[task.planId],
                          bookNameFor: (bookId) => bookNames.nameFor(
                            bookId,
                            Localizations.localeOf(context),
                          ),
                          completed: true,
                          onChanged: () => setState(() => _revision++),
                          onAllTodayCompleted: () async {
                            if (await _allTodayCompleted(
                              repository,
                              hasTodayDevotion: devotion != null,
                            )) {
                              await _celebrate();
                            }
                          },
                          repository: repository,
                          onStart: () => _startTask(
                            task,
                            data.plans[task.planId],
                            repository,
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_celebrating)
            const Positioned.fill(
              child: CompletionConfetti(key: Key('completion-confetti')),
            ),
        ],
      ),
    );
  }

  Future<void> _celebrate() async {
    setState(() => _celebrating = true);
    await Future<void>.delayed(const Duration(seconds: 8));
    if (mounted) setState(() => _celebrating = false);
  }

  Future<void> _startTask(
    PlanTask task,
    MemorizationPlan? plan,
    SqlitePlanRepository repository,
  ) async {
    if (plan == null) return;
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final request = await buildPlanRecitationRequest(
      scripture: scripture,
      plan: plan,
      tasks: await repository.listTasks(plan.id),
      selected: task,
      todayQuizEntry: true,
    );
    if (!mounted || request == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecitationPracticeScreen(request: request),
      ),
    );
    if (mounted) setState(() => _revision++);
  }

  Future<void> _startReview(
    EbbinghausReview review, {
    required bool hasTodayDevotion,
  }) async {
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final passage = await scripture.getPassage(
      review.translationId,
      PassageRange(
        start: (
          canonId: CanonId.protestant66,
          osisBookId: review.bookId,
          chapter: review.startChapter,
          verse: review.startVerse,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: review.bookId,
          chapter: review.endChapter,
          verse: review.endVerse,
        ),
      ),
    );
    final units = passage.units;
    if (!mounted || units.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecitationPracticeScreen(
          request: RecitationRequest(
            translationId: review.translationId,
            bookId: review.bookId,
            chapter: review.chapter,
            mode: RecitationMode.continuous,
            units: units,
            reviewId: review.id,
            quizScopes: [
              QuizScope(
                translationId: review.translationId,
                bookId: review.bookId,
                startChapter: review.startChapter,
                startVerse: review.startVerse,
                endChapter: review.endChapter,
                endVerse: review.endVerse,
              ),
            ],
            todayQuizEntry: true,
          ),
        ),
      ),
    );
    if (mounted) setState(() => _revision++);
    if (await _allTodayCompleted(
      await ref.read(planRepositoryProvider.future),
      hasTodayDevotion: hasTodayDevotion,
    )) {
      _celebrate();
    }
  }

  Future<bool> _allTodayCompleted(
    SqlitePlanRepository repository, {
    required bool hasTodayDevotion,
  }) async =>
      (await repository.dueTasks(DateTime.now())).isEmpty &&
      (await repository.dueEbbinghausReviews(DateTime.now())).isEmpty &&
      (!hasTodayDevotion ||
          await repository.isDevotionCompleted(
            ref.read(devotionTodayProvider),
          ));

  Future<void> _openDevotion(DateTime date) async {
    await context.push('/devotion/${devotionDateLabel(date)}');
    if (mounted) setState(() => _revision++);
  }

  Future<_TodayData> _load(
    SqlitePlanRepository repository, {
    required DateTime? devotionDay,
  }) async {
    final plans = await repository.listPlans();
    final tasks = await repository.dueTasks(
      DateTime.now(),
      includeCompleted: true,
    );
    final reviews = await repository.dueEbbinghausReviews(
      DateTime.now(),
      includeCompleted: true,
    );
    final devotionCompleted =
        devotionDay != null &&
        await repository.isDevotionCompleted(devotionDay);
    final devotionNote = devotionCompleted && devotionDay != null
        ? await repository.devotionNoteFor(devotionDay)
        : null;
    return _TodayData(
      plans: {for (final plan in plans) plan.id: plan},
      tasks: tasks,
      reviews: reviews,
      devotionCompleted: devotionCompleted,
      devotionCompletionReason: devotionCompleted
          ? devotionNote == null
                ? '已完成灵修阅读'
                : '已记录灵修笔记'
          : null,
      hasActivePlan: plans.any(
        (plan) =>
            !plan.paused &&
            plan.totalTasks > 0 &&
            plan.completedTasks < plan.totalTasks,
      ),
    );
  }
}

class _DevotionCard extends StatelessWidget {
  const _DevotionCard({
    required this.devotion,
    required this.bookNameFor,
    required this.completed,
    required this.onOpen,
    this.completionReason,
  });

  final DevotionDay devotion;
  final String Function(String bookId) bookNameFor;
  final bool completed;
  final String? completionReason;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: Key('today-devotion-${devotionDateLabel(devotion.date)}'),
      onTap: onOpen,
      leading: CircleAvatar(
        child: Icon(
          completed ? Icons.check_rounded : Icons.auto_stories_outlined,
        ),
      ),
      title: const Text('今日灵修'),
      subtitle: Text(
        completed
            ? completionReason ?? '已完成灵修'
            : devotion.passages
                  .map(
                    (passage) => devotionPassageLabel(
                      passage,
                      bookNameFor(passage.bookId),
                    ),
                  )
                  .join('；'),
      ),
      trailing: completed
          ? const Icon(Icons.check_circle_rounded, color: Colors.green)
          : const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.bookName,
    required this.onStart,
  });

  final EbbinghausReview review;
  final String bookName;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onStart,
      leading: CircleAvatar(
        child: Icon(
          review.completed ? Icons.check_rounded : Icons.auto_awesome_rounded,
        ),
      ),
      title: const Text('艾宾浩斯复习'),
      subtitle: Text(
        '$bookName ${review.startChapter}:${review.startVerse}–${review.endVerse} · 第 ${review.intervalDays} 天复习',
      ),
      trailing: review.completed
          ? const Icon(Icons.check_circle_rounded, color: Colors.green)
          : const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.plan,
    required this.bookNameFor,
    required this.completed,
    required this.onChanged,
    required this.repository,
    required this.onStart,
    required this.onAllTodayCompleted,
  });

  final PlanTask task;
  final MemorizationPlan? plan;
  final String Function(String bookId) bookNameFor;
  final bool completed;
  final VoidCallback onChanged;
  final SqlitePlanRepository repository;
  final Future<void> Function() onStart;
  final Future<void> Function() onAllTodayCompleted;

  @override
  Widget build(BuildContext context) {
    final blocks = task.effectiveBlocks;
    final summary = compactPlanTaskSummary(blocks, bookNameFor: bookNameFor);
    return Card(
      child: ListTile(
        onTap: plan == null ? null : onStart,
        leading: CircleAvatar(
          child: Icon(
            completed ? Icons.check_rounded : Icons.menu_book_rounded,
          ),
        ),
        title: Text(plan?.title ?? '今日任务'),
        subtitle: Text(summary),
        trailing: IconButton(
          key: Key('${completed ? 'undo' : 'complete'}-task-${task.id}'),
          tooltip: completed ? '撤销完成' : '完成',
          onPressed: () async {
            final unlocked = await repository.setTaskCompleted(
              task.id,
              !completed,
            );
            Future<void>? completionCelebration;
            if (!completed) {
              final remaining = await repository.dueTasks(DateTime.now());
              if (remaining.isEmpty) {
                completionCelebration = onAllTodayCompleted();
              }
            }
            await completionCelebration;
            if (!completed && context.mounted) {
              for (final achievement in unlocked) {
                await showAchievementUnlockDialog(
                  context,
                  AchievementProgress(
                    definition: achievement.definition,
                    current:
                        achievement.definition.target * achievement.awardCount,
                    satisfied: true,
                    unlockedAt: achievement.unlockedAt,
                    awardCount: achievement.awardCount,
                  ),
                  newlyUnlocked: true,
                );
                break;
              }
            }
            onChanged();
          },
          icon: Icon(
            completed ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
          ),
        ),
      ),
    );
  }
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday({
    required this.localizations,
    this.showStartJourney = false,
  });

  final AppLocalizations localizations;
  final bool showStartJourney;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.today_outlined, size: 64),
          const SizedBox(height: 16),
          Text(
            showStartJourney
                ? '开始背诵之旅吧，选择一份计划把神的话藏在心里。'
                : localizations.todayEmpty,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go(showStartJourney ? '/plans' : '/bible'),
            child: Text(
              showStartJourney ? '开始背诵之旅' : localizations.browseBible,
            ),
          ),
        ],
      ),
    ),
  );
}

final class _TodayData {
  const _TodayData({
    required this.plans,
    required this.tasks,
    required this.reviews,
    required this.devotionCompleted,
    required this.devotionCompletionReason,
    required this.hasActivePlan,
  });

  final Map<int, MemorizationPlan> plans;
  final List<PlanTask> tasks;
  final List<EbbinghausReview> reviews;
  final bool devotionCompleted;
  final String? devotionCompletionReason;
  final bool hasActivePlan;
  bool get devotionPending => !devotionCompleted;
}
