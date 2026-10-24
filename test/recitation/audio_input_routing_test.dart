import 'package:bible_recite/src/features/recitation/domain/audio_input_routing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('uses built-in phone mic even when bluetooth SCO is connected', () {
    const builtIn = InputDevice(
      id: '1',
      label: 'Phone mic',
      type: InputDeviceType.builtIn,
    );
    const a2dp = InputDevice(
      id: '2',
      label: 'Headphones',
      type: InputDeviceType.bluetoothA2dp,
    );
    const sco = InputDevice(
      id: '3',
      label: 'Headset',
      type: InputDeviceType.bluetoothSco,
    );

    final config = AudioInputRouting.phoneRecordConfig([
      sco,
      a2dp,
      builtIn,
    ], sampleRate: 16000);

    expect(config.device, builtIn);
    expect(config.androidConfig.manageBluetooth, isFalse);
    expect(config.androidConfig.audioSource, AndroidAudioSource.mic);
    expect(config.androidConfig.audioManagerMode, AudioManagerMode.modeNormal);
  });
  test(
    'desktop recording follows the system input instead of forcing the built-in mic',
    () {
      const builtIn = InputDevice(
        id: '1',
        label: 'Built in',
        type: InputDeviceType.builtIn,
      );
      final config = AudioInputRouting.recordConfig(
        [builtIn],
        sampleRate: 16000,
        desktop: true,
      );
      expect(config.device, isNull);
      expect(config.encoder, AudioEncoder.pcm16bits);
      expect(config.numChannels, 1);
      expect(config.sampleRate, 16000);
      expect(
        AudioInputRouting.recordConfig(
          [builtIn],
          sampleRate: 16000,
          desktop: false,
        ).device,
        builtIn,
      );
    },
  );
}
