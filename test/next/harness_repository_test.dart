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
