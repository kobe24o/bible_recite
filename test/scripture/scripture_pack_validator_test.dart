import 'dart:io';

import 'package:bible_recite/src/features/scripture/data/scripture_pack_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects a database whose digest differs from its manifest', () async {
    final fixture = await Directory.systemTemp.createTemp('corrupt-pack-');
    addTearDown(() => fixture.delete(recursive: true));
    await File(
      'assets/scripture/eng-web/manifest.json',
    ).copy('${fixture.path}${Platform.pathSeparator}manifest.json');
    await File(
      '${fixture.path}${Platform.pathSeparator}scripture.sqlite',
    ).writeAsString('corrupt');

    await expectLater(
      ScripturePackValidator().validate(fixture),
      throwsA(isA<ScripturePackIntegrityException>()),
    );
  });
}
