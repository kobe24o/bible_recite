# Foundation and Scripture Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a tested Flutter application for Android, iOS, Windows, and macOS that installs three verified offline scripture packs and lets users browse the Protestant 66-book canon through translation, testament, book, chapter, verse, and bilingual passage views.

**Architecture:** Flutter owns presentation and application state; pure Dart domain types distinguish stable verse slots from source text units that may bridge multiple verses. A build-time eBible adapter parses both VPL text and its companion SQL metadata into read-only SQLite pack directories, then generates reviewed many-to-many parallel mappings. Runtime code depends only on `ScriptureRepository`, so future sources and versification systems can be added without changing browsing or later recitation features.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, Riverpod 3.3.2, go_router 17.3.0, sqlite3 3.3.4, path_provider 2.1.6, cryptography 2.9.0, archive 4.0.9, Flutter localization, flutter_test.

## Global Constraints

- Target exactly Android, iOS, Windows, and macOS in this phase; keep the domain and adapters portable to HarmonyOS NEXT.
- Use application ID `app.biblerecite` and working display name `圣经背诵` / `Scripture Recite`.
- Minimum targets: Android API 24, iOS 13, macOS 10.15, Windows 10 x64.
- Runtime scripture access must make zero network requests; downloads occur only in `tool/scripture_pack`.
- Canon is Protestant 66 books. Stable keys are `VerseKey(canonId, osisBookId, chapter, verse)`.
- Ship CUV simplified, CUV traditional, and WEB. Preserve source text exactly for display.
- Preserve verse bridges and explicit omitted slots. Never duplicate a bridged source text to make verse counts align.
- Bilingual display must use verified many-to-many mapping groups. Never join translations by list position or equal verse number alone.
- Pin every source URL and SHA-256; a hash mismatch must stop the build.
- Do not commit `.toolchains/` or `tool/scripture_pack/.cache/`.
- Every task uses TDD, runs `flutter analyze`, and ends with an intentional commit.

---

## File Structure

```text
scripts/bootstrap_flutter.ps1                 # installs and verifies Flutter 3.44.4 locally
.flutter-version                              # documents the pinned Flutter version
l10n.yaml                                     # Flutter ARB generation settings
lib/main.dart                                 # process entrypoint and ProviderScope
lib/src/app/app.dart                          # MaterialApp.router and localization
lib/src/app/router.dart                       # route table
lib/src/app/responsive_shell.dart             # bottom navigation / desktop rail
lib/l10n/app_zh.arb                           # simplified Chinese UI strings
lib/l10n/app_zh_Hant.arb                      # traditional Chinese UI strings
lib/l10n/app_en.arb                           # English UI strings
lib/src/features/scripture/domain/*.dart      # stable scripture types and repository contract
lib/src/features/scripture/data/*.dart        # pack validator, installer, and SQLite repository
lib/src/features/scripture/presentation/*.dart# directory and passage screens
assets/scripture/canon/protestant66.json      # ordered canon and localized book metadata
assets/scripture/versification/parallel_overrides.json # reviewed residual mappings with content hashes
assets/scripture/{cmn-cu89s,cmn-cu89t,eng-web}/ # manifest, scripture.sqlite, LICENSE.txt
tool/scripture_pack/source_catalog.json       # pinned authority URLs and archive hashes
tool/scripture_pack/bin/fetch_sources.dart    # verified source downloader
tool/scripture_pack/bin/build_all.dart        # deterministic pack build entrypoint
tool/scripture_pack/lib/*.dart                # VPL/SQL parsers, canon/mapping validators, SQLite builder
tool/scripture_pack/test/*.dart               # ingestion tests
test/app/*.dart                               # app shell tests
test/scripture/*.dart                         # domain, repository, and widget tests
```

## Task 1: Bootstrap the pinned four-platform Flutter shell

**Files:**
- Create: `scripts/bootstrap_flutter.ps1`
- Create: `.flutter-version`
- Modify: `.gitignore`
- Create via Flutter: `pubspec.yaml`, `analysis_options.yaml`, `android/`, `ios/`, `windows/`, `macos/`
- Create: `lib/main.dart`
- Create: `lib/src/app/app.dart`
- Create: `lib/src/app/router.dart`
- Create: `lib/src/app/responsive_shell.dart`
- Create: `l10n.yaml`, `lib/l10n/app_zh.arb`, `lib/l10n/app_zh_Hant.arb`, `lib/l10n/app_en.arb`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Produces: `BibleReciteApp`, `appRouter`, and `ResponsiveShell` for all later presentation tasks.
- Consumes: none.

- [ ] **Step 1: Add the reproducible Flutter bootstrap script**

```powershell
$ErrorActionPreference = 'Stop'
$version = '3.44.4'
$expectedSha256 = '8f2d6224fc6872d2f7f180de86cde989fcea3776efe0edf48a9aac2cd9be2b1b'
$root = Split-Path -Parent $PSScriptRoot
$toolchains = Join-Path $root '.toolchains'
$archive = Join-Path $toolchains "flutter-$version.zip"
$sdk = Join-Path $toolchains 'flutter'
$url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${version}-stable.zip"

New-Item -ItemType Directory -Force -Path $toolchains | Out-Null
if (-not (Test-Path $archive)) {
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
}
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($actual -ne $expectedSha256) { throw "Flutter archive hash mismatch: $actual" }
if (-not (Test-Path (Join-Path $sdk 'bin\flutter.bat'))) {
  Expand-Archive -LiteralPath $archive -DestinationPath $toolchains -Force
}
& (Join-Path $sdk 'bin\flutter.bat') --version
```

Append these ignore rules and create `.flutter-version` containing exactly `3.44.4`:

```gitignore
.toolchains/
tool/scripture_pack/.cache/
```

- [ ] **Step 2: Generate the platform projects and pin dependencies**

Run:

