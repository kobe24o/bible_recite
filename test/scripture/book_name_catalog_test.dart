import 'package:bible_recite/src/features/scripture/data/asset_book_name_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const catalog = AssetBookNameCatalog.protestant66();

  test('resolves representative book names in all supported locales', () {
    expect(catalog.nameFor('GEN', const Locale('zh')), '创世记');
    expect(catalog.nameFor('PSA', const Locale('zh')), '诗篇');
    expect(catalog.nameFor('MAT', const Locale('zh')), '马太福音');
    expect(catalog.nameFor('JHN', const Locale('zh')), '约翰福音');
    expect(catalog.nameFor('PHP', const Locale('zh')), '腓立比书');
    expect(catalog.nameFor('REV', const Locale('zh')), '启示录');

    expect(catalog.nameFor('GEN', const Locale('zh', 'TW')), '創世記');
    expect(catalog.nameFor('PSA', const Locale('zh', 'TW')), '詩篇');
    expect(catalog.nameFor('MAT', const Locale('zh', 'TW')), '馬太福音');
    expect(catalog.nameFor('JHN', const Locale('zh', 'TW')), '約翰福音');
    expect(catalog.nameFor('PHP', const Locale('zh', 'TW')), '腓立比書');
    expect(catalog.nameFor('REV', const Locale('zh', 'TW')), '啟示錄');

    expect(catalog.nameFor('GEN', const Locale('en')), 'Genesis');
    expect(catalog.nameFor('PSA', const Locale('en')), 'Psalms');
    expect(catalog.nameFor('MAT', const Locale('en')), 'Matthew');
    expect(catalog.nameFor('JHN', const Locale('en')), 'John');
    expect(catalog.nameFor('PHP', const Locale('en')), 'Philippians');
    expect(catalog.nameFor('REV', const Locale('en')), 'Revelation');
  });

  test('uses English and OSIS fallbacks', () {
    expect(catalog.nameFor('GEN', const Locale('fr')), 'Genesis');
    expect(catalog.nameFor('XYZ', const Locale('zh')), 'XYZ');
  });

  test('formats localized chapter titles', () {
    expect(catalog.chapterLabel('JHN', 3, const Locale('zh')), '约翰福音 3章');
    expect(catalog.chapterLabel('JHN', 3, const Locale('zh', 'TW')), '約翰福音 3章');
    expect(catalog.chapterLabel('JHN', 3, const Locale('en')), 'John 3');
  });
}
