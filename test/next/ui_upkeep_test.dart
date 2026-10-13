import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipa_harness/nipa_harness.dart' as h show Invocation;
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/upkeep.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/settings/registry_rows.dart';
import 'package:nipaplay/next/ui/settings/section_misc.dart';

/// The upkeep pages read the capability layer through these: caches by
/// the kinds a person knows, cleared with the plan they were shown; a
/// check for updates that failed says so; sync and folders as they are.
void main() {
  test('caches: each kind gathers its stores; clearing prunes its own plan',
      () async {
    final world = _World();
    final upkeep = NextUpkeep(world.calls);

    final kinds = await upkeep.caches();
    expect([for (final k in kinds) k.id], ['images', 'danmaku', 'thumbnails']);
    expect([for (final k in kinds) k.title], ['图片', '弹幕', '缩略图']);
    expect(world.plans, [
      ['images', 'nextArtwork'],
      ['classicDanmaku', 'nextDanmaku'],
      ['thumbnails', 'timeline'],
    ]);
    final danmaku = kinds[1];
    expect(danmaku.bytes, 300 + 100);
    expect(danmaku.kept, 12);
    expect(kinds[2].kept, 0);

    world.plans.clear();
    final freed = await upkeep.clear('danmaku');
    expect(world.plans, [
      ['classicDanmaku', 'nextDanmaku']
    ]);
    // The plan just made, not one shown earlier.
    expect(world.pruned, ['plan-4']);
    expect(freed, 400);
    expect((await upkeep.caches())[1].bytes, 0);
  });

  test('space: the downloads inside NipaPlay’s folder are not counted twice',
      () async {
    final world = _World();
    final space = await NextUpkeep(world.calls).space();
    expect(space.downloads, 4000);
    expect(space.app, 5000 - 4000);
    expect(space.free, 200000);
    expect(space.total, 1000000);

    world.downloadsElsewhere = true;
    final apart = await NextUpkeep(world.calls).space();
    expect(apart.app, 5000);
    expect(apart.downloads, 4000);
  });

  test('a check that failed is a failure; none yet is nothing', () async {
    final found = UiUpdateCheck.from({
      'currentVersion': '1.9.3',
      'latestVersion': '1.9.4',
      'hasUpdate': true,
      'publicReleaseUrl': 'https://github.com/x/releases/tag/v1.9.4',
      'error': null,
    });
    expect(found.newer, isTrue);
    expect(found.latest, '1.9.4');
    expect(found.page, isTrue);
    expect(found.failed, isFalse);

    final failed = UiUpdateCheck.from({
      'currentVersion': '1.9.3',
      'latestVersion': null,
      'hasUpdate': null,
      'publicReleaseUrl': null,
      'error': {'code': 'update_check_failed', 'retryable': true},
    });
    expect(failed.failed, isTrue);
    expect(failed.newer, isNull);
    expect(failed.page, isFalse);

    final world = _World();
    final upkeep = NextUpkeep(world.calls);
    expect(await upkeep.lastUpdate(), isNull);
    world.checked = {'currentVersion': '1.9.3', 'hasUpdate': false};
    final last = await upkeep.lastUpdate();
    expect(last!.newer, isFalse);
    expect(last.failed, isFalse);
  });

  test('sync reads its configuration and state', () async {
    final at = DateTime.utc(2026, 10, 13, 8, 30);
    final s = UiSync.from({
      'configuration': {
        'url': 'https://dav.example.net/dav',
        'username': 'hikari',
        'remotePath': '/NipaPlay',
        'intervalMinutes': 15,
        'categories': ['watchHistory', 'preferences'],
        'syncOnRecordChange': true,
      },
      'enabled': true,
      'syncing': false,
      'lastSyncAt': at.toIso8601String(),
      'lastError': '',
    });
    expect(s.url, 'https://dav.example.net/dav');
    expect(s.username, 'hikari');
    expect(s.folder, '/NipaPlay');
    expect(s.minutes, 15);
    expect(s.kinds, ['watchHistory', 'preferences']);
    expect(s.onChange, isTrue);
    expect(s.enabled, isTrue);
    expect(s.configured, isTrue);
    expect(s.last, at.toLocal());
    expect(s.error, isNull);

    final fresh = UiSync.from({
      'configuration': {'url': '', 'categories': []},
      'lastSyncAt': null,
      'lastError': 'Unauthorized',
    });
    expect(fresh.configured, isFalse);
    expect(fresh.minutes, 30);
    expect(fresh.last, isNull);
    expect(fresh.error, 'Unauthorized');

    final world = _World()..syncAnswers = false;
    expect(await NextSync(world.calls).test(), isFalse);
  });

  test('folders: roots, the files a scan could not take, where each is',
      () async {
    final f = UiFolders.from({
      'roots': ['/Users/hikari/Movies/番剧', '/Volumes/NAS/动画'],
      'scanning': true,
      'failedFiles': [
        {'path': '/Volumes/NAS/动画/broken.mkv', 'reason': 'unreadable'},
        {'path': '/Volumes/NAS/动画/S1/bad.mp4', 'reason': 'unreadable'},
      ],
    });
    expect(f.paths, hasLength(2));
    expect(f.scanning, isTrue);
    expect(f.failed, 2);
    expect(f.failedIn('/Volumes/NAS/动画'), 2);
    expect(f.failedIn('/Users/hikari/Movies/番剧'), 0);
    expect(f.failedIn('/Volumes/NAS/动'), 0);

    final world = _World();
    final folders = NextFolders(world.calls);
    expect(await folders.add(), ['/Users/hikari/Movies/电影']);
    expect(await folders.scan(['/Users/hikari/Movies/电影']), 'scan-1');
    expect(world.scanned, [
      ['/Users/hikari/Movies/电影']
    ]);
    final near = await folders.nearby();
    expect(near.single.name, '客厅的 Mac mini');
    expect(near.single.address, 'http://192.168.1.20:1180');
  });

  testWidgets('storage: the room left, each cache, and 空 once cleared',
      (tester) async {
    final world = _World();
    final model = SettingsModel(FakeSettings());
    await tester.runAsync(model.load);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: SingleChildScrollView(
          child: StorageSection(
            upkeep: NextUpkeep(world.calls),
            model: model,
            more: false,
            onMore: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('195 KB'), findsOneWidget);
    expect(find.text('共 977 KB'), findsOneWidget);
    expect(find.text('3.9 KB'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('保留 12 B'), findsOneWidget);
    expect(find.text('400 B'), findsOneWidget);

    await tester.tap(find.text('清理').at(1));
    await tester.pumpAndSettle();
    expect(world.pruned, hasLength(1));
    expect(find.text('空'), findsOneWidget);
  });
}

/// A capability layer with just the upkeep Actions, its stores in bytes.
final class _World {
  final caches = {
    'images': 800,
    'nextArtwork': 200,
    'classicDanmaku': 300,
    'nextDanmaku': 100,
    'thumbnails': 50,
    'timeline': 25,
  };
  final plans = <List<String>>[];
  final _planned = <String, List<String>>{};
  final pruned = <String>[];
  final scanned = <List<String>>[];
  JsonMap? checked;
  bool downloadsElsewhere = false;
  bool syncAnswers = true;

  late final harness = Harness([
    _Capability([
      _Action('storage.status', (_) => {
            'directories': [
              {'role': 'app', 'path': '/Library/NipaPlay', 'bytes': 5000},
              {
                'role': 'downloads',
                'path': downloadsElsewhere
                    ? '/Volumes/NAS/下载'
                    : '/Library/NipaPlay/downloads',
                'bytes': 4000
              },
            ],
            'volumes': [
              {'availableBytes': 200000, 'totalBytes': 1000000}
            ],
          }),
      _Action('cache.plan', (input) {
        final kinds = (input['kinds'] as List).cast<String>();
        plans.add(kinds);
        final id = 'plan-${_planned.length + 1}';
        _planned[id] = kinds;
        return {
          'planId': id,
          'reclaimableBytes': kinds.fold<int>(0, (n, k) => n + caches[k]!),
          'retained': [
            if (kinds.contains('nextDanmaku'))
              {'kind': 'nextDanmaku', 'bytes': 12},
          ],
        };
      }),
      _Action('cache.prune', (input) {
        final id = input['planId'] as String;
        pruned.add(id);
        var removed = 0;
        for (final k in _planned[id]!) {
          removed += caches[k]!;
          caches[k] = 0;
        }
        return {'planId': id, 'removedBytes': removed};
      }),
      _Action('app.update.status',
          (_) => {'checking': false, 'result': checked}),
      _Action('sync.test', (_) {
        if (!syncAnswers) {
          throw const Failure(FailureCode.unavailable, 'No server.');
        }
        return {'connected': true};
      }),
      _Action('media.library.roots.add',
          (_) => {'selected': ['/Users/hikari/Movies/电影'], 'roots': []}),
      _Action('media.library.scan_classic', (input) {
        scanned.add((input['paths'] as List).cast<String>());
        return {'jobId': 'scan-${scanned.length}'};
      }),
      _Action('media.sources.discover', (_) => {
            'candidates': [
              {
                'address': 'http://192.168.1.20:1180',
                'kind': 'nipaplay_shared',
                'name': '客厅的 Mac mini',
              }
            ],
          }),
    ]),
  ]);

  GuiCalls get calls => GuiCalls(() async => harness);
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Action extends Action<_Json, _Json> {
  _Action(this.id, this.answer);
  final String id;
  final JsonMap Function(JsonMap input) answer;

  @override
  ActionSpec get spec => ActionSpec(
        id: id,
        title: id,
        description: 'Test.',
        effect: Effect.write,
        input: const ObjectSchema({}, additionalProperties: true),
        output: const ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(JsonMap json) => _Json(json);

  @override
  Future<Outcome<_Json>> run(_Json input, h.Invocation invocation) async {
    try {
      return Completed(_Json(answer(input.value)));
    } on Failure catch (f) {
      return Failed(f);
    }
  }
}

final class _Capability implements Capability {
  _Capability(this.actions);
  @override
  final List<Action> actions;
}
