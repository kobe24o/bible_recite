import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../../plans/data/sqlite_plan_repository.dart';

/// A random installation alias, never a hardware identifier.
final class DeviceAliasSource {
  DeviceAliasSource({
    Future<String> Function()? modelReader,
    String Function()? aliasGenerator,
  }) : _modelReader = modelReader ?? _readModel,
       _aliasGenerator = aliasGenerator ?? _generate;
  final Future<String> Function() _modelReader;
  final String Function() _aliasGenerator;
  Future<String> loadOrCreate(SqlitePlanRepository repository) async {
    var alias = await repository.getSetting('leaderboard_install_alias', '');
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(alias)) {
      alias = _aliasGenerator();
      await repository.setSetting('leaderboard_install_alias', alias);
    }
    var model = await repository.getSetting('leaderboard_device_model', '');
    if (model.isEmpty) {
      try {
        model = await _modelReader();
      } catch (_) {
        model = '';
      }
      model = model.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
      model = String.fromCharCodes(model.runes.take(50));
      if (model.isEmpty) model = '本机设备';
      await repository.setSetting('leaderboard_device_model', model);
    }
    return '$model · $alias';
  }

  static String _generate() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      6,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static Future<String> _readModel() async {
    if (kIsWeb) return '本机设备';
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final device = await plugin.androidInfo;
      return '${device.manufacturer} ${device.model}';
    }
    if (Platform.isIOS) return (await plugin.iosInfo).model;
    // Desktop's host/computer name can identify a person, so never use it.
    return '本机设备';
  }
}
