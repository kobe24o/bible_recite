import 'dart:convert';

import '../data/cloud_plan_feed_client.dart';
import '../data/sqlite_plan_repository.dart';
import '../domain/cloud_plan_manifest.dart';
import 'plan_providers.dart';

const presetPlanManifestSettingKey = 'preset_plan_cached_manifest';
const presetPlanNewSettingKey = 'preset_plan_new_revisions';

final class PresetPlanSyncResult {
  const PresetPlanSyncResult({
    required this.manifest,
    required this.newPlanIds,
  });

  final CloudPlanManifest manifest;
  final Set<String> newPlanIds;
}

Future<PresetPlanSyncResult> syncPresetPlans({
  required SqlitePlanRepository repository,
  required CloudPlanFeedClient client,
}) async {
  final source = await repository.getSetting(
    'cloud_plan_source_url',
    defaultCloudPlanSourceUrl,
  );
  final previous = await loadCachedPresetPlanManifest(repository);
  final manifest = await client.fetchFirst(cloudPlanSourceCandidates(source));
  final previouslyKnown = {
    for (final plan in previous?.plans ?? const <CloudPlanTemplate>[])
      plan.id: plan.revision,
  };
  final existingNew = await loadNewPresetPlanIds(repository);
  final currentIds = manifest.plans.map((plan) => plan.id).toSet();
  final nextNew = <String>{
    ...existingNew.where(currentIds.contains),
    for (final plan in manifest.plans)
      if ((previouslyKnown[plan.id] ?? 0) < plan.revision) plan.id,
  };
  await repository.setSetting(
    presetPlanManifestSettingKey,
    jsonEncode(manifest.toJson()),
  );
  await repository.setSetting(
    presetPlanNewSettingKey,
    jsonEncode({
      for (final plan in manifest.plans)
        if (nextNew.contains(plan.id)) plan.id: plan.revision,
    }),
  );
  return PresetPlanSyncResult(manifest: manifest, newPlanIds: nextNew);
}

Future<CloudPlanManifest?> loadCachedPresetPlanManifest(
  SqlitePlanRepository repository,
) async {
  final source = await repository.getSetting(presetPlanManifestSettingKey, '');
  if (source.isEmpty) return null;
  try {
    return CloudPlanManifest.parse(source);
  } on FormatException {
    return null;
  }
}

Future<Set<String>> loadNewPresetPlanIds(
  SqlitePlanRepository repository,
) async {
  final source = await repository.getSetting(presetPlanNewSettingKey, '{}');
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) return <String>{};
    return decoded.keys.toSet();
  } on FormatException {
    return <String>{};
  }
}

Future<void> markPresetPlanSeen(
  SqlitePlanRepository repository,
  String planId,
) async {
  final source = await repository.getSetting(presetPlanNewSettingKey, '{}');
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) return;
    decoded.remove(planId);
    await repository.setSetting(presetPlanNewSettingKey, jsonEncode(decoded));
  } on FormatException {
    await repository.setSetting(presetPlanNewSettingKey, '{}');
  }
}
