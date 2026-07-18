import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

final class GeneratedUpdateKeyFiles {
  const GeneratedUpdateKeyFiles({
    required this.privateOutput,
    required this.publicOutput,
  });

  final File privateOutput;
  final File publicOutput;
}

Future<GeneratedUpdateKeyFiles> generateUpdateKey({
  required File privateOutput,
  required File publicOutput,
}) async {
  if (privateOutput.absolute.path == publicOutput.absolute.path) {
    throw FileSystemException(
      'Private and public key output paths must be different.',
      privateOutput.path,
    );
  }
  if (await privateOutput.exists()) {
    throw FileSystemException(
      'Refusing to overwrite an existing private key file.',
      privateOutput.path,
    );
  }
  if (await publicOutput.exists()) {
    throw FileSystemException(
      'Refusing to overwrite an existing public key file.',
      publicOutput.path,
    );
  }

  final privateDirectory = privateOutput.parent;
  final publicDirectory = publicOutput.parent;
  if (!await privateDirectory.exists() || !await publicDirectory.exists()) {
    throw const FileSystemException(
      'Key output directories must already exist.',
    );
  }

  final random = Random.secure();
  final seed = List<int>.generate(32, (_) => random.nextInt(256));
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();

  await privateOutput.writeAsString(base64Encode(seed), flush: true);
  await publicOutput.writeAsString(base64Encode(publicKey.bytes), flush: true);
  return GeneratedUpdateKeyFiles(
    privateOutput: privateOutput,
    publicOutput: publicOutput,
  );
}

Future<void> main(List<String> arguments) async {
  final outputs = _parseOutputArguments(arguments);
  final generated = await generateUpdateKey(
    privateOutput: File(outputs.privateOutput),
    publicOutput: File(outputs.publicOutput),
  );
  stdout.writeln(
    'Created update signing public key: ${generated.publicOutput.path}',
  );
}

_UpdateKeyOutputs _parseOutputArguments(List<String> arguments) {
  String? privateOutput;
  String? publicOutput;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--private-output':
        privateOutput = _argumentValue(arguments, ++index, '--private-output');
        break;
      case '--public-output':
        publicOutput = _argumentValue(arguments, ++index, '--public-output');
        break;
      default:
        throw ArgumentError('Unknown argument: ${arguments[index]}');
    }
  }
  if (privateOutput == null || publicOutput == null) {
    throw ArgumentError(
      'Both --private-output and --public-output are required.',
    );
  }
  return _UpdateKeyOutputs(
    privateOutput: privateOutput,
    publicOutput: publicOutput,
  );
}

String _argumentValue(List<String> arguments, int index, String flag) {
  if (index >= arguments.length || arguments[index].startsWith('--')) {
    throw ArgumentError('Missing value for $flag.');
  }
  return arguments[index];
}

final class _UpdateKeyOutputs {
  const _UpdateKeyOutputs({
    required this.privateOutput,
    required this.publicOutput,
  });

  final String privateOutput;
  final String publicOutput;
}
