import 'dart:typed_data';

abstract class Message {
  /// Indicate that this message should retain it's raw payload
  void setRetainPayload();

  /// whether to retain the message payload
  bool isRetainPayload();

  /// the raw response message
  Uint8List? getRawPayload();

  void setRawPayload(Uint8List rawPayload);
}
