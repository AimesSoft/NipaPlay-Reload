import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:cp949_codec/cp949_codec.dart' as cp949_codec;
import 'package:enough_convert/big5.dart' as enough_big5;

/// Pure Dart decoder for legacy subtitle encodings.
///
/// The native subtitle parser remains the preferred path because iconv also
/// covers extensions such as the full GB18030 and Big5-HKSCS repertoires. This
/// decoder keeps the Dart fallback usable on platforms without plugin channels,
/// including HarmonyOS.
class LegacyCharsetDecoder {
  const LegacyCharsetDecoder._();

  static String? decode(List<int> bytes, String encodingName) {
    final normalized = encodingName.trim().toLowerCase().replaceAll('_', '-');
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized == 'euc-kr' ||
        normalized == 'euckr' ||
        normalized == 'cp949' ||
        normalized == 'windows-949') {
      return cp949_codec.cp949.decode(bytes);
    }

    final Encoding? encoding = switch (normalized) {
      'big5' ||
      'big-5' ||
      'cp950' ||
      'windows-950' ||
      'big5-hkscs' ||
      'big5hkscs' =>
        enough_big5.big5,
      _ => charset.Charset.getByName(normalized),
    };

    return encoding?.decode(bytes);
  }
}
