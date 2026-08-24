import 'dart:convert';

/// Stable, non-display identity for a playable media object.
///
/// Paths are canonicalized as opaque bytes. We deliberately do not use
/// [Uri.decodeComponent]: malformed percent escapes must not throw, and an
/// encoded slash (`%2F`) must never turn into a path separator.
class MediaIdentity {
  const MediaIdentity({
    required this.source,
    required this.sourceId,
    required this.objectKey,
  });

  final String source;
  final String sourceId;
  final String objectKey;

  String get key => '$source:${_field(sourceId)}:$objectKey';

  static String remotePathKey({
    required String source,
    required String connectionId,
    required String rawPath,
    bool normalizeBackslashes = false,
  }) {
    return MediaIdentity(
      source: source,
      sourceId: connectionId,
      objectKey: OpaqueMediaPath.canonicalize(
        rawPath,
        normalizeBackslashes: normalizeBackslashes,
      ),
    ).key;
  }

  static String object({
    required String source,
    required String sourceId,
    required String objectId,
  }) {
    return MediaIdentity(
      source: source,
      sourceId: sourceId,
      objectKey: _field(objectId),
    ).key;
  }

  static String _field(String value) => Uri.encodeComponent(value.trim());
}

class OpaqueMediaPath {
  const OpaqueMediaPath._();

  static String canonicalize(
    String value, {
    bool normalizeBackslashes = false,
  }) {
    var input = value;
    if (normalizeBackslashes) input = input.replaceAll('\\', '/');
    if (!input.startsWith('/')) input = '/$input';

    return input.split('/').map(_canonicalizeSegment).join('/');
  }

  static String _canonicalizeSegment(String segment) {
    final output = StringBuffer();
    var index = 0;
    while (index < segment.length) {
      final codeUnit = segment.codeUnitAt(index);
      if (codeUnit == 0x25 && index + 2 < segment.length) {
        final high = _hexValue(segment.codeUnitAt(index + 1));
        final low = _hexValue(segment.codeUnitAt(index + 2));
        if (high >= 0 && low >= 0) {
          _writeByte(output, high * 16 + low);
          index += 3;
          continue;
        }
      }

      final rune = segment.substring(index).runes.first;
      final scalar = String.fromCharCode(rune);
      for (final byte in utf8.encode(scalar)) {
        _writeByte(output, byte);
      }
      index += scalar.length;
    }
    return output.toString();
  }

  static void _writeByte(StringBuffer output, int byte) {
    if (_isUnreserved(byte)) {
      output.writeCharCode(byte);
      return;
    }
    output
      ..write('%')
      ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }

  static bool _isUnreserved(int byte) {
    return (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5F ||
        byte == 0x7E;
  }

  static int _hexValue(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
    if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x41 + 10;
    if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x61 + 10;
    return -1;
  }
}
