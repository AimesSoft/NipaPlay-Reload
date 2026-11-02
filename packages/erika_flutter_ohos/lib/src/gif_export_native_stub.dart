Future<Map<String, Object?>> exportGifNative(Map<String, Object?> options) {
  throw UnsupportedError('Erika GIF export is not available on Web.');
}

Future<Map<String, Object?>> exportFrameNative(Map<String, Object?> options) {
  throw UnsupportedError('Erika frame export is not available on Web.');
}

/// Web has no native library: a session cannot be opened.
final class NativeFrameExportSession {
  NativeFrameExportSession._();

  static Future<NativeFrameExportSession> open(Map<String, Object?> arguments) {
    throw UnsupportedError('Erika frame export is not available on Web.');
  }

  Future<Map<String, Object?>> frame(Map<String, Object?> arguments) {
    throw UnsupportedError('Erika frame export is not available on Web.');
  }

  Future<void> close() async {}
}
