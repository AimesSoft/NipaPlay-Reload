import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/harness_repository.dart';

void main() {
  test('existing directory and symlink are untouched, even when empty',
      () async {
    final root = await Directory.systemTemp.createTemp('harness-preservation-');
    addTearDown(() => root.delete(recursive: true));
    final existing = await Directory('${root.path}/existing').create();
    final before = await existing.stat();
    final seed = {'nipa': utf8.encode('replacement')};
    expect(await createHarnessRepository(existing, seed), isFalse);
    expect(await existing.list().toList(), isEmpty);
    expect((await existing.stat()).modified, before.modified);
    if (!Platform.isWindows) {
      await Link('${root.path}/link').create(existing.path);
      expect(
          await createHarnessRepository(Directory('${root.path}/link'), seed),
          isFalse);
      expect(await existing.list().toList(), isEmpty);
    }
  });
}
