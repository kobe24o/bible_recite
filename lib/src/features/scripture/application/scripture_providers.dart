import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/scripture_pack_installer.dart';
import '../data/sqlite_scripture_repository.dart';
import '../domain/scripture_repository.dart';

final scripturePackRegistryProvider = FutureProvider<ScripturePackRegistry>((
  ref,
) async {
  final supportDirectory = await getApplicationSupportDirectory();
  return ScripturePackInstaller(
    applicationSupportDirectory: supportDirectory,
    assetBundle: rootBundle,
  ).ensureInstalled();
});

final scriptureRepositoryProvider = FutureProvider<ScriptureRepository>((
  ref,
) async {
  final registry = await ref.watch(scripturePackRegistryProvider.future);
  return SqliteScriptureRepository(registry: registry);
});
