import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/webdav_service.dart';
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

  group('WebDAV playable URL credentials', () {
    test('encodes an email username and reserved password characters', () {
      const username = 'viewer@example.test';
      const password = r'p@ss:/?#% word$';
      final connection = WebDAVConnection(
        id: 'connection-id',
        name: 'WebDAV',
        url: 'https://dav.example.test/root',
        username: username,
        password: password,
      );

      final url = WebDAVService.instance.getFileUrl(
        connection,
        '/Anime/[ANi] Example - 01 [1080P].mp4',
      );
      final uri = Uri.parse(url);

      expect(Uri.decodeComponent(uri.userInfo), '$username:$password');
      expect(url, isNot(contains(username)));
      expect(url, isNot(contains(password)));
      expect(
        uri.path,
        '/root/Anime/%5BANi%5D%20Example%20-%2001%20%5B1080P%5D.mp4',
      );
    });

    test('remote path errors never expose their source value', () {
      const error = FormatException(
        'Invalid character',
        'viewer@example.test:super-secret',
      );

      final safe = MediaSourceUtils.safeRemotePathError(error);

      expect(safe, 'FormatException');
      expect(safe, isNot(contains('viewer@example.test')));
      expect(safe, isNot(contains('super-secret')));
    });
  });
}