```powershell
.\scripts\bootstrap_flutter.ps1
$flutter = '.\.toolchains\flutter\bin\flutter.bat'
& $flutter create --platforms=android,ios,windows,macos --org app.biblerecite --project-name bible_recite .
& $flutter pub add flutter_riverpod:3.3.2 go_router:17.3.0 sqlite3:3.3.4 path_provider:2.1.6 cryptography:2.9.0 archive:4.0.9
& $flutter pub add flutter_localizations --sdk=flutter
& $flutter pub add intl:any
& $flutter pub add --dev flutter_lints:6.0.0 build_runner:2.15.1
```

Expected: `flutter create` succeeds and `pubspec.lock` pins Dart-compatible transitive versions.

- [ ] **Step 3: Write the failing responsive-shell test**

```dart
import 'package:bible_recite/src/app/responsive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses bottom navigation on a phone and rail on desktop', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ResponsiveShell(child: Text('body'))));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/app/app_shell_test.dart`

Expected: FAIL because `ResponsiveShell` does not exist.

- [ ] **Step 5: Implement the minimal app shell, routes, and localization**

```dart
// lib/src/app/responsive_shell.dart
import 'package:flutter/material.dart';

class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({required this.child, super.key});
  final Widget child;

  static const destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
    NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '圣经'),
    NavigationDestination(icon: Icon(Icons.event_note_outlined), label: '计划'),
    NavigationDestination(icon: Icon(Icons.insights_outlined), label: '统计'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Scaffold(
              body: Row(children: [
                const NavigationRail(
                  selectedIndex: 0,
                  destinations: [
                    NavigationRailDestination(icon: Icon(Icons.today_outlined), label: Text('今日')),
                    NavigationRailDestination(icon: Icon(Icons.menu_book_outlined), label: Text('圣经')),
                    NavigationRailDestination(icon: Icon(Icons.event_note_outlined), label: Text('计划')),
                    NavigationRailDestination(icon: Icon(Icons.insights_outlined), label: Text('统计')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ]),
            );
          }
          return Scaffold(body: child, bottomNavigationBar: const NavigationBar(destinations: destinations));
        },
      );
}
```

```dart
// lib/main.dart
import 'package:bible_recite/src/app/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: BibleReciteApp()));
```

