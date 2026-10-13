import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/headless/downloads.dart';

void main() {
  test('download rejects symlink ancestors before writing into read-only media',
      () async {
    final temporary = await Directory.systemTemp.createTemp('x45-output-');
    try {
      final media = await Directory('${temporary.path}/media').create();
      final alias = await Link('${temporary.path}/alias').create(media.path);
      final backend = HeadlessDownloadBackend(readOnlyRoots: [media.path]);
      await expectLater(backend.prepareDirectory('${alias.path}/new/nested'),
          throwsA(isA<Failure>()));
      expect(await media.list().toList(), isEmpty);
      final normal =
          await backend.prepareDirectory('${temporary.path}/output/nested');
      expect(await Directory(normal).exists(), isTrue);
    } finally {
      await temporary.delete(recursive: true);
    }
  },
      skip: Platform.isWindows
          ? 'Symlink creation requires Windows host privileges.'
          : false);
}
