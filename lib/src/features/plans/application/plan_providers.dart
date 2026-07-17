import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/sqlite_plan_repository.dart';
import '../data/cloud_plan_feed_client.dart';
import '../domain/cloud_plan_importer.dart';
import '../domain/cloud_plan_manifest.dart';

const officialCloudPlanGcoreUrl =
    'https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/cloud-plans.json';
const officialCloudPlanFastlyUrl =
    'https://fastly.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/cloud-plans.json';
const officialCloudPlanCdnUrl =
    'https://cdn.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/cloud-plans.json';
const officialCloudPlanRawUrl =
    'https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/cloud-plans.json';
const defaultCloudPlanSourceUrl = officialCloudPlanGcoreUrl;

List<Uri> cloudPlanSourceCandidates(String source) {
  const officialSources = {
    officialCloudPlanGcoreUrl,
    officialCloudPlanFastlyUrl,
    officialCloudPlanCdnUrl,
    officialCloudPlanRawUrl,
  };
  if (officialSources.contains(source)) {
    return [
      Uri.parse(officialCloudPlanGcoreUrl),
      Uri.parse(officialCloudPlanFastlyUrl),
      Uri.parse(officialCloudPlanCdnUrl),
      Uri.parse(officialCloudPlanRawUrl),
    ];
  }
  return [Uri.parse(source)];
}

final bundledCloudPlanManifestProvider = FutureProvider<CloudPlanManifest>((
  ref,
) async {
  final source = await rootBundle.loadString('assets/cloud_plans.json');
  return CloudPlanManifest.parse(source);
});

final cloudPlanFeedClientProvider = Provider<CloudPlanFeedClient>(
  (ref) => CloudPlanFeedClient(),
);

final cloudPlanImporterProvider = Provider<CloudPlanImporter>(
  (ref) => const CloudPlanImporter(),
);

final planRepositoryProvider = FutureProvider<SqlitePlanRepository>((
  ref,
) async {
  final directory = await getApplicationSupportDirectory();
  final database = sqlite3.open('${directory.path}/user.sqlite');
  final repository = SqlitePlanRepository(database);
  ref.onDispose(repository.close);
  return repository;
});
