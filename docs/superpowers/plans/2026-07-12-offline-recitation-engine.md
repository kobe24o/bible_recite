# Offline Recitation Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add completely offline Mandarin and English recording, transcription, tolerant verse alignment, explainable results, verse-by-verse practice, and continuous passage practice to the scripture browser produced by the foundation plan.

**Architecture:** Pure Dart normalization, alignment, and evaluation code is isolated from device audio and sherpa-onnx. `record` streams PCM into a stateful decoder/resampler; one long-lived worker isolate owns sherpa VAD, SenseVoice, and every FFI object's lifetime. Complete speech segments go to the non-streaming recognizer. A Riverpod session controller owns the state machine and can be tested with fake audio and speech-pipeline ports.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, record 7.1.1, sherpa_onnx 1.13.4, pinyin 3.3.0, SenseVoice INT8 (2024-07-17), Silero VAD, Riverpod 3.3.2, cryptography 2.9.0, flutter_test.

## Global Constraints

- Complete the foundation plan first; all selected target passages come from `ScriptureRepository`.
- Recognition is local only. No runtime download, cloud fallback, remote logging, or remote model call is allowed.
- Bundle the model and VAD with every installer; copy and validate them into application support before initialization.
- Record mono PCM16, observe the device's effective format, and resample to 16 kHz before VAD/ASR.
- Languages are Mandarin (`zh`) and English (`en`) only in product UI.
- Preserve source text for display. Normalization creates a comparison copy only.
- Self-correction, harmless fillers, and repetition do not cause content failure; unresolved deletion, substitution, or order errors do.
- SenseVoice exposes text/tokens/timestamps/language/event metadata but no dependable confidence score. Never claim uncertainty is model confidence.
- Ambiguous audio must become `pendingClarification`, never automatic pass or fail.
- Do not load the approximately 228 MB ONNX model with `rootBundle.load`; Android must stream-copy packaged assets to a real private file path after a 260 MB free-space preflight.
- Raw audio is deleted after evaluation unless the user explicitly enables local failure playback.
- Every task uses TDD and ends with a commit.

---

## File Structure

```text
tool/models/model_catalog.json                        # exact URLs, sizes, hashes, licenses
tool/models/bin/prepare_models.dart                  # verified model acquisition/extraction
tool/models/lib/model_fetcher.dart                   # injected downloader and atomic installer
assets/models/runtime/                               # generated build assets; binaries ignored
assets/models/manifests/                             # committed model/license metadata
lib/src/features/recitation/domain/recitation_models.dart
lib/src/features/recitation/domain/audio_capture.dart
lib/src/features/recitation/domain/speech_recognizer.dart
lib/src/features/recitation/domain/voice_activity_segmenter.dart
lib/src/features/recitation/domain/speech_pipeline.dart
lib/src/features/recitation/domain/text_normalizer.dart
lib/src/features/recitation/domain/sequence_aligner.dart
lib/src/features/recitation/domain/recitation_evaluator.dart
lib/src/features/recitation/data/record_audio_capture.dart
lib/src/features/recitation/data/linear_pcm_resampler.dart
lib/src/features/recitation/data/sherpa_voice_activity_segmenter.dart
lib/src/features/recitation/data/sherpa_sense_voice_recognizer.dart
lib/src/features/recitation/data/isolate_speech_pipeline.dart
lib/src/features/recitation/data/model_bundle_installer.dart
lib/src/features/recitation/application/recitation_session_controller.dart
lib/src/features/recitation/presentation/recitation_screen.dart
lib/src/features/recitation/presentation/recitation_result_screen.dart
assets/recitation/fillers.json                         # reviewed Mandarin/English filler list
assets/recitation/orthography_zh.json                  # reviewed one-to-one script equivalences
assets/recitation/pronunciation_overrides.json         # Bible-name reading overrides
test/recitation/**                                     # pure, adapter, controller, widget tests
integration_test/offline_recitation_test.dart          # end-to-end with fake/fixture PCM
```

## Task 1: Define recitation ports, value types, and the session state machine

**Files:**
- Create: `lib/src/features/recitation/domain/recitation_models.dart`
- Create: `lib/src/features/recitation/domain/audio_capture.dart`
- Create: `lib/src/features/recitation/domain/session_audio_store.dart`
- Create: `lib/src/features/recitation/domain/speech_recognizer.dart`
- Create: `lib/src/features/recitation/domain/voice_activity_segmenter.dart`
- Create: `lib/src/features/recitation/domain/speech_pipeline.dart`
- Test: `test/recitation/recitation_models_test.dart`

**Interfaces:**
- Produces: all stable types consumed by Tasks 2–9.
- Consumes: `SelectedPassage`, `PassageSelection`, and `VerseKey` from the foundation plan.