Use `MaterialApp.router`, `GoRouter`, `flutter_localizations`, and generated ARB delegates in `BibleReciteApp`. Configure `l10n.yaml` with `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, and `output-localization-file: app_localizations.dart`.

- [ ] **Step 6: Verify the shell and platform floors**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat gen-l10n
.\.toolchains\flutter\bin\flutter.bat test test/app/app_shell_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: test PASS and analyzer reports `No issues found!`. Before committing, set Android namespace/application ID and MainActivity package to `app.biblerecite`, iOS/macOS bundle identifier to `app.biblerecite`, Android `minSdk = 24`, iOS deployment target `13.0`, and macOS deployment target `10.15`. Keep the Dart package name `bible_recite`; move the generated Android activity to `android/app/src/main/kotlin/app/biblerecite/MainActivity.kt` after changing its package declaration.

- [ ] **Step 7: Commit**

```powershell
git add .gitignore .flutter-version scripts pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml lib test android ios windows macos
git commit -m "chore: bootstrap four-platform Flutter app"
```

## Task 2: Define stable scripture domain types and repository interfaces

**Files:**
- Create: `lib/src/features/scripture/domain/scripture_models.dart`
- Create: `lib/src/features/scripture/domain/scripture_repository.dart`
- Test: `test/scripture/scripture_models_test.dart`

**Interfaces:**
- Produces: `CanonId`, `VerseKey`, `VerseUnit`, `PassageRange`, `LocatedPassageRange`, `TranslationInfo`, `BibleBook`, `Passage`, `ParallelGroup`, `ParallelPassage`, `ScriptureRepository`.
- Consumes: none.

- [ ] **Step 1: Write validation and equality tests**

```dart
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verse keys are stable value objects', () {
    const a = (canonId: CanonId.protestant66, osisBookId: 'JHN', chapter: 3, verse: 16);
    const b = (canonId: CanonId.protestant66, osisBookId: 'JHN', chapter: 3, verse: 16);
    expect(a, b);
  });

  test('passage range rejects reversed references', () {
    expect(
      () => PassageRange(
        start: (canonId: CanonId.protestant66, osisBookId: 'JHN', chapter: 3, verse: 18),
        end: (canonId: CanonId.protestant66, osisBookId: 'JHN', chapter: 3, verse: 16),
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run the tests and confirm the missing-type failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/scripture/scripture_models_test.dart`

Expected: FAIL because the scripture domain files do not exist.

- [ ] **Step 3: Implement the domain contract**

```dart
enum CanonId { protestant66 }

typedef VerseKey = ({CanonId canonId, String osisBookId, int chapter, int verse});

final class PassageRange {
  PassageRange({required this.start, required this.end}) {
    if (start.canonId != end.canonId || start.osisBookId != end.osisBookId) {
      throw ArgumentError('A passage range must stay in one book and canon');
    }
    final startsAfterEnd = start.chapter > end.chapter ||
        (start.chapter == end.chapter && start.verse > end.verse);
    if (startsAfterEnd) throw ArgumentError('Passage start must precede end');
  }
  final VerseKey start;
  final VerseKey end;
}

final class PassageSelection {
  PassageSelection(List<PassageRange> ranges)
      : ranges = List.unmodifiable(validateAndCanonicalizeRanges(ranges));
  final List<PassageRange> ranges;
}

final class TranslationInfo {
  const TranslationInfo({required this.id, required this.languageTag, required this.name, required this.canonId, required this.packId, required this.versificationId, required this.semanticSha256});
  final String id;
  final String languageTag;
  final String name;
  final CanonId canonId;
  final String packId;
  final String versificationId;
  final String semanticSha256;
}

final class BibleBook {
  const BibleBook({required this.osisId, required this.ordinal, required this.name, required this.chapterCount});
  final String osisId;
  final int ordinal;
  final String name;
  final int chapterCount;
}

enum SourceTextStatus { present, omitted }

final class VerseUnit {
  const VerseUnit({required this.translationId, required this.start, required this.end, required this.text, required this.status});
  final String translationId;
  final VerseKey start;
  final VerseKey end;
  final String text;
  final SourceTextStatus status;
}

final class Passage {
  const Passage({required this.range, required this.translationId, required this.units});
  final PassageRange range;
  final String translationId;
  final List<VerseUnit> units;
}

final class SelectedPassage {
  const SelectedPassage({required this.selection, required this.translationId, required this.passages});
  final PassageSelection selection;
  final String translationId;
  final List<Passage> passages;
  List<VerseUnit> get units => passages.expand((passage) => passage.units).toList(growable: false);
}

final class LocatedPassageRange {
  const LocatedPassageRange({required this.translationId, required this.range});
  final String translationId;
  final PassageRange range;
}

enum ParallelRelation { oneToOne, sourceBridge, targetBridge, crossChapterTargetBridge, relocated, sourceAbsent, targetAbsent }

final class ParallelGroup {
  const ParallelGroup({required this.id, required this.sourceUnits, required this.targetUnits, required this.relation, required this.provenance});
  final String id;
  final List<VerseUnit> sourceUnits;
  final List<VerseUnit> targetUnits;
  final ParallelRelation relation;
  final String provenance;
}

final class ParallelPassage {
  const ParallelPassage({required this.sourceRange, required this.targetTranslationId, required this.groups, required this.warnings});
  final LocatedPassageRange sourceRange;
  final String targetTranslationId;
  final List<ParallelGroup> groups;
  final List<String> warnings;
}
```

```dart
abstract interface class ScriptureRepository {
  Future<List<TranslationInfo>> listTranslations();
  Future<TranslationInfo> getTranslation(String id);
  Future<List<BibleBook>> listBooks(String translationId, CanonId canonId);
  Future<List<VerseUnit>> getChapter(String translationId, String osisBookId, int chapter);
  Future<Passage> getPassage(String translationId, PassageRange range);
  Future<SelectedPassage> getSelection(String translationId, PassageSelection selection);
  Future<ParallelPassage> resolveParallelPassage(LocatedPassageRange sourceRange, String targetTranslationId);
}
```

`PassageRange` is one inclusive, continuous, single-book interval. `PassageSelection` is the user-facing selection: a nonempty ordered list of canonical, nonoverlapping ranges, so it supports a chapter, a cross-book plan, or discrete verses without overloading range semantics. `getSelection` resolves each range in order and preserves indivisible bridge expansion warnings; plan generation, recitation, and persistence exchange `PassageSelection`, not an ambiguous serialized start/end pair.

- [ ] **Step 4: Run focused and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/scripture/scripture_models_test.dart
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/scripture/domain test/scripture/scripture_models_test.dart
git commit -m "feat: define stable scripture domain contract"
```

## Task 3: Pin and verify the three authoritative source archives

**Files:**
- Create: `tool/scripture_pack/source_catalog.json`
- Create: `tool/scripture_pack/lib/source_fetcher.dart`
- Create: `tool/scripture_pack/bin/fetch_sources.dart`
- Test: `tool/scripture_pack/test/source_fetcher_test.dart`

**Interfaces:**
- Produces: `SourceDescriptor` and `SourceFetcher.fetch(SourceDescriptor, Directory)`.
- Consumes: `cryptography` SHA-256 and eBible VPL archives.

- [ ] **Step 1: Add the exact source catalog**

```json
{
  "sources": [
    {"id":"cmn-cu89s","name":"新标点和合本（简体）","languageTag":"zh-Hans","detailsUrl":"https://ebible.org/details.php?id=cmn-cu89s","archiveUrl":"https://eBible.org/Scriptures/cmn-cu89s_vpl.zip","sha256":"22c3f71130742e7754e3870e55df6833406ab34a19abb891ac36443a14c13d13","licenseId":"public-domain"},
    {"id":"cmn-cu89t","name":"新標點和合本（繁體）","languageTag":"zh-Hant","detailsUrl":"https://ebible.org/details.php?id=cmn-cu89t","archiveUrl":"https://eBible.org/Scriptures/cmn-cu89t_vpl.zip","sha256":"510e281306ddc499e83b50279a73758b33f376ed3a47baaa76081d10523a28ea","licenseId":"public-domain"},
    {"id":"eng-web","name":"World English Bible","languageTag":"en","detailsUrl":"https://ebible.org/details.php?id=eng-web","archiveUrl":"https://eBible.org/Scriptures/eng-web_vpl.zip","sha256":"8e2a8bec53722b049c6a85bd7788fe638051a205bfddf73b03689edc6fa995cc","licenseId":"public-domain"}
  ]
}
```

- [ ] **Step 2: Write a failing hash-mismatch test with an injected downloader**

```dart
test('does not keep a source archive when sha256 differs', () async {
  final directory = await Directory.systemTemp.createTemp('source-fetcher-');
  addTearDown(() => directory.delete(recursive: true));
  final fetcher = SourceFetcher(download: (_) async => Uint8List.fromList([1, 2, 3]));
  final source = SourceDescriptor(
    id: 'fixture',
    archiveUrl: Uri.parse('https://example.invalid/source.zip'),
    sha256: List.filled(64, '0').join(),
  );
  await expectLater(fetcher.fetch(source, directory), throwsA(isA<SourceIntegrityException>()));
  expect(File('${directory.path}/fixture_vpl.zip').existsSync(), isFalse);
});
```

- [ ] **Step 3: Run it and verify failure**

Run: `.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/source_fetcher_test.dart`

Expected: FAIL because `SourceFetcher` is undefined.

- [ ] **Step 4: Implement atomic download and SHA-256 verification**

```dart
final class SourceFetcher {
  SourceFetcher({Future<Uint8List> Function(Uri)? download}) : _download = download ?? _downloadHttp;
  final Future<Uint8List> Function(Uri) _download;

  Future<File> fetch(SourceDescriptor source, Directory cache) async {
    await cache.create(recursive: true);
    final bytes = await _download(source.archiveUrl);
    final digest = await Sha256().hash(bytes);
    final actual = digest.bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    if (actual != source.sha256) throw SourceIntegrityException(source.id, actual);
    final target = File('${cache.path}/${source.id}_vpl.zip');
    final temporary = File('${target.path}.partial');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
    return target;
  }

  static Future<Uint8List> _downloadHttp(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: uri);
      return Uint8List.fromList(await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk)));
    } finally {
      client.close(force: true);
    }
  }
}
```

- [ ] **Step 5: Run unit tests and perform the real verified fetch**

Run:

```powershell
.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/source_fetcher_test.dart
.\.toolchains\flutter\bin\dart.bat run tool/scripture_pack/bin/fetch_sources.dart
Get-FileHash tool\scripture_pack\.cache\*_vpl.zip -Algorithm SHA256
```

Expected: tests PASS; all three printed hashes equal the catalog.

- [ ] **Step 6: Commit only catalog and tooling**

```powershell
git add tool/scripture_pack/source_catalog.json tool/scripture_pack/lib/source_fetcher.dart tool/scripture_pack/bin/fetch_sources.dart tool/scripture_pack/test/source_fetcher_test.dart
git commit -m "build: pin authoritative scripture sources"
```

## Task 4: Parse VPL text plus bridge metadata and enforce the Protestant 66-book canon

**Files:**
- Create: `assets/scripture/canon/protestant66.json`
- Create: `tool/scripture_pack/lib/vpl_parser.dart`
- Create: `tool/scripture_pack/lib/vpl_sql_metadata_parser.dart`
- Create: `tool/scripture_pack/lib/verse_unit_assembler.dart`
- Create: `tool/scripture_pack/lib/book_code_map.dart`
- Create: `tool/scripture_pack/lib/scripture_source_adapter.dart`
- Create: `tool/scripture_pack/lib/ebible_vpl_source_adapter.dart`
- Create: `tool/scripture_pack/lib/canon_validator.dart`
- Test: `tool/scripture_pack/test/vpl_parser_test.dart`
- Test: `tool/scripture_pack/test/vpl_sql_metadata_parser_test.dart`
- Test: `tool/scripture_pack/test/verse_unit_assembler_test.dart`
- Test: `tool/scripture_pack/test/canon_validator_test.dart`
- Test fixture: `tool/scripture_pack/test/fixtures/sample_vpl.txt`
- Test fixture: `tool/scripture_pack/test/fixtures/sample_vpl.sql`

**Interfaces:**
- Produces: stable `ScriptureSourceAdapter`, `EbibleVplSourceAdapter`, `ParsedVplLine`, `VplSqlVerseMetadata`, `ParsedVerseUnit`, restricted parsers, and `CanonValidator`.
- Consumes: pinned archives from Task 3.

- [ ] **Step 1: Write parser tests for real VPL syntax and filtering**

```dart
test('parses BOM, spaces, and exact source text', () async {
  final lines = Stream.fromIterable(['\uFEFFGEN 1:1 起初，　神创造天地。', '', 'JHN 3:16 神爱世人。']);
  final verses = await VplParser().parse(lines).toList();
  expect(verses.first.bookCode, 'GEN');
  expect(verses.first.text, '起初，　神创造天地。');
  expect(verses.last, const ParsedVplLine(bookCode: 'JHN', chapter: 3, verse: 16, text: '神爱世人。', status: SourceTextStatus.present));
});

test('keeps an explicit empty WEB verse as omitted', () async {
  final verses = await VplParser().parse(Stream.value('LUK 17:36 ')).toList();
  expect(verses.single.status, SourceTextStatus.omitted);
  expect(verses.single.text, '');
});

test('assembles a SQL bridge into one text unit and two addressable slots', () async {
  final result = VerseUnitAssembler().assemble(
    textLines: [fixtureText(book: 'GEN', chapter: 24, verse: 29, text: '利百加有一个哥哥，名叫拉班。')],
    metadata: [fixtureMetadata(book: 'GEN', chapter: 24, startVerse: 29, endVerse: 30)],
  );
  expect(result.units.single.startVerse, 29);
  expect(result.units.single.endVerse, 30);
  expect(result.slots.map((slot) => slot.verse), [29, 30]);
});

test('rejects malformed non-empty lines', () async {
  final lines = Stream.value('GEN one:1 invalid');
  await expectLater(VplParser().parse(lines).toList(), throwsA(isA<VplFormatException>()));
});
```

- [ ] **Step 2: Run the tests and verify failure**

Run: `.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/vpl_parser_test.dart`

Expected: FAIL because the parser is missing.

- [ ] **Step 3: Implement strict line parsing**

First define the source-neutral build contract. Pack building and validation may depend on this result but never on eBible filenames or parser classes:

```dart
abstract interface class ScriptureSourceAdapter {
  String get formatId;
  Future<NormalizedScriptureSource> parse(SourceBundle source);
}

final class NormalizedScriptureSource {
  const NormalizedScriptureSource({required this.translation, required this.units, required this.slots, required this.provenance});
  final NormalizedTranslationMetadata translation;
  final List<ParsedVerseUnit> units;
  final List<ParsedVerseSlot> slots;
  final SourceProvenance provenance;
}
```

`EbibleVplSourceAdapter` is the only class that knows the `_vpl.txt`, `_vpl.sql`, `_about.txt`, and eBible book-code conventions. A future USFM or licensed-source adapter must be able to produce the same normalized result without changing `PackBuilder`, `ScriptureRepository`, recitation, plans, or statistics.

```dart
final class ParsedVplLine {
  const ParsedVplLine({required this.bookCode, required this.chapter, required this.verse, required this.text, required this.status});
  final String bookCode;
  final int chapter;
  final int verse;
  final String text;
  final SourceTextStatus status;
}

final class VplParser {
  static final _line = RegExp(r'^([1-3A-Z][A-Z0-9]{2})\s+(\d+):(\d+)\s?(.*)$');

  Stream<ParsedVplLine> parse(Stream<String> lines) async* {
    var lineNumber = 0;
    await for (final raw in lines) {
      lineNumber += 1;
      final value = raw.replaceFirst('\uFEFF', '');
      if (value.trim().isEmpty) continue;
      final match = _line.firstMatch(value);
      if (match == null) throw VplFormatException(lineNumber, value);
      yield ParsedVplLine(
        bookCode: match.group(1)!,
        chapter: int.parse(match.group(2)!),
        verse: int.parse(match.group(3)!),
        text: match.group(4)!,
        status: match.group(4)!.isEmpty ? SourceTextStatus.omitted : SourceTextStatus.present,
      );
    }
  }
}
```

`VplSqlMetadataParser` must parse only the narrowly documented `INSERT` rows in the companion `_vpl.sql` file and extract book, chapter, start verse, end verse, and source verse ID. It must never execute upstream SQL. Reject DDL, comments containing executable text, unknown column layouts, invalid ranges, duplicate IDs, and trailing unparsed tokens. Map TXT abbreviations such as `SOL/EZE/JOE/MAR/JOH/PHI/JAM/1JO` and SQL abbreviations such as `SNG/EZK/JOL/MRK/JHN/PHP/JAS/1JN` through separate explicit tables to the same OSIS IDs.

Join text and metadata by OSIS book, chapter, and start verse. Every non-empty TXT line must match exactly one SQL record. Expand `endVerse` only into address slots; keep one source text unit. A TXT-only empty line is allowed only as an explicit `omitted` slot.

- [ ] **Step 4: Add exact canon metadata and validator rules**

The JSON must contain these ordered codes and chapter counts:

```json
{"canonId":"protestant66","books":[
  ["GEN",50],["EXO",40],["LEV",27],["NUM",36],["DEU",34],["JOS",24],["JDG",21],["RUT",4],["1SA",31],["2SA",24],["1KI",22],["2KI",25],["1CH",29],["2CH",36],["EZR",10],["NEH",13],["EST",10],["JOB",42],["PSA",150],["PRO",31],["ECC",12],["SNG",8],["ISA",66],["JER",52],["LAM",5],["EZK",48],["DAN",12],["HOS",14],["JOL",3],["AMO",9],["OBA",1],["JON",4],["MIC",7],["NAM",3],["HAB",3],["ZEP",3],["HAG",2],["ZEC",14],["MAL",4],["MAT",28],["MRK",16],["LUK",24],["JHN",21],["ACT",28],["ROM",16],["1CO",16],["2CO",13],["GAL",6],["EPH",6],["PHP",4],["COL",4],["1TH",5],["2TH",3],["1TI",6],["2TI",4],["TIT",3],["PHM",1],["HEB",13],["JAS",5],["1PE",5],["2PE",3],["1JN",5],["2JN",1],["3JN",1],["JUD",1],["REV",22]
]}
```

`CanonValidator` must discard non-canon books only when explicitly called with `filterNonCanon: true`, then verify ordered book set, contiguous chapters, positive ranges, no duplicate slot, no overlapping text units, and at least one slot in every expected chapter. On the pinned archives, assert CUV simplified and traditional each have 66 books, 1189 chapters, 31021 text units, 70 bridge units, and 71 extra bridge slots. After filtering WEB's 15 deuterocanonical books, assert 66 books, 1189 chapters, 31103 slots, 31098 non-empty units/slots, and exactly five omitted slots: Luke 17:36, Acts 8:37, Acts 15:34, Acts 24:7, and Romans 16:25.

- [ ] **Step 5: Run parser and canon tests**

Run:

```powershell
.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/vpl_parser_test.dart tool/scripture_pack/test/vpl_sql_metadata_parser_test.dart tool/scripture_pack/test/verse_unit_assembler_test.dart tool/scripture_pack/test/canon_validator_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```powershell
git add assets/scripture/canon tool/scripture_pack/lib/scripture_source_adapter.dart tool/scripture_pack/lib/ebible_vpl_source_adapter.dart tool/scripture_pack/lib/vpl_parser.dart tool/scripture_pack/lib/vpl_sql_metadata_parser.dart tool/scripture_pack/lib/verse_unit_assembler.dart tool/scripture_pack/lib/book_code_map.dart tool/scripture_pack/lib/canon_validator.dart tool/scripture_pack/test
git commit -m "feat: preserve scripture bridges and omitted verses"
```

## Task 5: Build deterministic SQLite scripture packs

**Files:**
- Create: `tool/scripture_pack/lib/pack_builder.dart`
- Create: `tool/scripture_pack/lib/pack_manifest.dart`
- Create: `tool/scripture_pack/lib/parallel_mapping_builder.dart`
- Create: `tool/scripture_pack/lib/parallel_mapping_validator.dart`
- Create: `tool/scripture_pack/bin/build_all.dart`
- Create: `assets/scripture/versification/parallel_overrides.json`
- Test: `tool/scripture_pack/test/pack_builder_test.dart`
- Test: `tool/scripture_pack/test/parallel_mapping_builder_test.dart`
- Generate: `assets/scripture/cmn-cu89s/`, `assets/scripture/cmn-cu89t/`, `assets/scripture/eng-web/`

**Interfaces:**
- Produces: pack folder containing `manifest.json`, `scripture.sqlite`, and `LICENSE.txt`, plus content-hash-bound many-to-many mappings.
- Consumes: `SourceDescriptor`, `ParsedVerseUnit`, verse slots, canon metadata, and reviewed overrides.

- [ ] **Step 1: Write a deterministic pack test**

```dart
test('builds a queryable pack and records source provenance', () async {
  final output = await Directory.systemTemp.createTemp('scripture-pack-');
  addTearDown(() => output.delete(recursive: true));
  await PackBuilder().build(
    output: output,
    source: fixtureSource,
    units: const [ParsedVerseUnit(bookCode: 'GEN', chapter: 1, startVerse: 1, endVerse: 1, text: 'In the beginning.', status: SourceTextStatus.present)],
    canon: fixtureCanon,
  );
  final database = sqlite3.open('${output.path}/scripture.sqlite');
  addTearDown(database.close);
  expect(database.select('SELECT text FROM verse_unit').single['text'], 'In the beginning.');
  final manifest = jsonDecode(await File('${output.path}/manifest.json').readAsString()) as Map<String, Object?>;
  expect((manifest['source'] as Map<String, Object?>)['archiveSha256'], fixtureSource.sha256);
  expect(manifest['schemaVersion'], 1);
  expect((manifest['translation'] as Map<String, Object?>)['versificationId'], isNotEmpty);
});
```

Add mapping tests for all three relation shapes that cannot be represented by an equal-key join:

```dart
test('resolves bridges, cross-chapter bridges, and relocated doxology in both directions', () async {
  expect(group('cmn-cu89s', ['Gen.24.29'], 'eng-web').targetKeys, ['Gen.24.29', 'Gen.24.30']);
  expect(group('cmn-cu89s', ['Rev.12.18', 'Rev.13.1'], 'eng-web').targetKeys, ['Rev.13.1']);
  expect(group('cmn-cu89s', ['Rom.16.25', 'Rom.16.26', 'Rom.16.27'], 'eng-web').targetKeys, ['Rom.14.24', 'Rom.14.25', 'Rom.14.26']);
  expect(reverseEveryApprovedGroup(), isTrue);
});
```

- [ ] **Step 2: Run and confirm failure**

Run: `.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/pack_builder_test.dart`

Expected: FAIL because `PackBuilder` is missing.

- [ ] **Step 3: Implement the pack schema and atomic builder**

```sql
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE books (
  osis_id TEXT PRIMARY KEY,
  ordinal INTEGER NOT NULL UNIQUE,
  chapter_count INTEGER NOT NULL CHECK (chapter_count > 0)
);
CREATE TABLE verse_unit (
  unit_id INTEGER PRIMARY KEY,
  osis_book_id TEXT NOT NULL REFERENCES books(osis_id),
  chapter INTEGER NOT NULL CHECK (chapter > 0),
  start_verse INTEGER NOT NULL CHECK (start_verse > 0),
  end_verse INTEGER NOT NULL CHECK (end_verse >= start_verse),
  text TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('present', 'omitted')),
  source_order INTEGER NOT NULL UNIQUE,
  UNIQUE (osis_book_id, chapter, start_verse, end_verse)
);
CREATE TABLE verse_slot (
  osis_book_id TEXT NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  unit_id INTEGER NOT NULL REFERENCES verse_unit(unit_id),
  slot_ordinal INTEGER NOT NULL,
  PRIMARY KEY (osis_book_id, chapter, verse)
);
CREATE TABLE parallel_group (
  group_id TEXT PRIMARY KEY,
  target_translation_id TEXT NOT NULL,
  target_semantic_sha256 TEXT NOT NULL,
  relation TEXT NOT NULL,
  provenance TEXT NOT NULL,
  review_state TEXT NOT NULL CHECK (review_state IN ('automatic', 'approved'))
);
CREATE TABLE parallel_source_member (group_id TEXT NOT NULL REFERENCES parallel_group(group_id), osis_book_id TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, ordinal INTEGER NOT NULL, PRIMARY KEY (group_id, ordinal));
CREATE TABLE parallel_target_member (group_id TEXT NOT NULL REFERENCES parallel_group(group_id), osis_book_id TEXT NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, ordinal INTEGER NOT NULL, PRIMARY KEY (group_id, ordinal));
CREATE INDEX verse_unit_chapter_idx ON verse_unit(osis_book_id, chapter, start_verse);
```

Create the database in a temporary sibling directory, insert all rows in one transaction, run `PRAGMA integrity_check`, write canonical JSON with sorted keys, hash `scripture.sqlite`, then rename the complete directory into place. The manifest records `packId`, `canonId`, `versificationId`, archive/text/about hashes, license hash, unit/slot/bridge/omitted counts, semantic content hash, SQLite hash, mapping revision, mapping hash, and every target pack semantic hash. `assets/scripture/index.json`, not the manifest itself, pins each manifest SHA-256. `LICENSE.txt` must identify the source page, archive hash, Public Domain label reported by the source, WEB name/trademark notice, and retrieval date.

Mapping generation order is fixed: CUV simplified/traditional identical ranges; structurally equal ranges outside reviewed exceptions; CUV SQL bridges to WEB slots; then reviewed overrides for the 12 residual chapters. Those chapters are Acts 28, John 5, John 7, Luke 23, Matthew 18, Matthew 23, Mark 7, Mark 15, Romans 14, Romans 16, 3 John 1, and Revelation 12/13 (the Revelation override crosses the chapter boundary). Overrides contain source/target member arrays, relation, evidence, review state, and both packs' semantic SHA-256 values. A content update invalidates the override.

The checked-in review must explicitly encode:

- WEB-only Acts 28:29, John 5:4, John 7:53, Luke 23:17, Matthew 18:11, Matthew 23:14, Mark 7:16, and Mark 15:28 as absent in CUV, not silently dropped.
- CUV 3 John 1:14 + 1:15 to WEB 1:14 as `targetBridge`.
- CUV Revelation 12:18 + 13:1 to WEB 13:1 as `crossChapterTargetBridge`.
- CUV Romans 16:25–27 to WEB Romans 14:24–26 as `relocated`.
- CUV Romans 16:23 + 16:24 to WEB 16:23 as `targetBridge`; WEB Romans 16:24 is a separate unmatched textual unit and WEB 16:25 remains an explicit `omitted` slot.

The validator must prove zero unresolved units, reverse-direction resolution, and an explicit `sourceAbsent`/`targetAbsent` reason for any present unit without a counterpart. The pinned raw TXT comparison has 67 differing chapters; after bridge expansion only the reviewed 12 chapter areas may remain.

- [ ] **Step 4: Run unit tests and build all three real packs**

Run:

```powershell
.\.toolchains\flutter\bin\dart.bat test tool/scripture_pack/test/pack_builder_test.dart
.\.toolchains\flutter\bin\dart.bat run tool/scripture_pack/bin/build_all.dart
Get-ChildItem assets\scripture -Recurse | Select-Object FullName,Length
```

Expected: each translation directory has the three required files; builder prints expected unit/slot/bridge/omitted counts, `0 unresolved mappings`, `0 duplicates`, `0 missing chapters`, and SQLite integrity `ok`.

- [ ] **Step 5: Rebuild and prove determinism**

Run the builder twice and compare:

```powershell
$before = Get-FileHash assets\scripture\*\scripture.sqlite -Algorithm SHA256
.\.toolchains\flutter\bin\dart.bat run tool/scripture_pack/bin/build_all.dart
$after = Get-FileHash assets\scripture\*\scripture.sqlite -Algorithm SHA256
Compare-Object $before.Hash $after.Hash
```

Expected: `Compare-Object` prints nothing.

- [ ] **Step 6: Commit**

```powershell
git add tool/scripture_pack assets/scripture
git commit -m "build: generate verified offline scripture packs"
```

## Task 6: Install, validate, and query scripture packs at runtime

**Files:**
- Create: `lib/src/features/scripture/data/scripture_pack_manifest.dart`
- Create: `lib/src/features/scripture/data/scripture_pack_validator.dart`
- Create: `lib/src/features/scripture/data/scripture_pack_installer.dart`
- Create: `lib/src/features/scripture/data/sqlite_scripture_repository.dart`
- Create: `lib/src/features/scripture/application/scripture_providers.dart`
- Test: `test/scripture/scripture_pack_validator_test.dart`
- Test: `test/scripture/sqlite_scripture_repository_test.dart`

**Interfaces:**
- Produces: `ScripturePackInstaller.ensureInstalled()`, concrete `SqliteScriptureRepository`.
- Consumes: `ScriptureRepository` and generated pack assets.

- [ ] **Step 1: Write failure-first pack integrity and repository tests**

```dart
test('rejects a database whose digest differs from its manifest', () async {
  final fixture = await copyPackFixture();
  await File('${fixture.path}/scripture.sqlite').writeAsString('corrupt');
  await expectLater(ScripturePackValidator().validate(fixture), throwsA(isA<ScripturePackIntegrityException>()));
});

test('reads John 3:16 through a text unit and stable verse slot', () async {
  final repository = SqliteScriptureRepository(packDirectory: fixturePackDirectory);
  final units = await repository.getChapter('eng-web', 'JHN', 3);
  expect(units.singleWhere((unit) => unit.start.verse == 16).start.osisBookId, 'JHN');
});

test('parallel repository returns an approved cross-chapter group', () async {
  final result = await repository.resolveParallelPassage(
    LocatedPassageRange(translationId: 'cmn-cu89s', range: rev1218Through131),
    'eng-web',
  );
  expect(result.groups.single.relation, ParallelRelation.crossChapterTargetBridge);
  expect(result.groups.single.targetUnits.single.start, rev131);
});
```

- [ ] **Step 2: Run and verify missing implementations**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/scripture/scripture_pack_validator_test.dart test/scripture/sqlite_scripture_repository_test.dart`

Expected: FAIL at compile time for missing classes.

- [ ] **Step 3: Implement safe installation and read-only queries**

`ScripturePackInstaller` must copy each asset pack into a versioned directory under application support, validate in a temporary directory, and atomically rename it. Validation rejects mismatched versification/mapping hashes or any mapping whose target semantic hash is stale. `SqliteScriptureRepository` opens databases with `OpenMode.readOnly`, maps units and slots into domain records, resolves parallel groups in both directions, and throws `TranslationNotFound`, `PassageNotFound`, or `ParallelMappingUnavailable` instead of returning guessed/partial data. If a requested slot intersects a bridged `VerseUnit` or `ParallelGroup`, return that complete indivisible unit/group and add a structured range-expansion warning; never cut or duplicate source text merely to match the requested endpoint.

```dart
final class SqliteScriptureRepository implements ScriptureRepository {
  SqliteScriptureRepository({required this.registry});
  final ScripturePackRegistry registry;

  Database _open(String translationId) => sqlite3.open(
        registry.databasePath(translationId),
        mode: OpenMode.readOnly,
      );

  @override
  Future<List<VerseUnit>> getChapter(String translationId, String osisBookId, int chapter) async {
    final database = _open(translationId);
    try {
      final rows = database.select(
        'SELECT start_verse, end_verse, text, status FROM verse_unit WHERE osis_book_id = ? AND chapter = ? ORDER BY source_order',
        [osisBookId, chapter],
      );
      if (rows.isEmpty) throw PassageNotFound('$osisBookId $chapter');
      return rows.map((row) => VerseUnit(
        translationId: translationId,
        start: (canonId: CanonId.protestant66, osisBookId: osisBookId, chapter: chapter, verse: row['start_verse'] as int),
        end: (canonId: CanonId.protestant66, osisBookId: osisBookId, chapter: chapter, verse: row['end_verse'] as int),
        text: row['text'] as String,
        status: SourceTextStatus.values.byName(row['status'] as String),
      )).toList(growable: false);
    } finally {
      database.close();
    }
  }
}
```

- [ ] **Step 4: Run repository and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/scripture
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/scripture/data lib/src/features/scripture/application test/scripture pubspec.yaml
git commit -m "feat: install and query offline scripture packs"
```

## Task 7: Build the multilevel browser and bilingual passage view

**Files:**
- Create: `lib/src/features/scripture/presentation/scripture_browser_screen.dart`
- Create: `lib/src/features/scripture/presentation/book_grid.dart`
- Create: `lib/src/features/scripture/presentation/chapter_grid.dart`
- Create: `lib/src/features/scripture/presentation/passage_screen.dart`
- Create: `lib/src/features/scripture/presentation/translation_selector.dart`
- Create: `lib/src/features/scripture/presentation/scripture_sources_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/src/app/router.dart`
- Modify: `pubspec.yaml` to register pack assets
- Test: `test/scripture/scripture_browser_screen_test.dart`
- Test: `test/scripture/passage_screen_test.dart`
- Test: `test/scripture/scripture_sources_screen_test.dart`

**Interfaces:**
- Produces: routes `/bible`, `/bible/:translation/:book/:chapter`, `/about/scripture-sources`, and bilingual passage selection.
- Consumes: Riverpod repository provider and scripture domain types.

- [ ] **Step 1: Write widget tests for directory depth and location preservation**

```dart
testWidgets('selects translation, testament, book, chapter, and passage', (tester) async {
  await tester.pumpWidget(testApp(repository: FakeScriptureRepository.standard()));
  await tester.tap(find.text('圣经'));
  await tester.tap(find.text('新标点和合本（简体）'));
  await tester.tap(find.text('新约'));
  await tester.tap(find.text('约翰福音'));
  await tester.tap(find.text('第 3 章'));
  await tester.pumpAndSettle();
  expect(find.textContaining('神爱世人'), findsOneWidget);
});

testWidgets('keeps John 3 selected when switching to WEB', (tester) async {
  await tester.pumpWidget(testApp(repository: FakeScriptureRepository.standard(), initialLocation: '/bible/cmn-cu89s/JHN/3'));
  await tester.tap(find.byKey(const Key('translation-selector')));
  await tester.tap(find.text('World English Bible'));
  await tester.pumpAndSettle();
  expect(find.textContaining('For God so loved the world'), findsOneWidget);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/scripture/scripture_browser_screen_test.dart test/scripture/passage_screen_test.dart`

Expected: FAIL because the screens and routes are missing.

- [ ] **Step 3: Implement responsive directory and passage screens**

Use one Riverpod `AsyncNotifier` for selection state:

```dart
final class ScriptureSelection {
  const ScriptureSelection({required this.translationId, this.testament, this.bookId, this.chapter, this.parallelTranslationId});
  final String translationId;
  final String? testament;
  final String? bookId;
  final int? chapter;
  final String? parallelTranslationId;
}
```

On widths below 720, each level pushes a route; on desktop, show book/chapter navigation in a left pane and passage text in the main pane. Single-translation mode renders each `VerseUnit` once and labels bridged ranges such as `29–30`; omitted slots show an accessible “本译本省略此节” marker. Bilingual mode renders repository-provided `ParallelGroup` rows, including one-to-many, many-to-one, cross-chapter, relocated, and absent relationships. It must never reconstruct correspondence from list index or equal `VerseKey`. Add semantics labels containing both translations, source/target references, and mapping status.

`ScriptureSourcesScreen` reads installed pack manifests and bundled `LICENSE.txt` files and displays translation name, source organization/page as copyable text, archive and semantic hashes, retrieval date, Public Domain/trademark notices, and the complete offline license text. It never fetches or opens a URL at runtime. Every new label, status, warning, and action in this task is added with matching placeholders/metadata to all three ARB files; `flutter gen-l10n` plus a locale-coverage test fails on missing or untranslated keys.

- [ ] **Step 4: Run widget, golden, and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/scripture
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS and no overflow exceptions at 390x844 and 1200x800 test sizes. Widget fixtures explicitly cover Genesis 24:29–30 bridge, 3 John 1:14–15 target bridge, Revelation 12:18/13:1 cross-chapter group, Romans 16/14 relocation, and a WEB omitted slot.

- [ ] **Step 5: Smoke-build locally available targets**

Run on Windows:

```powershell
.\.toolchains\flutter\bin\flutter.bat build windows --debug
.\.toolchains\flutter\bin\flutter.bat build apk --debug
```

Expected: both build commands exit 0. iOS and macOS builds are deferred to the release plan's macOS CI because this host is Windows.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/scripture/presentation lib/l10n lib/src/app/router.dart pubspec.yaml test/scripture
git commit -m "feat: add offline scripture browser and bilingual view"
```

## Phase Acceptance

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat pub get
.\.toolchains\flutter\bin\flutter.bat gen-l10n
.\.toolchains\flutter\bin\flutter.bat analyze
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\dart.bat run tool/scripture_pack/bin/build_all.dart
git status --short
```

Expected: analyzer clean, all tests pass, the three packs rebuild deterministically, and `git status --short` is empty. Pack validation reports the pinned unit/slot/bridge/omitted counts, the raw 67-chapter structural delta, only the reviewed 12 residual chapter areas after bridge expansion, zero unresolved mappings, and valid reverse resolution. The app can browse all 66 books offline and preserve the intended mapped passage while switching among CUV simplified, CUV traditional, and WEB.
