import 'dart:typed_data';

abstract interface class SpeechDecoder {
  Future<String> accept(Uint8List pcm);
  Future<String> finish();

  /// Interrupt network work immediately; local decode drains before close.
  void cancel();
  Future<void> close();
}