- [ ] **Step 1: Write state-transition tests**

```dart
test('recording can pause, resume, and finish exactly once', () {
  expect(RecitationPhase.idle.canTransitionTo(RecitationPhase.recording), isTrue);
  expect(RecitationPhase.recording.canTransitionTo(RecitationPhase.paused), isTrue);
  expect(RecitationPhase.paused.canTransitionTo(RecitationPhase.recording), isTrue);
  expect(RecitationPhase.evaluating.canTransitionTo(RecitationPhase.completed), isTrue);
  expect(RecitationPhase.completed.canTransitionTo(RecitationPhase.recording), isFalse);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_models_test.dart`

Expected: FAIL because `RecitationPhase` is undefined.

- [ ] **Step 3: Implement exact domain ports**

```dart
enum RecitationLanguage { mandarin, english }
enum RecitationMode { verseByVerse, continuous }
enum RecitationPhase { idle, preparing, recording, paused, evaluating, pendingClarification, completed, failed }

extension RecitationTransitions on RecitationPhase {
  bool canTransitionTo(RecitationPhase next) => switch (this) {
    RecitationPhase.idle => next == RecitationPhase.preparing || next == RecitationPhase.recording,
    RecitationPhase.preparing => next == RecitationPhase.recording || next == RecitationPhase.failed,
    RecitationPhase.recording => next == RecitationPhase.paused || next == RecitationPhase.evaluating || next == RecitationPhase.failed,
    RecitationPhase.paused => next == RecitationPhase.recording || next == RecitationPhase.evaluating,
    RecitationPhase.evaluating => next == RecitationPhase.pendingClarification || next == RecitationPhase.completed || next == RecitationPhase.failed,
    RecitationPhase.pendingClarification => next == RecitationPhase.recording || next == RecitationPhase.failed,
    RecitationPhase.completed || RecitationPhase.failed => false,
  };
}

final class PcmChunk {
  const PcmChunk({required this.samples, required this.sampleRate, required this.capturedAt});
  final Float32List samples;
  final int sampleRate;
  final Duration capturedAt;
}

final class SpeechSegment {
  const SpeechSegment({required this.sequence, required this.samples, required this.sampleRate, required this.startedAt, required this.endedAt, required this.quality});
  final int sequence;
  final Float32List samples;
  final int sampleRate;
  final Duration startedAt;
  final Duration endedAt;
  final SpeechQuality quality;
}

final class SpeechQuality {
  const SpeechQuality({required this.speechDuration, required this.rmsDbfs, required this.clippingFraction, this.estimatedSnrDb});
  final Duration speechDuration;
  final double rmsDbfs;
  final double clippingFraction;
  final double? estimatedSnrDb;
}

final class RecognitionSegment {
  const RecognitionSegment({required this.sequence, required this.text, required this.tokens, required this.tokenStarts, required this.tokenEnds, required this.languageTag, required this.startedAt, required this.endedAt, required this.quality, required this.emotion, required this.event});
  final int sequence;
  final String text;
  final List<String> tokens;
  final List<Duration> tokenStarts;
  final List<Duration> tokenEnds;
  final String languageTag;
  final Duration startedAt;
  final Duration endedAt;
  final SpeechQuality quality;
  final String emotion;
  final String event;
}

final class RecitationRequest {
  const RecitationRequest({required this.translation, required this.passage, required this.mode, required this.language});
  final TranslationInfo translation;
  final SelectedPassage passage;
  final RecitationMode mode;
  final RecitationLanguage language;
}

enum HintKind { firstCharacter, nextToken, fullReveal }

final class HintEvent {
  const HintEvent({required this.kind, required this.at, this.verseKey});
  final HintKind kind;
  final Duration at;
  final VerseKey? verseKey;
}

final class RetainedRecordingDraft {
  const RetainedRecordingDraft({required this.sessionId, required this.sha256, required this.sizeBytes, required this.mimeType});
  final String sessionId;
  final String sha256;
  final int sizeBytes;
  final String mimeType;
}

abstract interface class SessionAudioStore {
  Future<void> start(String sessionId);
  Future<void> append(String sessionId, PcmChunk chunk);
  Future<RetainedRecordingDraft> sealFailed(String sessionId);
  Future<void> discard(String sessionId);
}

```

`RecognitionSegment` intentionally has no confidence field: sherpa-onnx 1.13.4 does not return one for `OfflineRecognizerResult`. An adapter must not synthesize a probability. Validate equal token/start/end list lengths and monotonic bounds within the segment; these timings, the per-segment detected `languageTag`, and `SpeechQuality` are the evidence used by the evaluator.

