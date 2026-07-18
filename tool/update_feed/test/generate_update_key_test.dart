import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../bin/generate_update_key.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'update-key-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'creates Base64-encoded 32-byte Ed25519 seed and public key files',
    () async {
      final privateOutput = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}private.txt',
      );
      final publicOutput = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}public.txt',
      );

      final result = await generateUpdateKey(
        privateOutput: privateOutput,
        publicOutput: publicOutput,
      );

      expect(result.privateOutput, privateOutput);
      expect(result.publicOutput, publicOutput);
      expect(base64Decode(await privateOutput.readAsString()), hasLength(32));
      expect(base64Decode(await publicOutput.readAsString()), hasLength(32));
    },
  );

  test('refuses to overwrite either key output path', () async {
    final privateOutput = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}private.txt',
    );
    final publicOutput = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}public.txt',
    );
    await privateOutput.writeAsString('existing-private');

    await expectLater(
      generateUpdateKey(
        privateOutput: privateOutput,
        publicOutput: publicOutput,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await privateOutput.readAsString(), 'existing-private');
    expect(await publicOutput.exists(), isFalse);
  });

  test('refuses to use the same path for the private and public key', () async {
    final output = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}key.txt',
    );

    await expectLater(
      generateUpdateKey(privateOutput: output, publicOutput: output),
      throwsA(isA<FileSystemException>()),
    );

    expect(await output.exists(), isFalse);
  });
}
