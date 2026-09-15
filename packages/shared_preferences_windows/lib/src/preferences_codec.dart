import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Both JSON escaping and UTF-8 conversion are CPU work, even when the final
/// file write is asynchronous. Isolate.run transfers the result on exit without
/// copying the byte buffer back onto the caller's heap.
Future<Uint8List> encodePreferences(Map<String, Object> snapshot) =>
    Isolate.run(
      () => utf8.encode(json.encode(snapshot)),
      debugName: 'nipaplay.preferences.encode',
    );
