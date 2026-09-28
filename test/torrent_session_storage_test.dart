import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/torrent_session_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('torrent-session-test-'));
  tearDown(() async => root.delete(recursive: true));

  Future<void> legacy(String folder, String hash) async {
    final directory =
        Directory(p.join(root.path, folder, '.nipaplay_torrent_session'));
    await directory.create(recursive: true);
    await File(p.join(directory.path, 'session.json'))
        .writeAsString(jsonEncode({
      'torrents': {
        '0': {
          'info_hash': hash,
          'output_folder': p.join(root.path, folder),
          'is_paused': true,
          'trackers': [],
          'only_files': null,
        }
      }
    }));
    await File(p.join(directory.path, '$hash.torrent'))
        .writeAsString('metadata-$hash');
    await File(p.join(directory.path, '$hash.bitv'))
        .writeAsString('resume-$hash');
  }

  test(
      'merges directories with colliding IDs, preserves paths and pause state, and copies resume data',
      () async {
    final hashA = 'a' * 40;
    final hashB = 'b' * 40;
    await legacy('A', hashA);
    await legacy('B', hashB);
    final stable = Directory(p.join(root.path, 'support', 'torrent_session'));
    final result = await TorrentSessionStorage.prepare(
        stable, [p.join(root.path, 'B'), p.join(root.path, 'A')]);
    expect(result, stable.path);
    final data =
        jsonDecode(await File(p.join(result, 'session.json')).readAsString())
            as Map;
    final tasks = (data['torrents'] as Map).values.toList();
    expect(tasks, hasLength(2));
    expect(tasks.map((t) => t['output_folder']),
        unorderedEquals([p.join(root.path, 'A'), p.join(root.path, 'B')]));
    expect(tasks.every((t) => t['is_paused'] == true), isTrue);
    expect(await File(p.join(result, '$hashA.bitv')).readAsString(),
        'resume-$hashA');
    expect(
        await File(p.join(
                root.path, 'A', '.nipaplay_torrent_session', 'session.json'))
            .exists(),
        isTrue);
  });

  test(
      'restarting with a new default directory does not resurrect removed tasks',
      () async {
    await legacy('A', 'a' * 40);
    await legacy('B', 'b' * 40);
    final stable = Directory(p.join(root.path, 'support'));
    await TorrentSessionStorage.prepare(
        stable, [p.join(root.path, 'A'), p.join(root.path, 'B')]);
    // rqbit rewrites its database when tasks are removed.
    await File(p.join(stable.path, 'session.json'))
        .writeAsString('{"torrents":{}}');
    await TorrentSessionStorage.prepare(
        stable, [p.join(root.path, 'B'), p.join(root.path, 'A')]);
    expect(
        (jsonDecode(
                await File(p.join(stable.path, 'session.json')).readAsString())
            as Map)['torrents'],
        isEmpty);
  });

  test('the same hash from multiple old directories is imported once',
      () async {
    await legacy('A', 'a' * 40);
    await legacy('B', 'a' * 40);
    final stable = Directory(p.join(root.path, 'support'));
    await TorrentSessionStorage.prepare(
        stable, [p.join(root.path, 'A'), p.join(root.path, 'B')]);
    final data = jsonDecode(
        await File(p.join(stable.path, 'session.json')).readAsString()) as Map;
    expect(data['torrents'], hasLength(1));
  });
}
