import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/application/plan_providers.dart';
import '../../plans/application/preset_plan_sync.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../plans/domain/plan_models.dart';
import '../../plans/domain/cloud_plan_manifest.dart';
import '../../scripture/domain/book_name_catalog.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../../scripture/application/scripture_providers.dart';
import '../domain/achievement.dart';
import 'achievement_coverage.dart';

final displayedAchievementsLoaderProvider =
    Provider<Future<List<AchievementProgress>> Function(SqlitePlanRepository)>(
  (ref) => (repository) => loadDisplayedAchievements(
    repository,
    loadBundledManifest: () => ref.read(bundledCloudPlanManifestProvider.future),
    loadScripture: () => ref.read(scriptureRepositoryProvider.future),
    names: ref.read(bookNameCatalogProvider),
  ),
);

/// Gallery and leaderboard use the same displayed badge definitions and awards.
Future<List<AchievementProgress>> loadDisplayedAchievements(
  SqlitePlanRepository repository, {
  required Future<CloudPlanManifest> Function() loadBundledManifest,
  required Future<ScriptureRepository> Function() loadScripture,
  required BookNameCatalog names,
}) async {
  await repository.evaluateAndUnlockAchievements(source: 'backfill');
  final coverage = await _coverageAchievements(
    repository,
    loadBundledManifest: loadBundledManifest,
    loadScripture: loadScripture,
    names: names,
  );
  final achievements = [
    ...await repository.listAchievementProgress(),
    ...coverage.progress,
  ];
  final count = countDisplayedBadgeAwards(achievements).toString();
  if (await repository.getSetting('leaderboard_displayed_badge_count', '') != count) {
    await repository.setSetting('leaderboard_displayed_badge_count', count);
    await repository.markLeaderboardDirty();
  }
  return achievements;
}

Future<ExternalAchievementSyncResult> _coverageAchievements(
  SqlitePlanRepository repository, {
  required Future<CloudPlanManifest> Function() loadBundledManifest,
  required Future<ScriptureRepository> Function() loadScripture,
  required BookNameCatalog names,
}) async {
    final metrics = await repository.listRecitationVerseMetrics();
    final definitions = <AchievementDefinition>[];
    final satisfied = <String>{};
    final currentValues = <String, double>{};
    final plans = await repository.listPlans();
    final presetPlans = plans
        .where(
          (plan) =>
              plan.sourceKind == PlanSourceKind.preset ||
              plan.sourceKind == PlanSourceKind.cloud,
        )
        .toList();
    final savedByExternalId = {
      for (final plan in presetPlans)
        if (plan.externalId != null) plan.externalId!: plan,
    };
    final cachedManifest = await loadCachedPresetPlanManifest(repository);
    final manifest =
        cachedManifest ??
        await loadBundledManifest();
    final knownExternalIds = <String>{};
    for (final template in manifest.plans) {
      final id = 'preset_plan_${template.id}';
      final saved = savedByExternalId[template.id];
      definitions.add(
        AchievementDefinition(
          id: id,
          title: '${template.title}勋章',
          description: '完成预置计划《${template.title}》',
          metric: AchievementMetric.sessions,
          target: 1,
          repeatable: true,
        ),
      );
      if (saved != null &&
          saved.totalTasks > 0 &&
          saved.completedTasks == saved.totalTasks) {
        satisfied.add(id);
      }
      currentValues[id] = saved == null || saved.totalTasks == 0
          ? 0
          : saved.completedTasks / saved.totalTasks;
      knownExternalIds.add(template.id);
    }
    for (final plan in presetPlans.where(
      (plan) =>
          plan.externalId == null ||
          !knownExternalIds.contains(plan.externalId),
    )) {
      final id = 'preset_plan_${plan.externalId ?? plan.id}';
      definitions.add(
        AchievementDefinition(
          id: id,
          title: '${plan.title}勋章',
          description: '完成预置计划《${plan.title}》',
          metric: AchievementMetric.sessions,
          target: 1,
          repeatable: true,
        ),
      );
      if (plan.totalTasks > 0 && plan.completedTasks == plan.totalTasks) {
        satisfied.add(id);
      }
      currentValues[id] = plan.totalTasks == 0
          ? 0
          : plan.completedTasks / plan.totalTasks;
    }
    if (metrics.isEmpty) {
      return repository.syncExternalAchievementsWithUnlocks(
        definitions,
        satisfied,
        currentValues,
      );
    }
    final presetCoverage = await repository.syncExternalAchievementsWithUnlocks(
      definitions,
      satisfied,
      currentValues,
    );
    final scriptureCoverage = await syncScriptureCoverageAchievements(
      repository: repository,
      scripture: await loadScripture(),
      names: names,
    );
    return ExternalAchievementSyncResult(
      progress: [...presetCoverage.progress, ...scriptureCoverage.progress],
      unlocked: [...presetCoverage.unlocked, ...scriptureCoverage.unlocked],
    );
  }

