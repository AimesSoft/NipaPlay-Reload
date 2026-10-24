import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/memory/service.dart';
import 'package:nipaplay/next/ui/conversation/chat_context.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/repository_location.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _Location implements RepositoryLocation {
  _Location(this.path);
  @override
  final String path;
  @override
  Future<void> get ready async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root, repo;
  late HarnessMemory memory;
  late Database db;
  final reports = <JsonMap>[];
  Future<ProcessResult> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: repo.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('x49-constraints-');
    repo = await Directory('${root.path}/harness').create();
    await Directory('${repo.path}/memory').create();
    await File('${repo.path}/memory/preferences.md')
        .writeAsString('- 2026-10-13，用户：偏爱短篇。\n- 2026-10-13，用户：喜欢温暖结局。\n');
    await File('${repo.path}/memory/MEMORY.md').writeAsString('# 索引\n');
    await git(['init', '--template=', '--initial-branch=main']);
    await git(['add', '.']);
    await git([
      '-c',
      'user.name=fixture',
      '-c',
      'user.email=fixture@localhost',
      '-c',
      'commit.gpgSign=false',
      'commit',
      '-m',
      'fixture'
    ]);
    db = await openNextDatabase(Directory('${root.path}/db'),
        factory: databaseFactoryFfi);
    reports.clear();
    memory = HarnessMemory(_Location(repo.path), SettingsRegistry(db, []),
        (data, invocation) async {
      reports.add({...data, 'origin': invocation.origin});
      return data;
    });
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('user deletion commits only memory and preserves unrelated staged work',
      () async {
    await File('${repo.path}/unrelated').writeAsString('pending');
    await git(['add', 'unrelated']);
    final read = await memory.read('preferences.md');
    await memory.delete('preferences.md', read['revision'] as String,
        Invocation(origin: 'gui'));
    expect(await File('${repo.path}/memory/preferences.md').exists(), false);
    expect(
        (await git(['diff', '--cached', '--name-only'])).stdout, 'unrelated\n');
    expect((await git(['log', '-1', '--format=%an <%ae>'])).stdout,
        'NipaPlay User <user@localhost>\n');
    expect(reports.single['origin'], 'gui');
    expect((reports.single['facts'] as Map)['operation'], 'delete');
  });

  test(
      'stale edit cannot replace newer memory; line deletion preserves other preferences',
      () async {
    final old = await memory.read('preferences.md');
    await memory.rememberThread('a');
    await memory.rememberThread('b');
    await memory.edit('preferences.md', '- 2026-10-13，用户：喜欢温暖结局。\n',
        old['revision'] as String, Invocation(origin: 'gui'));
    // Selecting an already loaded Codex thread must not discard pending changes.
    await memory.rememberThread('b');
    await expectLater(
        memory.edit('preferences.md', 'stale', old['revision'] as String,
            Invocation(origin: 'gui')),
        throwsA(isA<Failure>()));
    expect(await memory.changesFor('a'), contains('preferences.md'));
    expect(await memory.changesFor('a'), isNull);
    expect(await memory.changesFor('b'), contains('preferences.md'));
    expect((await memory.read('preferences.md'))['content'], contains('温暖结局'));
  });

  test('her own edits are no news next turn; the user’s, made meanwhile, are',
      () async {
    final file = File('${repo.path}/memory/preferences.md');
    await memory.rememberThread('a');
    var since = DateTime.now();
    // Nipa edits the file herself during a turn; it ends.
    await file.writeAsString('${await file.readAsString()}- 她自己记下的。\n');
    await memory.settle('a', since);
    expect(await memory.changesFor('a'), isNull);
    // During the next turn the user edits it from the interface.
    since = DateTime.now();
    final read = await memory.read('preferences.md');
    await memory.edit('preferences.md', '- 用户改过。\n', read['revision'] as String,
        Invocation(origin: 'gui'));
    await memory.settle('a', since);
    final notice = await memory.changesFor('a');
    expect(notice, contains('preferences.md'));
    // The conversation shows what was said, not the notice after it.
    expect(ChatContext.strip('怎么样了？\n\n$notice'), '怎么样了？');
  });

  test('direct file edits are observed without a memory API write', () async {
    await memory.rememberThread('a');
    final file = File('${repo.path}/memory/preferences.md');
    await file.writeAsString('${await file.readAsString()}- 直接改盘。\n');
    expect(await memory.changesFor('a'), contains('preferences.md'));
    expect(await memory.changesFor('a'), isNull);
  });

  test('a staged target stays intact when the user tries to delete it',
      () async {
    final file = File('${repo.path}/memory/preferences.md');
    await file.writeAsString('- 新偏好\n');
    await git(['add', 'memory/preferences.md']);
    final old = await memory.read('preferences.md');
    await expectLater(
        memory.delete('preferences.md', old['revision'] as String,
            Invocation(origin: 'gui')),
        throwsA(isA<Failure>()
            .having((failure) => failure.code, 'code', FailureCode.conflict)));
    expect(await file.readAsString(), '- 新偏好\n');
    expect((await git(['diff', '--cached', '--name-only'])).stdout,
        'memory/preferences.md\n');
    expect(reports, isEmpty);
  });

  test(
      'forgetting an untracked note records deletion without committing staged work',
      () async {
    await File('${repo.path}/memory/note.md').writeAsString('临时笔记');
    await File('${repo.path}/unrelated').writeAsString('pending');
    await git(['add', 'unrelated']);
    final old = await memory.read('note.md');
    await memory.delete(
        'note.md', old['revision'] as String, Invocation(origin: 'gui'));
    expect(
        (await git(['diff', '--cached', '--name-only'])).stdout, 'unrelated\n');
    expect(await File('${repo.path}/memory/note.md').exists(), false);
    expect(reports, hasLength(1));
    await File('${repo.path}/memory/note.md').writeAsString('Agent 临时笔记');
    final agentRead = await memory.read('note.md');
    await memory.delete('note.md', agentRead['revision'] as String,
        Invocation(origin: 'harness_cli'));
    expect((await git(['log', '-1', '--format=%an <%ae>'])).stdout,
        'Nipa <agent@localhost>\n');
    expect(
        (await git(['diff', '--cached', '--name-only'])).stdout, 'unrelated\n');
  });

  test('symlinks and traversal never expose or delete files outside memory',
      () async {
    await File('${repo.path}/memory/环境笔记.md').writeAsString('中文文件名');
    expect((await memory.read('环境笔记.md'))['content'], '中文文件名');
    final outside = File('${root.path}/outside.md');
    await outside.writeAsString('untouched');
    await Link('${repo.path}/memory/linked.md').create(outside.path);
    for (final path in ['../outside.md', '/outside.md', 'linked.md']) {
      await expectLater(memory.read(path), throwsA(isA<Failure>()));
    }
    expect(await outside.readAsString(), 'untouched');
    expect((await memory.list()).map((r) => r['path']),
        isNot(contains('linked.md')));
  });

  test(
      'resident UTF-8 cap and recognizable secrets reject writes without git changes',
      () async {
    final before = await memory.read('preferences.md');
    for (final content in [
      List.filled(3000, '字').join(),
      'cookie=synthetic',
      'password=synthetic',
      'https://example.test/rss?passkey=synthetic',
      '-----BEGIN PRIVATE KEY-----\nsynthetic\n-----END PRIVATE KEY-----'
    ]) {
      await expectLater(
          memory.edit('preferences.md', content, before['revision'] as String,
              Invocation(origin: 'gui')),
          throwsA(isA<Failure>()));
    }
    expect(
        (await memory.read('preferences.md'))['revision'], before['revision']);
    expect((await git(['status', '--porcelain'])).stdout, isEmpty);
  });

  test(
      'oversize direct file edits disclose exact omitted bytes, never exceed resident cap',
      () async {
    await File('${repo.path}/memory/preferences.md')
        .writeAsString(List.filled(3000, '字').join());
    final context = await memory.context(null);
    expect(context['preferences'], contains('尾部 810 UTF-8 字节未注入'));
    expect(context['preferences'], isNot(contains('\uFFFD')));
  });

  test(
      'settings preferences retain current values and reasons, omit defaults and migrations',
      () async {
    final values = <String, Object?>{
      'user': false,
      'migration': false,
      'default': false
    };
    final registry = SettingsRegistry(db, [
      for (final key in values.keys)
        SettingEntry(
          key: 'fixture.$key',
          title: key,
          description: key,
          schema: const BooleanSchema(),
          defaultValue: false,
          scope: 'user',
          storageKey: key,
          reader: key,
          writer: key,
          decodeStorage: (value) => value ?? false,
          read: () async => values[key],
          write: (value) async {
            values[key] = value;
          },
        ),
    ]);
    await registry.set('fixture.user', true, Invocation(origin: 'gui'),
        reason: '用户的原话');
    await registry.set(
        'fixture.migration', true, Invocation(origin: 'migration'));
    final prefs = await registry.preferences();
    expect(prefs, hasLength(1));
    expect(prefs.single['key'], 'fixture.user');
    expect(prefs.single['value'], true);
    expect(prefs.single['reason'], '用户的原话');
    expect(prefs.single['changedBy'], 'user');
  });
}
