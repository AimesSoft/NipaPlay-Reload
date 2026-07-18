import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/media_path_name.dart';

void main() {
  group('mediaPathName', () {
    test('accepts an already-decoded Unicode filename', () {
      const path = '/media/[云光字幕组] 新 攻壳机动队THE.GHOST.IN.THE.SHELL[01].mp4';

      expect(
        mediaPathName(path),
        '[云光字幕组] 新 攻壳机动队THE.GHOST.IN.THE.SHELL[01].mp4',
      );
    });

    test('preserves a literal percent sign in the filename', () {
      expect(
        mediaPathName('/media/Magical Star Kanon 100%.mkv'),
        'Magical Star Kanon 100%.mkv',
      );
    });

    test('decodes an encoded URI path segment exactly once', () {
      expect(
        mediaPathName('https://media.example/%E6%94%BB%E5%A3%B3%20100%25.mp4'),
        '攻壳 100%.mp4',
      );
    });
  });
}
