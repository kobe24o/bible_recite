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
  final manifest = await _fetchNewestManifest(
    client,
    cloudPlanSourceCandidates(source),
  );
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

/// Fetch every official mirror and use the manifest with the highest combined
/// template revision. A single stale CDN must not hide a newly published plan
/// description merely because it answered first.
Future<CloudPlanManifest> _fetchNewestManifest(
  CloudPlanFeedClient client,
  Iterable<Uri> sources,
) async {
  final manifests = <CloudPlanManifest>[];
  final errors = <String>[];
  for (final source in sources) {
    try {
      manifests.add(await client.fetch(source));
    } on CloudPlanFeedException catch (error) {
      errors.add('${source.host}: ${error.message}');
    }
  }
  if (manifests.isEmpty) {
    throw CloudPlanFeedException(
      errors.isEmpty ? '未获取到云端计划' : errors.join('；'),
    );
  }
  manifests.sort(
    (left, right) => _revisionScore(right).compareTo(_revisionScore(left)),
  );
  return manifests.first;
}

int _revisionScore(CloudPlanManifest manifest) =>
    manifest.plans.fold(0, (score, plan) => score + plan.revision);

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
