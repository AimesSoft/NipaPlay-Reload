import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';

/// The deletion prompt names what goes and how much, never the manifest.
void main() {
  test('names a few files, counts the rest and adds up the size', () {
    final words = downloadDeletionWords({
      'downloads': [
        {
          'jobId': 'job-1',
          'files': [
            for (var i = 1; i <= 5; i++)
              {'path': '/d/Show - 0$i.mkv', 'expectedSize': 300 << 20, 'included': true},
            {'path': '/d/skipped.mkv', 'expectedSize': 1 << 30, 'included': false},
          ]
        }
      ]
    });
    expect(words, contains('Show - 01.mkv'));
    expect(words, contains('还有 2 个文件'));
    expect(words, contains('1.5 GB'));
    expect(words, isNot(contains('job-1')));
    expect(words, isNot(contains('skipped')));
  });

  test('without file names it counts the downloads', () {
    expect(
        downloadDeletionWords({
          'downloads': [
            {'jobId': 'a', 'files': []},
            {'jobId': 'b', 'files': []}
          ]
        }),
        '将删除 2 个下载留下的数据，无法恢复。');
  });
}
