import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/media_source_utils.dart';

void main() {
  group('MediaSourceUtils.isContentUri', () {
    test('accepts Android SAF media sources', () {
      expect(
        MediaSourceUtils.isContentUri(
          'content://com.android.providers.media.documents/document/video%3A42',
        ),
        isTrue,
      );
      expect(
          MediaSourceUtils.isContentUri('  CONTENT://provider/item  '), isTrue);
    });

    test('does not classify file and network sources as content URIs', () {
      expect(MediaSourceUtils.isContentUri('/storage/emulated/0/video.mkv'),
          isFalse);
      expect(MediaSourceUtils.isContentUri('file:///tmp/video.mkv'), isFalse);
      expect(MediaSourceUtils.isContentUri('https://example.test/video.mkv'),
          isFalse);
    });
  });
}
