import 'dart:io';

import 'quiz_bank/lib/offline_quiz_bank_bundle.dart';

Future<void> main(List<String> arguments) async {
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      _usage();
    }
    values[arguments[index]] = arguments[index + 1];
  }
  final index = values['--index'];
  final shardDirectory = values['--shard-dir'];
  final outputBank = values['--output-bank'];
  final outputIndex = values['--output-index'];
  if (index == null ||
      shardDirectory == null ||
      outputBank == null ||
      outputIndex == null) {
    _usage();
  }
  await OfflineQuizBankBundle.build(
    indexFile: File(index),
    shardDirectory: Directory(shardDirectory),
    outputBank: File(outputBank),
    outputIndex: File(outputIndex),
  );
}

Never _usage() {
  throw ArgumentError(
    'Usage: dart run tool/bundle_quiz_bank.dart '
    '--index <index.json> --shard-dir <dir> '
    '--output-bank <bank.json> --output-index <index.json>',
  );
}
