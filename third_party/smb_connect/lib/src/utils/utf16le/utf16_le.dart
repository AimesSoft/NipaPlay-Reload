import 'dart:convert';

import 'package:charset/charset.dart';

class Utf16LeCodec extends Encoding {
  /// Utf16 Codec
  // const Utf16LeCodec();
  // final Utf16Encoder _encoder = utf16.encoder as Utf16Encoder;
  // final Utf16Decoder _decoder = utf16.decoder as Utf16Decoder;

  @override
  Converter<List<int>, String> get decoder => Utf16LeDecoder();

  @override
  Converter<String, List<int>> get encoder => Utf16LeEncoder();

  @override
  String get name => 'utf-16le';
}

final Encoding utf16le = Utf16LeCodec();

class Utf16LeEncoder extends Converter<String, List<int>> {
  final Utf16Encoder _encoder = utf16.encoder as Utf16Encoder;

  @override
  List<int> convert(String input) => _encoder.encodeUtf16Le(input);
}

class Utf16LeDecoder extends Converter<List<int>, String> {
  final Utf16Decoder _decoder = utf16.decoder as Utf16Decoder;

  @override
  String convert(List<int> input) => _decoder.decodeUtf16Le(input);
}
