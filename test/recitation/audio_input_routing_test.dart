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
}