```dart
abstract interface class AudioCapture {
  Future<Stream<PcmChunk>> start();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<bool> hasPermission();
}

abstract interface class VoiceActivitySegmenter {
  List<SpeechSegment> add(PcmChunk chunk);
  List<SpeechSegment> flush();
  void reset();
}

abstract interface class SpeechRecognizer {
  Future<void> initialize();
  Future<RecognitionSegment> transcribe(SpeechSegment segment, RecitationLanguage language);
  Future<void> dispose();
}

enum PipelineWriteResult { accepted, backpressure, closed }

abstract interface class SpeechPipeline {
  Stream<RecognitionSegment> get results;
  Future<void> initialize(RecitationLanguage language);
  Future<PipelineWriteResult> add(PcmChunk chunk);
  Future<void> flush();
  Future<void> reset();
  Future<void> dispose();
}
```

`VoiceActivitySegmenter` and `SpeechRecognizer` are worker-internal test seams. Application/session code depends only on `SpeechPipeline`, which owns ordering, backpressure, flushing, and the long-lived isolate boundary.

- [ ] **Step 4: Run tests and analyzer**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_models_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/recitation/domain test/recitation/recitation_models_test.dart
git commit -m "feat: define offline recitation ports"
```

## Task 2: Normalize Mandarin and English without changing display text

**Files:**
- Create: `lib/src/features/recitation/domain/text_normalizer.dart`
- Create: `lib/src/features/recitation/domain/mandarin_normalizer.dart`
- Create: `lib/src/features/recitation/domain/english_normalizer.dart`
- Create: `assets/recitation/orthography_zh.json`
- Test: `test/recitation/text_normalizer_test.dart`

**Interfaces:**
- Produces: `NormalizedText` and `NormalizedToken` with source offsets.
- Consumes: a reviewed `orthography_zh.json` for permitted simplified/traditional display differences; `pinyin` is reserved for Task 4 pronunciation ambiguity and display text is untouched.

- [ ] **Step 1: Write exact normalization tests**

```dart
test('Mandarin ignores punctuation, spaces, and simplified/traditional display differences', () {
  final simplified = MandarinNormalizer().normalize('神爱世人。');
  final traditional = MandarinNormalizer().normalize('　神愛世人！');
  expect(simplified.values, ['神', '爱', '世', '人']);
  expect(traditional.values, simplified.values);
  expect(traditional.original, '　神愛世人！');
});

