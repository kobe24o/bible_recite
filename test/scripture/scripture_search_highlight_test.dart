import 'package:bible_recite/src/features/scripture/presentation/scripture_search_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps full scripture text while highlighting every search match', () {
    const style = TextStyle(fontWeight: FontWeight.bold);
    final spans = scriptureSearchHighlightSpans(
      text: 'For God so loved the world, God is love.',
      query: 'god',
      matchStyle: style,
    );

    expect(
      spans.map((span) => span.text).join(),
      'For God so loved the world, God is love.',
    );
    expect(
      spans.where((span) => span.style?.fontWeight == FontWeight.bold),
      hasLength(2),
    );
  });
}
