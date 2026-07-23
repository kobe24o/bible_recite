import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../plans/domain/plan_models.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../../recitation/application/plan_recitation_builder.dart';
import '../../recitation/presentation/recitation_practice_screen.dart';
import '../../scripture/application/scripture_providers.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final repository = ref.watch(planRepositoryProvider);
    final bookNames = ref.watch(bookNameCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.todayTitle)),
      body: repository.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _EmptyToday(localizations: localizations),
        data: (repository) => FutureBuilder<_TodayData>(
          key: ValueKey(_revision),
          future: _load(repository),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            if (data.tasks.isEmpty && data.reviews.isEmpty) {
              return _EmptyToday(localizations: localizations);
            }
            final pending = data.tasks
                .where((task) => !task.completed)
                .toList(growable: false);
            final completed = data.tasks
                .where((task) => task.completed)
                .toList(growable: false);
            final chinese =
                Localizations.localeOf(context).languageCode == 'zh';
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (pending.isNotEmpty || data.reviews.isNotEmpty) ...[
                  Text(
                    chinese ? '待完成' : 'To do',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final review in data.reviews)
                    _ReviewCard(
                      review: review,
                      bookName: bookNames.nameFor(
                        review.bookId,
                        Localizations.localeOf(context),
                      ),
                    ),
                  for (final task in pending)
                    _TaskCard(
                      task: task,
                      plan: data.plans[task.planId],
                      completed: false,
                      onChanged: () => setState(() => _revision++),
                      repository: repository,
                      onStart: () =>
                          _startTask(task, data.plans[task.planId], repository),
                    ),
                ],
                if (completed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    chinese ? '今日已完成' : 'Completed today',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final task in completed)
                    _TaskCard(
                      task: task,
                      plan: data.plans[task.planId],
                      completed: true,
                      onChanged: () => setState(() => _revision++),
                      repository: repository,
                      onStart: () =>
                          _startTask(task, data.plans[task.planId], repository),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
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
    );
    if (!mounted || request == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecitationPracticeScreen(request: request),
      ),
    );
  }

  Future<_TodayData> _load(SqlitePlanRepository repository) async {
    final plans = await repository.listPlans();
    final tasks = await repository.dueTasks(
      DateTime.now(),
      includeCompleted: true,
    );
    final reviews = await repository.dueEbbinghausReviews(DateTime.now());
    return _TodayData(
      plans: {for (final plan in plans) plan.id: plan},
      tasks: tasks,
      reviews: reviews,
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.bookName});

  final EbbinghausReview review;
  final String bookName;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: () => context.go(
        '/bible/${review.translationId}/${review.bookId}/${review.chapter}',
        extra: review.id,
      ),
      leading: const CircleAvatar(child: Icon(Icons.auto_awesome_rounded)),
      title: const Text('艾宾浩斯复习'),
      subtitle: Text(
        '$bookName ${review.chapter}章 · 第 ${review.intervalDays} 天复习',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.plan,
    required this.completed,
    required this.onChanged,
    required this.repository,
    required this.onStart,
  });

  final PlanTask task;
  final MemorizationPlan? plan;
  final bool completed;
  final VoidCallback onChanged;
  final SqlitePlanRepository repository;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final range = task.startChapter == task.endChapter
        ? '${task.startChapter}:${task.startVerse}–${task.endVerse}'
        : '${task.startChapter}:${task.startVerse}–'
              '${task.endChapter}:${task.endVerse}';
    return Card(
      child: ListTile(
        onTap: plan == null ? null : onStart,
        leading: CircleAvatar(
          child: Icon(
            completed ? Icons.check_rounded : Icons.menu_book_rounded,
          ),
        ),
        title: Text(plan?.title ?? '今日任务'),
        subtitle: Text(range),
        trailing: IconButton(
          key: Key('${completed ? 'undo' : 'complete'}-task-${task.id}'),
          tooltip: completed ? '撤销完成' : '完成',
          onPressed: () async {
            await repository.setTaskCompleted(task.id, !completed);
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
  const _EmptyToday({required this.localizations});

  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.today_outlined, size: 64),
          const SizedBox(height: 16),
          Text(localizations.todayEmpty, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go('/bible'),
            child: Text(localizations.browseBible),
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
  });

  final Map<int, MemorizationPlan> plans;
  final List<PlanTask> tasks;
  final List<EbbinghausReview> reviews;
}
