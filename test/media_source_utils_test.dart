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

  group('remote playback error display', () {
    test('decodes a WebDAV Chinese path without showing URL credentials', () {
      const error =
          '播放器打开媒体失败: https://viewer%40example.test:secret%20word@dav.example.test/root/%E5%8A%A8%E6%BC%AB/%E7%AC%AC1%E9%9B%86.mkv';

      final display = MediaSourceUtils.playbackErrorForDisplay(
        error,
        'webdav://connection-id/动漫/第1集.mkv',
      );

      expect(display, contains('https://dav.example.test/root/动漫/第1集.mkv'));
      expect(display, isNot(contains('viewer')));
      expect(display, isNot(contains('secret')));
      expect(error, contains('%E5%8A%A8'));
    });

    test('decodes the SMB proxy path query without changing other sources', () {
      const error =
          '打开失败: http://127.0.0.1:8123/smb/stream?conn=media&path=%2F%E4%B8%AD%E6%96%87%E7%9B%AE%E5%BD%95%2Fmovie.mkv';

      final display = MediaSourceUtils.playbackErrorForDisplay(
        error,
        'smb://media/中文目录/movie.mkv',
      );

      expect(display, contains('中文目录'));
      expect(display, contains('conn=media&path=/中文目录/movie.mkv'));
      expect(MediaSourceUtils.playbackErrorForDisplay(error, '/tmp/movie.mkv'),
          error);
      expect(
        MediaSourceUtils.playbackErrorForDisplay(
          error,
          'https://cdn.example.test/movie.mkv',
        ),
        error,
      );
    });

    test('keeps a malformed escape while still hiding credentials', () {
      const error = '无法打开 https://user:password@dav.example.test/bad%ZZ';
      final display = MediaSourceUtils.playbackErrorForDisplay(
        error,
        'webdav://connection-id/bad%ZZ',
      );

      expect(display, contains('https://dav.example.test/bad%ZZ'));
      expect(display, isNot(contains('password')));
    });
  });
}
