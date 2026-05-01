import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';

void main() {
  group('WebDAVFileSorter', () {
    test('keeps folders first and sorts names naturally by default', () {
      final files = [
        WebDAVFile(
            name: 'Episode 10.mkv',
            path: '/Episode 10.mkv',
            isDirectory: false),
        WebDAVFile(name: 'Season 2', path: '/Season 2', isDirectory: true),
        WebDAVFile(
            name: 'Episode 2.mkv', path: '/Episode 2.mkv', isDirectory: false),
        WebDAVFile(name: 'Season 10', path: '/Season 10', isDirectory: true),
      ];

      WebDAVFileSorter.sort(files, WebDAVSortPreset.defaultValue);

      expect(
        files.map((file) => file.name),
        ['Season 2', 'Season 10', 'Episode 2.mkv', 'Episode 10.mkv'],
      );
    });

    test('sorts by modified time with stable name fallback', () {
      final files = [
        WebDAVFile(
          name: 'Episode 10.mkv',
          path: '/Episode 10.mkv',
          isDirectory: false,
          lastModified: DateTime(2026, 1, 1),
        ),
        WebDAVFile(
          name: 'Episode 2.mkv',
          path: '/Episode 2.mkv',
          isDirectory: false,
          lastModified: DateTime(2026, 1, 1),
        ),
        WebDAVFile(
          name: 'Episode 1.mkv',
          path: '/Episode 1.mkv',
          isDirectory: false,
          lastModified: DateTime(2026, 1, 2),
        ),
      ];

      WebDAVFileSorter.sort(files, WebDAVSortPreset.modifiedDesc);

      expect(
        files.map((file) => file.name),
        ['Episode 1.mkv', 'Episode 2.mkv', 'Episode 10.mkv'],
      );
    });
  });
}
