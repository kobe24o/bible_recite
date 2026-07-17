sealed class RecognitionEvent {
  const RecognitionEvent();
}

final class RecognitionPartial extends RecognitionEvent {
  const RecognitionPartial(this.text);
  final String text;
}

final class RecognitionFinal extends RecognitionEvent {
  const RecognitionFinal(this.text);
  final String text;
}

final class RecognitionInputChanged extends RecognitionEvent {
  const RecognitionInputChanged({required this.label, required this.bluetooth});
  final String label;
  final bool bluetooth;
}

enum RecognitionFailureKind { permissionDenied, model, audio, unknown }

final class RecognitionFailed extends RecognitionEvent {
  const RecognitionFailed(this.kind, this.message);
  final RecognitionFailureKind kind;
  final String message;
}
