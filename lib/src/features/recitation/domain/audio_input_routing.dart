import 'package:record/record.dart';

final class AudioInputRouting {
  const AudioInputRouting._();

  static bool isBluetooth(InputDevice device) => switch (device.type) {
    InputDeviceType.bluetoothSco ||
    InputDeviceType.bluetoothA2dp ||
    InputDeviceType.bluetoothLe => true,
    _ => false,
  };

  static InputDevice? phoneMicrophone(Iterable<InputDevice> devices) {
    for (final device in devices) {
      if (device.type == InputDeviceType.builtIn) return device;
    }
    for (final device in devices) {
      if (!isBluetooth(device)) return device;
    }
    return null;
  }

  /// Desktops follow the user's system input, including USB/Bluetooth mics.
  static RecordConfig recordConfig(
    Iterable<InputDevice> devices, {
    required int sampleRate,
    required bool desktop,
  }) => desktop
      ? RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: true,
        )
      : phoneRecordConfig(devices, sampleRate: sampleRate);

  static RecordConfig phoneRecordConfig(
    Iterable<InputDevice> devices, {
    required int sampleRate,
  }) => RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    device: phoneMicrophone(devices),
    autoGain: true,
    noiseSuppress: true,
    androidConfig: const AndroidRecordConfig(
      manageBluetooth: false,
      audioSource: AndroidAudioSource.mic,
      audioManagerMode: AudioManagerMode.modeNormal,
    ),
  );
}
