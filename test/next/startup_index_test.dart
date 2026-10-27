import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/media/startup_index.dart';

void main() {
  test('startup indexes local roots and reports unavailable or remote roots',
      () async {
    final root = await Directory.systemTemp.createTemp('next-startup-index-');
    addTearDown(() => root.delete(recursive: true));
    final calls = <String>[];
    final report = await submitStartupIndex(
        enabled: true,
        roots: [
          root.path,
          root.path,
          '${root.path}/missing',
          'webdav://server/media'
        ],
        submit: (path) async {
          calls.add(path);
        });
    expect(calls, [root.path]);
    expect(report['submitted'], calls);
    expect((report['skipped'] as List).map((e) => e['reason']),
        ['directory_unavailable', 'not_local_directory']);
    await submitStartupIndex(
        enabled: false,
        roots: [root.path],
        submit: (path) async {
          fail('disabled index submitted a job');
        });
  });
}
