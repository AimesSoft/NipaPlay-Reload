import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/harness_repository.dart';

void main() {
  group('automatic seed merge', () {
    late Directory root, source, repository;
    Map<String, List<int>> seed(String instructions, {bool tool = false}) => {
          'AGENTS.md': utf8.encode('$instructions\n'),
          'memory/note.md': utf8.encode('original memory\n'),
          if (tool) 'official-tool': utf8.encode('new tool\n'),
        };
    Future<String> git(List<String> args) async {
      final result =
          await Process.run('git', args, workingDirectory: repository.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    Future<void> commit() async {
      await git(['add', 'AGENTS.md']);
      await git([
        '-c',
        'user.name=User',
        '-c',
        'user.email=user@localhost',
        '-c',
        'commit.gpgSign=false',
        'commit',
        '-m',
        'Personal instructions'
      ]);
    }

    Future<void> noConflictArtifacts() async {
      expect(await git(['ls-files', '--unmerged']), isEmpty);
      expect(await File('${repository.path}/.git/MERGE_HEAD').exists(), false);
    }

    setUp(() async {
      root = await Directory.systemTemp.createTemp('harness-automatic-');
      source = Directory('${root.path}/seed');
      repository = Directory('${root.path}/harness');
      await maintainHarnessSeed(source, seed('original'));
      await createHarnessRepository(repository, seed('original'),
          upstream: source);
    });
    tearDown(() => root.delete(recursive: true));

    test('fast-forward preserves staged, unstaged and untracked personal work',
        () async {
      await File('${repository.path}/memory/note.md')
          .writeAsString('staged memory\n');
      await git(['add', 'memory/note.md']);
      await File('${repository.path}/memory/note.md')
          .writeAsString('latest memory\n');
      await File('${repository.path}/personal-tool').writeAsString('mine');
      final staged = await git(['diff', '--cached', '--binary']);
      final unstaged = await git(['diff', '--binary']);
      await maintainHarnessSeed(source, seed('updated', tool: true));
      final result = await updateHarnessRepository(repository, source);
      expect(result['state'], 'updated');
      expect(await File('${repository.path}/AGENTS.md').readAsString(),
          'updated\n');
      expect(await File('${repository.path}/official-tool').exists(), true);
      expect(await File('${repository.path}/personal-tool').readAsString(),
          'mine');
      expect(await git(['diff', '--cached', '--binary']), staged);
      expect(await git(['diff', '--binary']), unstaged);
      expect((await harnessSeedStatus(repository, source))['merged'], true);
      final head = await git(['rev-parse', 'HEAD']);
      expect((await updateHarnessRepository(repository, source))['state'],
          'current');
      expect(await git(['rev-parse', 'HEAD']), head);
      await noConflictArtifacts();
    });

    test('disjoint committed customization keeps both parents and dirty memory',
        () async {
      await File('${repository.path}/AGENTS.md')
          .writeAsString('personal instructions\n');
      await commit();
      final personal = await git(['rev-parse', 'HEAD']);
      await File('${repository.path}/memory/note.md')
          .writeAsString('my pending memory');
      await maintainHarnessSeed(source, seed('original', tool: true));
      final result = await updateHarnessRepository(repository, source);
      expect(result['state'], 'updated');
      expect(await git(['rev-parse', 'HEAD^1']), personal);
      expect(await git(['rev-parse', 'HEAD^2']), result['seedHead']);
      expect(await File('${repository.path}/AGENTS.md').readAsString(),
          'personal instructions\n');
      expect(await File('${repository.path}/memory/note.md').readAsString(),
          'my pending memory');
      expect(await File('${repository.path}/official-tool').exists(), true);
      expect((await harnessSeedStatus(repository, source))['merged'], true);
      await noConflictArtifacts();
    });

    test('same-line conflict leaves HEAD, index, staged work and files intact',
        () async {
      await File('${repository.path}/AGENTS.md')
          .writeAsString('personal instructions\n');
      await commit();
      await File('${repository.path}/memory/note.md')
          .writeAsString('pending memory');
      await git(['add', 'memory/note.md']);
      await File('${repository.path}/personal-tool').writeAsString('mine');
      final head = await git(['rev-parse', 'HEAD']);
      final index = await File('${repository.path}/.git/index').readAsBytes();
      final status = await git(['status', '--porcelain']);
      await maintainHarnessSeed(source, seed('official instructions'));
      final result = await updateHarnessRepository(repository, source);
      expect(result['state'], 'conflict');
      expect(result['paths'], contains('AGENTS.md'));
      expect(await git(['rev-parse', 'HEAD']), head);
      expect(await File('${repository.path}/.git/index').readAsBytes(), index);
      expect(await git(['status', '--porcelain']), status);
      expect(await File('${repository.path}/AGENTS.md').readAsString(),
          'personal instructions\n');
      expect(await File('${repository.path}/memory/note.md').readAsString(),
          'pending memory');
      expect(await File('${repository.path}/personal-tool').readAsString(),
          'mine');
      expect((await harnessSeedStatus(repository, source))['merged'], false);
      await noConflictArtifacts();
    });

    for (final mode in ['unstaged', 'staged', 'untracked']) {
      test('overlapping $mode work refuses checkout without changing user work',
          () async {
        final path = mode == 'untracked' ? 'official-tool' : 'AGENTS.md';
        await File('${repository.path}/$path')
            .writeAsString('my pending content');
        if (mode == 'staged') await git(['add', path]);
        final head = await git(['rev-parse', 'HEAD']);
        final status = await git(['status', '--porcelain']);
        final staged = await git(['diff', '--cached', '--binary']);
        final unstaged = await git(['diff', '--binary']);
        await maintainHarnessSeed(source, seed('official update', tool: true));
        expect((await updateHarnessRepository(repository, source))['state'],
            'local_changes');
        expect(await git(['rev-parse', 'HEAD']), head);
        expect(await git(['status', '--porcelain']), status);
        expect(await git(['diff', '--cached', '--binary']), staged);
        expect(await git(['diff', '--binary']), unstaged);
        expect(await File('${repository.path}/$path').readAsString(),
            'my pending content');
        await noConflictArtifacts();
      });
    }

    test('detached HEAD and in-progress operations are skipped', () async {
      final head = await git(['rev-parse', 'HEAD']);
      await maintainHarnessSeed(source, seed('new'));
      await git(['checkout', '--detach']);
      expect((await updateHarnessRepository(repository, source))['state'],
          'detached_head');
      await git(['checkout', 'main']);
      await File('${repository.path}/.git/MERGE_HEAD').writeAsString('$head\n');
      expect((await updateHarnessRepository(repository, source))['state'],
          'in_progress');
      expect(await git(['rev-parse', 'HEAD']), head);
      expect(await File('${repository.path}/AGENTS.md').readAsString(),
          'original\n');
    });

    test('different remote and unrelated history never get rewritten',
        () async {
      final other = Directory('${root.path}/other');
      await maintainHarnessSeed(other, seed('unrelated'));
      await git(['remote', 'set-url', 'nipaplay', other.path]);
      expect((await updateHarnessRepository(repository, source))['state'],
          'different_remote');
      expect(await git(['remote', 'get-url', 'nipaplay']), other.path);
      await git(['remote', 'set-url', 'nipaplay', source.path]);
      await git(['checkout', '--orphan', 'personal']);
      await File('${repository.path}/AGENTS.md').writeAsString('unrelated');
      await commit();
      final head = await git(['rev-parse', 'HEAD']);
      expect((await updateHarnessRepository(repository, source))['state'],
          'unrelated_history');
      expect(await git(['rev-parse', 'HEAD']), head);
      await noConflictArtifacts();
    });
  });
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

  test('seed history preserves ancestry and fetch never changes harness files',
      () async {
    final root = await Directory.systemTemp.createTemp('harness-upstream-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}/seed');
    final repository = Directory('${root.path}/harness');
    final first = {
      'nipa': utf8.encode('first'),
      'obsolete.txt': utf8.encode('old')
    };
    await maintainHarnessSeed(source, first);
    await createHarnessRepository(repository, first, upstream: source);
    expect((await harnessSeedStatus(repository, source))['state'], 'current');
    Future<String> git(Directory dir, List<String> args) async {
      final result = await Process.run('git', args, workingDirectory: dir.path);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      return (result.stdout as String).trim();
    }

    final initial = await git(source, ['rev-parse', 'HEAD']);
    await maintainHarnessSeed(source, first);
    expect(await git(source, ['rev-parse', 'HEAD']), initial);
    final custom = File('${repository.path}/nipa');
    await custom.writeAsString('agent change');
    final before = await custom.stat();
    final upgraded = {
      'nipa': utf8.encode('second'),
      'added.txt': utf8.encode('new')
    };
    await maintainHarnessSeed(source, upgraded);
    final lag = await harnessSeedStatus(repository, source);
    expect(lag['state'], 'behind');
    expect(lag['trackingBehindSeed'], true);
    // ignore: avoid_print
    print(
        'X8 status before fetch: seed=${lag['path']}; state=${lag['state']}; trackingBehindSeed=${lag['trackingBehindSeed']}');
    expect(
        await createHarnessRepository(repository, upgraded, upstream: source),
        false);
    expect(await git(source, ['rev-list', '--count', 'HEAD']), '2');
    await git(repository, ['fetch', 'nipaplay']);
    final current = await harnessSeedStatus(repository, source);
    expect(current['state'], 'current');
    expect(current['trackingBehindSeed'], false);
    // ignore: avoid_print
    print(
        'X8 status after fetch: state=${current['state']}; trackingBehindSeed=${current['trackingBehindSeed']}; custom file untouched=true');
    expect(await git(repository, ['merge-base', 'HEAD', 'nipaplay/main']),
        initial);
    expect(await git(repository, ['show', 'nipaplay/main:nipa']), 'second');
    expect(await git(repository, ['show', 'nipaplay/main:added.txt']), 'new');
    expect(await File('${source.path}/obsolete.txt').exists(), false);
    expect(await custom.readAsString(), 'agent change');
    expect((await custom.stat()).modified, before.modified);
  });

  test(
      'seed status distinguishes missing remote and unfetched history without writes',
      () async {
    final root = await Directory.systemTemp.createTemp('harness-status-');
    addTearDown(() => root.delete(recursive: true));
    final source = Directory('${root.path}/seed');
    final repository = Directory('${root.path}/harness');
    final seed = {'nipa': utf8.encode('fixture')};
    await maintainHarnessSeed(source, seed);
    await createHarnessRepository(repository, seed);
    expect((await harnessSeedStatus(repository, source))['state'],
        'missing_remote');
    final result = await Process.run(
        'git', ['remote', 'add', 'nipaplay', source.path],
        workingDirectory: repository.path);
    expect(result.exitCode, 0);
    expect(
        (await harnessSeedStatus(repository, source))['state'], 'not_fetched');
    expect(
        (await Process.run(
                'git', ['show-ref', '--verify', 'refs/remotes/nipaplay/main'],
                workingDirectory: repository.path))
            .exitCode,
        isNot(0));
    final other = Directory('${root.path}/other');
    await maintainHarnessSeed(other, seed);
    expect(
        (await Process.run('git', ['remote', 'set-url', 'nipaplay', other.path],
                workingDirectory: repository.path))
            .exitCode,
        0);
    final different = await harnessSeedStatus(repository, source);
    expect(different['state'], 'different_remote');
    expect(different['trackingBehindSeed'], null);
    // ignore: avoid_print
    print(
        'X8 status discovery: missing_remote -> not_fetched; no refs fetched=true');
  });
}