test('English expands harmless contractions and lowercases', () {
  final value = EnglishNormalizer().normalize("Don't be anxious; it's God's word.");
  expect(value.values, ['do', 'not', 'be', 'anxious', 'it', 'is', "god's", 'word']);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/text_normalizer_test.dart`

Expected: FAIL because normalizers are missing.

- [ ] **Step 3: Implement token-preserving normalizers**

```dart
final class NormalizedToken {
  const NormalizedToken({required this.value, required this.sourceStart, required this.sourceEnd});
  final String value;
  final int sourceStart;
  final int sourceEnd;
}

final class NormalizedText {
  const NormalizedText({required this.original, required this.tokens});
  final String original;
  final List<NormalizedToken> tokens;
  List<String> get values => tokens.map((token) => token.value).toList(growable: false);
}
```

Mandarin removes only reviewed punctuation/whitespace, applies only one-to-one comparison mappings explicitly listed in `orthography_zh.json`, and keeps one token per Han character. It must not run an unrestricted script-conversion library because context-sensitive conversions can change proper names. English converts curly apostrophes, expands this fixed unambiguous contraction map, removes punctuation, then splits on whitespace:

```dart
const contractions = <String, List<String>>{
  "can't": ['cannot'], "won't": ['will', 'not'], "don't": ['do', 'not'],
  "doesn't": ['does', 'not'], "didn't": ['did', 'not'], "isn't": ['is', 'not'],
  "aren't": ['are', 'not'], "it's": ['it', 'is'], "i'm": ['i', 'am'],
  "you're": ['you', 'are'], "we're": ['we', 'are'], "they're": ['they', 'are'],
};
```

- [ ] **Step 4: Run focused and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation/text_normalizer_test.dart
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/src/features/recitation/domain test/recitation/text_normalizer_test.dart
git commit -m "feat: normalize Mandarin and English recitations"
```

## Task 3: Implement deterministic sequence alignment

**Files:**
- Create: `lib/src/features/recitation/domain/sequence_aligner.dart`
- Test: `test/recitation/sequence_aligner_test.dart`

**Interfaces:**
- Produces: `SequenceAligner.align(expected, actual) -> AlignmentResult`.
- Consumes: normalized token values.

- [ ] **Step 1: Write tests for every edit operation and tie breaking**

```dart
test('classifies deletion, insertion, substitution, and adjacent transposition', () {
  expect(kinds(['a', 'b'], ['a']), [EditKind.match, EditKind.deletion]);
  expect(kinds(['a'], ['a', 'x']), [EditKind.match, EditKind.insertion]);
  expect(kinds(['a'], ['b']), [EditKind.substitution]);
  expect(kinds(['a', 'b'], ['b', 'a']), [EditKind.transposition]);
});

test('prefers matches then fewer content errors when costs tie', () {
  final result = SequenceAligner().align(['各', '人', '看', '别', '人'], ['各', '人', '看', '人']);
  expect(result.operations.where((op) => op.kind == EditKind.deletion).single.expected, '别');
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/sequence_aligner_test.dart`

Expected: FAIL for missing aligner.

- [ ] **Step 3: Implement Damerau-Levenshtein cost and backtrace**

```dart
enum EditKind { match, insertion, deletion, substitution, transposition }

final class AlignmentOp {
  const AlignmentOp({required this.kind, this.expected, this.actual, required this.expectedIndex, required this.actualIndex});
  final EditKind kind;
  final String? expected;
  final String? actual;
  final int expectedIndex;
  final int actualIndex;
}

// Recurrence used by SequenceAligner:
// match/substitute: d[i-1][j-1] + (expected[i-1] == actual[j-1] ? 0 : 1)
// delete:           d[i-1][j] + 1
// insert:           d[i][j-1] + 1
// transpose:        d[i-2][j-2] + 1 when adjacent tokens are reversed
// Tie order: match, substitution, deletion, insertion, transposition.
```

Store the two best distinct paths, their integer costs, and their predecessors in each matrix cell. `AlignmentResult` exposes `best`, `alternative`, and `costGap`; backtrace both to index zero and reverse operations. Do not use a heuristic diff library because later self-correction and ambiguity rules require stable indices. A cost gap below `2` is not automatically an error, but it becomes clarification evidence when the two paths would change the pass/fail conclusion.

- [ ] **Step 4: Run property and focused tests**

Add property loops asserting `align(x, x).cost == 0`, `cost >= abs(length difference)`, and backtrace reconstructs both sequences. Then run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation/sequence_aligner_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/recitation/domain/sequence_aligner.dart test/recitation/sequence_aligner_test.dart
git commit -m "feat: align expected and spoken scripture tokens"
```

## Task 4: Add tolerant, explainable recitation evaluation

**Files:**
- Create: `assets/recitation/fillers.json`
- Create: `assets/recitation/pronunciation_overrides.json`
- Create: `lib/src/features/recitation/domain/pronunciation_guard.dart`
- Create: `lib/src/features/recitation/domain/recitation_evaluator.dart`
- Test: `test/recitation/recitation_evaluator_test.dart`

**Interfaces:**
- Produces: `RecitationEvaluator.evaluate(EvaluationRequest) -> EvaluationResult`.
- Consumes: normalizers and `SequenceAligner`.

- [ ] **Step 1: Write acceptance-level evaluator tests**

```dart
test('self-correction passes content but lowers mastery', () {
  final result = evaluator.evaluate(request(expected: '各人看别人比自己强', spoken: '各人看自己 各人看别人比自己强'));
  expect(result.status, RecitationStatus.passedNeedsReview);
  expect(result.issues.single.kind, EvaluationIssueKind.selfCorrection);
  expect(result.masteryScore, lessThan(100));
});

test('unresolved omission cannot pass', () {
  final result = evaluator.evaluate(request(expected: '各人不要单顾自己的事', spoken: '各人单顾自己的事'));
  expect(result.status, RecitationStatus.needsPractice);
  expect(result.issues.any((issue) => issue.kind == EvaluationIssueKind.omission), isTrue);
});

test('phonetic ambiguity requests clarification instead of pass or fail', () {
  final result = evaluator.evaluate(request(expected: '以巴弗提', spoken: '以巴弗题'));
  expect(result.status, RecitationStatus.pendingClarification);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_evaluator_test.dart`

Expected: FAIL because evaluator types are missing.

- [ ] **Step 3: Implement exact classification and mastery rules**

```dart
enum RecitationStatus { accuratePass, passedNeedsReview, needsPractice, pendingClarification }
enum EvaluationIssueKind { omission, substitution, insertion, order, repetition, selfCorrection, filler, clarification }

final class EvaluationRequest {
  const EvaluationRequest({required this.expectedText, required this.segments, required this.language, required this.hints, required this.elapsed, required this.targetDuration});
  final String expectedText;
  final List<RecognitionSegment> segments;
  final RecitationLanguage language;
  final List<HintEvent> hints;
  final Duration elapsed;
  final Duration targetDuration;
}
```

Apply rules in this order: validate and time-order segments; join their text while retaining a timed-token-to-segment map; normalize; mark reviewed fillers; detect a wrong span followed within 12 lexical tokens and 4 seconds by a complete correct replacement span; align the remaining sequence; inspect all segment quality/language evidence and the aligner's best plus second-best paths; classify unresolved edits; compute mastery from typed hint events. `pendingClarification` is mandatory when speech is detected but ASR text is empty, any material segment's detected language conflicts with the selected language, speech is shorter than 250 ms, RMS is below -45 dBFS, clipping exceeds 1%, measurable SNR is below 10 dB, a substitution is only a same-pinyin candidate, or the best/second-best path cost gap is below 2 and changes the outcome. Pure silence produces “没有检测到语音” and no saved failure attempt.

Score starts at 100. Subtract 5 for each `HintKind.firstCharacter`, 8 for each `HintKind.nextToken`, 4 per self-correction (maximum 20), 1 per repeated lexical token (maximum 10), and up to 15 for elapsed time beyond 1.5 times the target. A `HintKind.fullReveal` ends the current no-hint attempt without a passing result. Any unresolved content error caps score at 59. `accuratePass` requires content pass, an empty hint-event list, zero self-corrections, and mastery at least 90; other content passes become `passedNeedsReview`.

- [ ] **Step 4: Add golden cases and run full pure-Dart tests**

Add at least 20 table cases covering Mandarin fillers, English fillers, repetitions, corrections, punctuation, contractions, names, omissions, substitutions, and verse-order changes. Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```powershell
git add assets/recitation lib/src/features/recitation/domain test/recitation
git commit -m "feat: evaluate recitation with explainable tolerance"
```

## Task 5: Pin, fetch, and bundle SenseVoice and Silero VAD

**Files:**
- Create: `tool/models/model_catalog.json`
- Create: `tool/models/lib/model_fetcher.dart`
- Create: `tool/models/bin/prepare_models.dart`
- Create: `assets/models/manifests/sensevoice.json`
- Modify: `.gitignore`
- Modify: `pubspec.yaml`
- Test: `tool/models/test/model_fetcher_test.dart`

**Interfaces:**
- Produces: verified runtime files `model.int8.onnx`, `tokens.txt`, `silero_vad.onnx`, and license notices.
- Consumes: GitHub release assets only at build time.

- [ ] **Step 1: Add the exact model catalog**

```json
{
  "senseVoice": {
    "url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
    "bytes": 163002883,
    "sha256": "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"
  },
  "sileroVad": {
    "url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
    "bytes": 643854,
    "sha256": "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"
  }
}
```

- [ ] **Step 2: Write a failing test for hash and exact extracted files**

```dart
test('rejects an archive before extraction when hash differs', () async {
  final fetcher = ModelFetcher(download: (_) async => Uint8List.fromList([1, 2, 3]));
  await expectLater(fetcher.prepare(fixtureCatalog, temporaryDirectory), throwsA(isA<ModelIntegrityException>()));
  expect(File('${temporaryDirectory.path}/model.int8.onnx').existsSync(), isFalse);
});
```

- [ ] **Step 3: Implement atomic download, SHA-256, and extraction**

Reuse the Task 3 source-fetch pattern, but verify both `bytes` and SHA-256. Run `tar -xjf` into a temporary directory, copy only `model.int8.onnx`, `tokens.txt`, the model license, and `silero_vad.onnx`, then atomically rename to `assets/models/runtime/sensevoice`. Add:

```gitignore
assets/models/runtime/*
!assets/models/runtime/.gitkeep
tool/models/.cache/
```

Register `assets/models/runtime/` in `pubspec.yaml`. The runtime provisioner must preflight at least 260 MB of writable space, stream-copy each packaged asset to a versioned temporary directory, verify its final-file SHA-256, and atomically rename the directory. Apple and Windows may use a verified bundle/install path directly when it is a real filesystem path. Android must use `AssetManager.open()` through a small platform adapter; never call `rootBundle.load()` for the model.

- [ ] **Step 4: Run tests and prepare real model assets**

Run:

```powershell
.\.toolchains\flutter\bin\dart.bat test tool/models/test/model_fetcher_test.dart
.\.toolchains\flutter\bin\dart.bat run tool/models/bin/prepare_models.dart
Get-FileHash assets\models\runtime\sensevoice\model.int8.onnx -Algorithm SHA256
Get-FileHash assets\models\runtime\sensevoice\silero_vad.onnx -Algorithm SHA256
```

Expected: tests PASS; the extracted model exists and VAD hash equals the catalog. Record the extracted model hash in `assets/models/manifests/sensevoice.json` during preparation.

- [ ] **Step 5: Commit metadata and tooling, not model binaries**

```powershell
git add .gitignore pubspec.yaml pubspec.lock tool/models assets/models/manifests assets/models/runtime/.gitkeep
git commit -m "build: pin offline speech models"
```

## Task 6: Implement PCM capture, resampling, VAD, and SenseVoice adapters

**Files:**
- Create: `lib/src/features/recitation/data/record_audio_capture.dart`
- Create: `lib/src/features/recitation/data/linear_pcm_resampler.dart`
- Create: `lib/src/features/recitation/data/sherpa_voice_activity_segmenter.dart`
- Create: `lib/src/features/recitation/data/sherpa_sense_voice_recognizer.dart`
- Create: `lib/src/features/recitation/data/isolate_speech_pipeline.dart`
- Create: `lib/src/features/recitation/data/model_bundle_installer.dart`
- Create: `lib/src/features/recitation/data/model_asset_locator.dart`
- Create: `android/app/src/main/kotlin/app/biblerecite/ModelAssetPlugin.kt`
- Modify: `android/app/src/main/kotlin/app/biblerecite/MainActivity.kt`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `macos/Runner/MainFlutterWindow.swift`
- Modify: `windows/runner/flutter_window.cpp`
- Test: `test/recitation/linear_pcm_resampler_test.dart`
- Test: `test/recitation/sherpa_adapter_contract_test.dart`
- Test: `test/recitation/model_bundle_installer_test.dart`

**Interfaces:**
- Produces concrete implementations of Task 1 ports; application code receives `IsolateSpeechPipeline` only.
- Consumes verified model bundle from Task 5.

- [ ] **Step 1: Write resampling and lifecycle contract tests**

```dart
test('resamples one second of 48 kHz PCM to exactly 16 kHz', () {
  final input = Float32List.fromList(List.generate(48000, (i) => sin(2 * pi * 440 * i / 48000)));
  final output = LinearPcmResampler().resample(input, fromRate: 48000, toRate: 16000);
  expect(output.length, 16000);
  expect(output.every((sample) => sample >= -1 && sample <= 1), isTrue);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/linear_pcm_resampler_test.dart test/recitation/sherpa_adapter_contract_test.dart`

Expected: FAIL for missing adapters.

- [ ] **Step 3: Implement effective-format capture and 16 kHz conversion**

Use:

```dart
const RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  autoGain: false,
  echoCancel: false,
  noiseSuppress: false,
  streamBufferSize: 1024,
);
```

Subscribe to `setOnConfigChanged` and decode using the effective sample rate and channel count returned by the platform; do not assume the request was honored. Preserve a single odd trailing PCM byte across chunks, convert signed little-endian PCM16 to `[-1, 1]`, downmix multiple channels, keep resampler phase between chunks, and emit 16 kHz mono `PcmChunk` objects. Tests must cover `511+1` and exact `512` sample boundaries, odd bytes, int16 extrema, stereo, 44.1/48 kHz, silence, and clipping.

`ModelAssetPlugin.kt` is the Android implementation of `ModelAssetLocator.openBundledAsset(String)`: it accepts only catalog-listed relative paths, rejects separators/traversal not in the catalog, opens them with `applicationContext.assets.open(path, AssetManager.ACCESS_STREAMING)`, and stream-copies into the installer's same-volume temporary directory without materializing the model in a platform channel message or Dart heap. The Dart installer verifies free space, expected size and SHA-256 before atomic directory publication. Contract tests use a fake locator plus Android instrumentation for a real packaged asset, missing asset, short read, disk-full, cancellation, and hash mismatch.

- [ ] **Step 4: Initialize sherpa VAD and SenseVoice with exact configs**

```dart
final senseVoice = OfflineSenseVoiceModelConfig(
  model: paths.model,
  language: language == RecitationLanguage.mandarin ? 'zh' : 'en',
  useInverseTextNormalization: false,
);
final model = OfflineModelConfig(
  senseVoice: senseVoice,
  tokens: paths.tokens,
  debug: false,
  numThreads: 2,
);
final recognizer = OfflineRecognizer(OfflineRecognizerConfig(model: model));
final stream = recognizer.createStream();
stream.acceptWaveform(samples: segment.samples, sampleRate: 16000);
recognizer.decode(stream);
final result = recognizer.getResult(stream);
stream.free();
```

Configure Silero VAD at 16 kHz with 512-sample windows, threshold `0.5`, minimum speech `0.20 s`, minimum silence `0.35 s`, maximum speech `10 s`, and a `30 s` rolling buffer. Pad and flush the final partial window, drain completed VAD segments promptly, and preserve segment sequence numbers. Create VAD, recognizer, and streams only in one long-lived worker isolate. Free every stream on success and exception paths, then free recognizer and VAD exactly once when the worker shuts down.

- [ ] **Step 5: Run adapter tests and a local fixture transcription**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation/linear_pcm_resampler_test.dart test/recitation/sherpa_adapter_contract_test.dart
.\.toolchains\flutter\bin\flutter.bat test --tags model test/recitation/sensevoice_fixture_test.dart
```

Expected: contract tests PASS; model-tagged test transcribes a committed short, licensed fixture and returns non-empty Mandarin/English text.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/src/features/recitation/data android/app/src/main/kotlin ios/Runner macos/Runner windows/runner test/recitation
git commit -m "feat: capture and transcribe speech fully offline"
```

## Task 7: Orchestrate verse and continuous sessions

**Files:**
- Create: `lib/src/features/recitation/application/recitation_session_controller.dart`
- Create: `lib/src/features/recitation/application/recitation_providers.dart`
- Test: `test/recitation/recitation_session_controller_test.dart`

**Interfaces:**
- Produces: `RecitationSessionController.start/pause/resume/finish/repeatClarification`.
- Consumes: `AudioCapture`, `SessionAudioStore`, combined `SpeechPipeline`, `RecitationEvaluator`, and a `RecitationRequest` containing selected `TranslationInfo` plus `SelectedPassage`.

- [ ] **Step 1: Write fake-port state tests**

```dart
test('flushes final speech, evaluates, and deletes temporary audio', () async {
  final controller = controllerWithFakes(spokenText: '神爱世人');
  await controller.start(RecitationRequest(translation: fixtureTranslation, passage: fixturePassage, mode: RecitationMode.continuous, language: RecitationLanguage.mandarin));
  await controller.finish();
  expect(controller.state.phase, RecitationPhase.completed);
  expect(controller.state.result, isNotNull);
  expect(fakeAudioStore.deletedSessionIds, contains(controller.state.sessionId));
});

test('clarification returns to recording only for the ambiguous span', () async {
  final controller = controllerWithPendingClarification();
  await controller.finish();
  expect(controller.state.phase, RecitationPhase.pendingClarification);
  await controller.repeatClarification();
  expect(controller.state.phase, RecitationPhase.recording);
});

test('retains only an opted-in failed recording draft', () async {
  final controller = controllerWithFakes(
    result: needsPracticeResult,
    keepFailedRecordings: true,
  );
  await controller.start(fixtureRequest);
  await controller.finish();
  expect(controller.state.result!.failedRecording, isNotNull);
  expect(fakeAudioStore.sealedSessionIds, contains(controller.state.sessionId));
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_session_controller_test.dart`

Expected: FAIL because controller is missing.

- [ ] **Step 3: Implement serialized commands and interruption handling**

The controller must reject illegal transitions, serialize finish/pause calls, stop capture before flushing the speech pipeline, concatenate recognition segments by sequence/time, evaluate only after all transcriptions finish, and expose a user-visible failure for permission/model/audio errors. It tees captured chunks to `SessionAudioStore` only in the app-private temporary area. By default it discards them after evaluation. Only when the user previously enabled “保存失败录音用于自己复听” and the result is `needsPractice` does it call `sealFailed` and attach the returned draft; pure silence, passes, cancellations, and infrastructure failures are always discarded. A completed state exposes `CompletedRecitation`, retaining translation ID, pack ID, versification ID, semantic SHA-256, the exact `PassageSelection`, and any opted-in recording draft so the persistence plan cannot bind results to changed wording or arbitrary paths. On app lifecycle pause, call `pause()` and set `wasInterrupted`; never submit automatically.

```dart
final class CompletedRecitation {
  const CompletedRecitation({required this.request, required this.result, this.failedRecording});
  final RecitationRequest request;
  final EvaluationResult result;
  final RetainedRecordingDraft? failedRecording;
}

final class RecitationSessionState {
  const RecitationSessionState({required this.sessionId, required this.phase, required this.mode, required this.elapsed, this.partialText = '', this.result, this.failure});
  final String sessionId;
  final RecitationPhase phase;
  final RecitationMode mode;
  final Duration elapsed;
  final String partialText;
  final CompletedRecitation? result;
  final RecitationFailure? failure;
}
```

- [ ] **Step 4: Run controller and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_session_controller_test.dart
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/recitation/application test/recitation/recitation_session_controller_test.dart
git commit -m "feat: orchestrate offline recitation sessions"
```

## Task 8: Build practice and explainable result screens

**Files:**
- Create: `lib/src/features/recitation/presentation/recitation_screen.dart`
- Create: `lib/src/features/recitation/presentation/recitation_result_screen.dart`
- Create: `lib/src/features/recitation/presentation/evaluation_text_span.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/src/features/scripture/presentation/passage_screen.dart`
- Modify: `lib/src/app/router.dart`
- Test: `test/recitation/recitation_screen_test.dart`
- Test: `test/recitation/recitation_result_screen_test.dart`

**Interfaces:**
- Produces: `/recite` and `/recite/result` flows.
- Consumes: session controller and `EvaluationResult`.

- [ ] **Step 1: Write widget tests for hidden text, hints, modes, and accessible feedback**

```dart
testWidgets('hides scripture while recording and records a requested hint', (tester) async {
  await tester.pumpWidget(recitationTestApp());
  expect(find.text(fixtureVerseText), findsNothing);
  await tester.tap(find.text('提示下一词'));
  await tester.pump();
  expect(fakeController.hintsUsed, 1);
});

testWidgets('result uses text and icons, not color alone', (tester) async {
  await tester.pumpWidget(resultTestApp(resultWithOmission));
  expect(find.text('遗漏'), findsOneWidget);
  expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
  expect(find.bySemanticsLabel(contains('遗漏')), findsWidgets);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/recitation/recitation_screen_test.dart test/recitation/recitation_result_screen_test.dart`

Expected: FAIL because screens are missing.

- [ ] **Step 3: Implement the approved interaction**

The recording screen shows reference, offline state, mode switch, elapsed time, waveform, pause, first-character hint, next-word hint, and finish. Hide scripture by default. A full reveal ends the no-hint attempt. The result screen shows content status and mastery separately; renders correct, self-corrected, omitted, substituted, order, and clarification spans with icon + label + color; offers “只重练错误句”, “完整重背”, and “下一段”. Add every new screen label, evaluator issue, permission/model/audio failure, hint, and accessibility string to Simplified Chinese, Traditional Chinese, and English ARBs; locale coverage and `flutter gen-l10n` are part of the focused test.

- [ ] **Step 4: Run widget, semantics, and full tests**

Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/recitation
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS; no text overflow at text scale 2.0.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/recitation/presentation lib/src/features/scripture/presentation/passage_screen.dart lib/l10n lib/src/app/router.dart test/recitation
git commit -m "feat: add verse and continuous recitation UI"
```

## Task 9: Add offline integration and performance gates

**Files:**
- Create: `integration_test/offline_recitation_test.dart`
- Create: `test/recitation/evaluator_golden_cases.dart`
- Create: `tool/benchmarks/recitation_benchmark.dart`
- Create: `docs/testing/recitation-corpus.md`

**Interfaces:**
- Produces: repeatable phase acceptance commands and benchmark JSON.
- Consumes: complete recitation stack.

- [ ] **Step 1: Add an end-to-end integration test**

```dart
testWidgets('selected passage reaches an offline explainable result', (tester) async {
  final harness = OfflineRecitationHarness(fixturePcm: 'test_assets/audio/john_3_16_zh.wav');
  await tester.pumpWidget(harness.app);
  await harness.openPassage(tester, translation: 'cmn-cu89s', book: 'JHN', chapter: 3, verses: '16');
  await tester.tap(find.text('开始逐节背诵'));
  await harness.feedFixtureAndFinish(tester);
  expect(find.textContaining('通过'), findsOneWidget);
  expect(harness.networkAttempts, isEmpty);
});
```

- [ ] **Step 2: Run the test before adding fixtures/harness and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test integration_test/offline_recitation_test.dart`

Expected: FAIL for missing harness/fixture.

- [ ] **Step 3: Add licensed short fixtures and benchmark output**

Store only fixtures whose consent/license is documented in `docs/testing/recitation-corpus.md`. Benchmark must emit:

```json
{"modelInitMs":0,"audioSeconds":0.0,"decodeMs":0,"realTimeFactor":0.0,"peakRssMb":0.0,"platform":""}
```

Fail the benchmark command when model initialization exceeds 8000 ms or real-time factor exceeds 0.5 on the declared reference device. The 30-minute stability run warms up for 5 minutes, then requires the queue to drain to zero, no missing segment sequence, RSS growth slope at most 1 MiB/minute, and final RSS no more than 20 MiB above the warm-up point.

- [ ] **Step 4: Run the complete phase gate**

Run:

```powershell
.\.toolchains\flutter\bin\dart.bat run tool/models/bin/prepare_models.dart
.\.toolchains\flutter\bin\flutter.bat analyze
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat test integration_test/offline_recitation_test.dart
.\.toolchains\flutter\bin\dart.bat run tool/benchmarks/recitation_benchmark.dart --fixture test_assets/audio/john_3_16_zh.wav
```

Expected: all tests PASS; model files remain local; benchmark JSON satisfies the thresholds.

- [ ] **Step 5: Commit**

```powershell
git add integration_test test/recitation test_assets/audio tool/benchmarks docs/testing
git commit -m "test: verify offline recitation end to end"
```

## Phase Acceptance

The phase is accepted only when a selected CUV or WEB passage can be recorded and evaluated with the network disabled, verse and continuous modes both complete, ambiguous phonetic cases request clarification, unresolved omissions never pass, temporary audio is deleted by default, all unit/widget/integration tests pass, and the reference-device real-time factor is at most 0.5.
