import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/legacy_charset_decoder.dart';

void main() {
  group('LegacyCharsetDecoder', () {
    test('decodes GBK and the GBK-compatible GB18030 subset', () {
      const bytes = [0xD6, 0xD0, 0xCE, 0xC4];

      expect(LegacyCharsetDecoder.decode(bytes, 'gbk'), '中文');
      expect(LegacyCharsetDecoder.decode(bytes, 'gb18030'), '中文');
    });

    test('decodes Big5 aliases', () {
      const bytes = [0xA4, 0xA4, 0xA4, 0xE5];

      expect(LegacyCharsetDecoder.decode(bytes, 'big5'), '中文');
      expect(LegacyCharsetDecoder.decode(bytes, 'cp950'), '中文');
      expect(LegacyCharsetDecoder.decode(bytes, 'big5-hkscs'), '中文');
    });

    test('decodes Shift-JIS', () {
      const bytes = [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA];

      expect(LegacyCharsetDecoder.decode(bytes, 'shift_jis'), '日本語');
    });

    test('decodes EUC-KR', () {
      const bytes = [0xC7, 0xD1, 0xB1, 0xB9, 0xBE, 0xEE];

      expect(LegacyCharsetDecoder.decode(bytes, 'euc-kr'), '한국어');
    });

    test('decodes Windows-1252', () {
      const bytes = [0x63, 0x61, 0x66, 0xE9, 0x20, 0x80];

      expect(
        LegacyCharsetDecoder.decode(bytes, 'windows-1252'),
        'café €',
      );
    });

    test('returns null for an unsupported encoding', () {
      expect(LegacyCharsetDecoder.decode(const [0x41], 'made-up'), isNull);
    });
  });
}
