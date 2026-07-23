import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sherpa_streaming_recognizer.dart';
import '../domain/speech_recognizer.dart';

/// One recognizer is retained for the lifetime of the app so model files and
/// native model state are prepared only once between recitation screens.
final recitationRecognizerProvider = Provider<OfflineSpeechRecognizer>((ref) {
  final recognizer = SherpaStreamingRecognizer();
  ref.onDispose(() => recognizer.dispose());
  return recognizer;
});
