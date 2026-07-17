// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import '../lib/feishu_csv_generator.dart';

void main(List<String> args) {
  final options = _parseOptions(args);
  final classic = options['classic'];
  final keyVerses = options['key-verses'];
  final output = options['output'];
  if (classic == null || keyVerses == null || output == null) {
    stderr.writeln(
      'Usage: dart run generate_feishu_template.dart '
      '--classic <path> --key-verses <path> --output <directory>',
    );
    exitCode = 64;
    return;
  }

  final summary = const FeishuTemplateGenerator().generate(
    TemplateGenerationRequest(
      classicMarkdownPath: classic,
      keyVersesMarkdownPath: keyVerses,
      outputDirectoryPath: output,
    ),
  );
  stdout
    ..writeln('chapters: ${summary.chapterCount}')
    ..writeln('plans: ${summary.planCount}')
    ..writeln('passages: ${summary.passageCount}')
    ..writeln('classic-passages: ${summary.classicPassageCount}')
    ..writeln('key-verses-66: ${summary.keyVersePassageCount}');
}

Map<String, String> _parseOptions(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      throw const FormatException('Options must be supplied as --name value');
    }
    result[args[index].substring(2)] = args[index + 1];
  }
  return result;
}
