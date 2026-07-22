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
  if (_normalizedOutputPath(privateOutput) ==
      _normalizedOutputPath(publicOutput)) {
    throw FileSystemException(
      'Private and public key output paths must be different.',
      privateOutput.path,
    );
  }

  final privateDirectory = privateOutput.parent;
  final publicDirectory = publicOutput.parent;
  if (!await privateDirectory.exists() || !await publicDirectory.exists()) {
    throw const FileSystemException(
      'Key output directories must already exist.',
    );
  }

  // Exclusive creation prevents ordinary accidental overwrites. This one-time
  // CLI assumes its output directory is not concurrently mutated by the same
  // user while it is running.
  RandomAccessFile? privateFile;
  RandomAccessFile? publicFile;
  try {
    await privateOutput.create(exclusive: true);
    privateFile = await privateOutput.open(mode: FileMode.append);
    await publicOutput.create(exclusive: true);
    publicFile = await publicOutput.open(mode: FileMode.append);
  } on FileSystemException catch (error) {
    await _closeQuietly(publicFile);
    await _closeQuietly(privateFile);
    throw FileSystemException(
      'Unable to reserve both update key outputs; no key material was written.',
      error.path,
      error.osError,
    );
  }

  try {
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();

    await publicFile.writeString(base64Encode(publicKey.bytes));
    await publicFile.flush();
    await privateFile.writeString(base64Encode(seed));
    await privateFile.flush();
    return GeneratedUpdateKeyFiles(
      privateOutput: privateOutput,
      publicOutput: publicOutput,
    );
  } finally {
    await _closeQuietly(publicFile);
    await _closeQuietly(privateFile);
  }
}

String _normalizedOutputPath(File file) {
  final path = file.absolute.uri.normalizePath().toFilePath(
    windows: Platform.isWindows,
  );
  return Platform.isWindows ? path.toLowerCase() : path;
}

Future<void> _closeQuietly(RandomAccessFile? file) async {
  if (file == null) {
    return;
  }
  try {
    await file.close();
  } on FileSystemException {
    // Continue cleanup for files exclusively created by this invocation.
  }
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
