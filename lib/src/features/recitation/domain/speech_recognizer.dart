import 'recognition_models.dart';

abstract interface class OfflineSpeechRecognizer {
  Stream<RecognitionEvent> get events;

  Future<void> initialize();

  Future<void> start({required String languageTag});

  Future<void> pause();

  Future<void> resume();

  Future<void> stop();

  Future<void> dispose();
}
