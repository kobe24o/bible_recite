import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../lib/cloud_plan_json.dart';

void main(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index + 1 < arguments.length; index += 2) {
    values[arguments[index]] = arguments[index + 1];
  }
  final classic = values['--classic'];
  final keyVerses = values['--key-verses'];
  final output = values['--output'];
  if (classic == null || keyVerses == null || output == null) {
    stderr.writeln(
      'Usage: dart run tool/cloud_plan/bin/generate_cloud_plan_json.dart '
      '--classic <path> --key-verses <path> --output <path>',
    );
    exitCode = 64;
    return;
  }
  final summary = const CloudPlanJsonGenerator().generate(
    CloudPlanJsonRequest(
      classicMarkdownPath: classic,
      keyVersesMarkdownPath: keyVerses,
      outputPath: output,
    ),
  );
  stdout.writeln(
    'Generated ${summary.classicPassageCount + summary.keyVersePassageCount} '
    'passages at $output',
  );
}
