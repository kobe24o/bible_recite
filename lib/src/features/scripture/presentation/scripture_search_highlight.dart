import 'package:flutter/material.dart';

/// Splits [text] into spans while preserving the original characters and
/// highlighting every literal occurrence of [query]. English matching is
/// case-insensitive, while Chinese text naturally retains its exact form.
List<TextSpan> scriptureSearchHighlightSpans({
  required String text,
  required String query,
  TextStyle? matchStyle,
}) {
  final needle = query.trim();
  if (needle.isEmpty || text.isEmpty) return [TextSpan(text: text)];

  final haystack = text.toLowerCase();
  final normalizedNeedle = needle.toLowerCase();
  final spans = <TextSpan>[];
  var cursor = 0;
  while (cursor < text.length) {
    final match = haystack.indexOf(normalizedNeedle, cursor);
    if (match < 0) {
      spans.add(TextSpan(text: text.substring(cursor)));
      break;
    }
    if (match > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match)));
    }
    spans.add(
      TextSpan(
        text: text.substring(match, match + needle.length),
        style: matchStyle,
      ),
    );
    cursor = match + needle.length;
  }
  return spans;
}
