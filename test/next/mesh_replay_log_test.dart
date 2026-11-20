import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/replay_log.dart';

void main() {
  late File file;
  late int now;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('mesh-replay-test-');
    addTearDown(() => root.delete(recursive: true));
    file = File('${root.path}/mesh-replay.jsonl');
    now = 1000;
  });

  String record(String key) => jsonEncode({
        'keys': [key],
        'deadline': 2000
      });

  test('a torn tail is discarded, a complete final record is retained',
      () async {
    await file
        .writeAsBytes([...utf8.encode('${record('old')}\n{"keys":["'), 0xc3]);
    final log = MeshReplayLog(file, now: () => now);
    await log.load();
    expect(await log.admit(['old'], 2000), ReplayAdmission.duplicate);
    expect(await log.admit(['new'], 2000), ReplayAdmission.accepted);

    await file.writeAsString(record('complete'), mode: FileMode.append);
    final reopened = MeshReplayLog(file, now: () => now);
    await reopened.load();
    expect(await reopened.admit(['complete'], 2000), ReplayAdmission.duplicate);
  });

  test('a bad terminated record fails closed without modifying the file',
      () async {
    final original = '${record('first')}\n{broken\n${record('last')}\n';
    await file.writeAsString(original);
    await expectLater(
        MeshReplayLog(file, now: () => now).load(), throwsFormatException);
    expect(await file.readAsString(), original);
  });

  test('running compaction drops expired records without forgetting live keys',
      () async {
    final log = MeshReplayLog(file, now: () => now, compactAfter: 4);
    await log.load();
    await log.admit(['live'], now + 1000);
    for (var index = 0; index < 40; index++) {
      now++;
      expect(await log.admit(['id-$index', 'nonce-$index'], now + 2),
          ReplayAdmission.accepted);
      expect(await file.readAsLines(), hasLength(lessThanOrEqualTo(7)));
    }
    final reopened = MeshReplayLog(file, now: () => now);
    await reopened.load();
    expect(
        await reopened.admit(['live'], now + 1000), ReplayAdmission.duplicate);
    final raced = await Future.wait([
      reopened.admit(['id-race', 'nonce-first'], now + 100),
      reopened.admit(['id-race', 'nonce-second'], now + 100),
    ]);
    expect(raced, [ReplayAdmission.accepted, ReplayAdmission.duplicate]);
  });
}
