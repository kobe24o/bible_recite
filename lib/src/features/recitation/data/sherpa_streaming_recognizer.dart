import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/audio_input_routing.dart';
import '../domain/recognition_models.dart';
import '../domain/speech_recognizer.dart';

final class SherpaStreamingRecognizer implements OfflineSpeechRecognizer {
  SherpaStreamingRecognizer({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const sampleRate = 16000;
  static const _assetRoot = 'assets/models/sherpa';
  static bool _bindingsInitialized = false;

  final AudioRecorder _recorder;
  final _events = StreamController<RecognitionEvent>.broadcast();
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  String _committedText = '';
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<RecognitionEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (!_bindingsInitialized) {
        sherpa.initBindings();
        _bindingsInitialized = true;
      }
      final encoder = await _copyAsset('encoder.onnx');
      final decoder = await _copyAsset('decoder.onnx');
      final joiner = await _copyAsset('joiner.onnx');
      final tokens = await _copyAsset('tokens.txt');
      final model = sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: encoder,
          decoder: decoder,
          joiner: joiner,
        ),
        tokens: tokens,
        numThreads: 4,
        debug: false,
        modelType: 'zipformer',
      );
      _recognizer = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          model: model,
          decodingMethod: 'greedy_search',
          enableEndpoint: true,
          rule1MinTrailingSilence: 2.4,
          rule2MinTrailingSilence: 1.2,
          rule3MinUtteranceLength: 20,
        ),
      );
      _initialized = true;
    } catch (error) {
      _events.add(
        RecognitionFailed(RecognitionFailureKind.model, error.toString()),
      );
      rethrow;
    }
  }

  Future<String> _copyAsset(String name) async {
    final directory = await getApplicationSupportDirectory();
    final modelDirectory = Directory('${directory.path}/sherpa-zipformer');
    await modelDirectory.create(recursive: true);
    final target = File('${modelDirectory.path}/$name');
    final data = await rootBundle.load('$_assetRoot/$name');
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await target.writeAsBytes(bytes, flush: true);
    }
    return target.path;
  }

  @override
  Future<void> start({required String languageTag}) async {
    await initialize();
    if (!await _recorder.hasPermission()) {
      const failure = RecognitionFailed(
        RecognitionFailureKind.permissionDenied,
        'Microphone permission denied',
      );
      _events.add(failure);
      throw StateError(failure.message);
    }
    await _audioSubscription?.cancel();
    _stream?.free();
    _stream = _recognizer!.createStream();
    _committedText = '';
    List<InputDevice> devices = const [];
    try {
      devices = await _recorder.listInputDevices();
    } catch (_) {
      // Some Android vendors do not expose input enumeration. The Android
      // config still disables Bluetooth routing and requests the phone mic.
    }
    final config = AudioInputRouting.phoneRecordConfig(
      devices,
      sampleRate: sampleRate,
    );
    final audio = await _recorder.startStream(config);
    _audioSubscription = audio.listen(
      _acceptBytes,
      onError: (Object error) => _events.add(
        RecognitionFailed(RecognitionFailureKind.audio, error.toString()),
      ),
    );
    _events.add(
      RecognitionInputChanged(
        label: config.device?.label ?? '手机麦克风',
        bluetooth: false,
      ),
    );
  }

  void _acceptBytes(Uint8List bytes) {
    final evenLength = bytes.lengthInBytes - (bytes.lengthInBytes % 2);
    if (evenLength == 0 || _stream == null) return;
    final data = ByteData.sublistView(bytes, 0, evenLength);
    final samples = Float32List(evenLength ~/ 2);
    for (var offset = 0; offset < evenLength; offset += 2) {
      samples[offset ~/ 2] = data.getInt16(offset, Endian.little) / 32768.0;
    }
    _stream!.acceptWaveform(samples: samples, sampleRate: sampleRate);
    _decodeAvailable();
  }

  void _decodeAvailable() {
    final recognizer = _recognizer;
    final stream = _stream;
    if (recognizer == null || stream == null) return;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    final current = recognizer.getResult(stream).text.trim();
    final combined = [
      _committedText,
      current,
    ].where((text) => text.isNotEmpty).join(' ');
    if (combined.isNotEmpty) _events.add(RecognitionPartial(combined));
    if (recognizer.isEndpoint(stream)) {
      if (current.isNotEmpty) {
        _committedText = [
          _committedText,
          current,
        ].where((text) => text.isNotEmpty).join(' ');
      }
      recognizer.reset(stream);
    }
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<void> stop() async {
    await _recorder.stop();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    final stream = _stream;
    if (stream == null) return;
    stream.inputFinished();
    _decodeAvailable();
    final tail = _recognizer!.getResult(stream).text.trim();
    final text = [
      _committedText,
      tail,
    ].where((part) => part.isNotEmpty).join(' ');
    _events.add(RecognitionFinal(text));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _audioSubscription?.cancel();
    await _recorder.dispose();
    _stream?.free();
    _recognizer?.free();
    await _events.close();
  }
}
