import 'package:charset/charset.dart';

typedef CharEncoding = CodePage;
// class Encoding {
//   List<int> encode(String s) {
//     return [];
//   }
// }

// class Utf16LeCodec extends Encoding {
//   /// Utf16 Codec
//   const Utf16LeCodec();

//   @override
//   Converter<List<int>, String> get decoder => Utf16leBytesToCodeUnitsDecoder();

//   @override
//   Converter<String, List<int>> get encoder => const Utf16Encoder();

//   @override
//   String get name => 'utf-16';
// }