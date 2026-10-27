import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'platform/lab_profile.dart';

import 'package:path/path.dart' as p;

/// HOME is the account home in the non-sandboxed Next host.
///
/// An iOS process may have no HOME in its environment: its application
/// container (the parent of its temporary directory) is the home there.
String get harnessHome => Platform.isWindows
    ? Platform.environment['USERPROFILE']!
    : Platform.environment['HOME'] ?? Directory.systemTemp.parent.path;
String get defaultHarnessPath => LabProfile.active
    ? LabProfile.location('harness')
    : p.join(harnessHome, 'nipaplay-harness');
File get defaultEndpointFile => LabProfile.active
    ? File(LabProfile.location('endpoint.json'))
    : Platform.isWindows
        ? File(p.join(
            Platform.environment['APPDATA']!, 'NipaPlay', 'endpoint.json'))
        : File(p.join(harnessHome, '.config', 'nipaplay', 'endpoint.json'));

String expandHarnessPath(String value) {
  final expanded = value == '~'
      ? harnessHome
      : value.startsWith('~/') || value.startsWith('~\\')
          ? p.join(harnessHome, value.substring(2))
          : value;
  if (!p.isAbsolute(expanded)) {
    throw ArgumentError('Harness path must be absolute.');
  }
  return p.normalize(expanded);
}

/// Reads the live seed and fetched remote tip without fetching or changing refs.
Future<Map<String, Object?>> harnessSeedStatus(
    Directory repository, Directory seed) async {
  Future<String?> read(Directory dir, List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }

  try {
    final head = await read(seed, ['rev-parse', '--verify', 'refs/heads/main']);
    final remote = await read(repository, ['remote', 'get-url', 'nipaplay']);
    final tracking = await read(
        repository, ['rev-parse', '--verify', 'refs/remotes/nipaplay/main']);
    final repositoryHead =
        await read(repository, ['rev-parse', '--verify', 'HEAD']);
    bool? remoteMatchesSeed;
    if (remote != null) {
      final uri = Uri.tryParse(remote);
      final remotePath = p.isAbsolute(remote)
          ? remote
          : uri?.scheme == 'file'
              ? uri!.toFilePath()
              : uri?.hasScheme == false
                  ? p.join(repository.path, remote)
                  : null;
      remoteMatchesSeed = remotePath != null &&
          await Directory(remotePath).exists() &&
          p.equals(await Directory(remotePath).resolveSymbolicLinks(),
              await seed.resolveSymbolicLinks());
    }
    String state;
    bool? behind;
    if (head == null) {
      state = 'seed_unversioned';
    } else if (remote == null) {
      state = 'missing_remote';
    } else if (remoteMatchesSeed != true) {
      state = 'different_remote';
    } else if (tracking == null) {
      state = 'not_fetched';
    } else if (head == tracking) {
      state = 'current';
      behind = false;
    } else {
      final ancestry = await Process.run(
          'git', ['merge-base', '--is-ancestor', tracking, head],
          workingDirectory: seed.path);
      if (ancestry.exitCode == 0) {
        state = 'behind';
        behind = true;
      } else {
        state = ancestry.exitCode == 1 ? 'diverged' : 'unrelated_or_unknown';
      }
    }
    bool? merged;
    if (head != null && repositoryHead != null && remoteMatchesSeed == true) {
      final ancestry = await Process.run(
          'git', ['merge-base', '--is-ancestor', head, repositoryHead],
          workingDirectory: repository.path);
      if (ancestry.exitCode == 0 || ancestry.exitCode == 1) {
        merged = ancestry.exitCode == 0;
      }
    }
    return {
      'path': seed.absolute.path,
      'head': head,
      'remote': remote,
      'remoteMatchesSeed': remoteMatchesSeed,
      'trackingHead': tracking,
      'trackingBehindSeed': behind,
      'repositoryHead': repositoryHead,
      'merged': merged,
      'state': state
    };
  } on ProcessException catch (error) {
    if (error.errorCode != 2) rethrow;
    return {
      'path': seed.absolute.path,
      'state': 'git_unavailable',
      'trackingBehindSeed': null
    };
  }
}

/// Preview in Git's object database, then apply only a fast-forward. A failed
/// preview never touches HEAD, the index or user files; Git's fast-forward
/// checkout refuses to overwrite overlapping staged/unstaged/untracked work.
/// No stash, reset, conflict checkout or abort is used in the user's repository.
Future<Map<String, Object?>> updateHarnessRepository(
    Directory repository, Directory seed) async {
  final receipt = <String, Object?>{
    'repository': repository.absolute.path,
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Map<String, Object?> finish(String state, String reason) =>
      {...receipt, 'state': state, 'reason': reason};
  // An empty, private directory disables user hooks without changing config.
  Directory? hooks;
  Future<ProcessResult> git(List<String> args) => Process.run(
      'git',
      [
        '-c',
        'core.hooksPath=${hooks!.path}',
        '-c',
        'commit.gpgSign=false',
        '-c',
        'core.fsmonitor=false',
        '-c',
        'submodule.recurse=false',
        ...args
      ],
      workingDirectory: repository.path,
      environment: {'GIT_TERMINAL_PROMPT': '0', 'GIT_MERGE_AUTOEDIT': 'no'});
  String output(ProcessResult result) => (result.stdout as String).trim();
  try {
    final status = await harnessSeedStatus(repository, seed);
    if (status['remoteMatchesSeed'] != true || status['head'] == null) {
      return finish(
          status['state'] as String, '仅自动更新指向本机官方种子的 nipaplay 远端；未修改仓库配置。');
    }
    hooks = await Directory.systemTemp.createTemp('nipa-update-hooks-');
    final branch = await git(['symbolic-ref', '-q', 'HEAD']);
    if (branch.exitCode != 0) {
      return finish('detached_head', '当前没有检出分支，保留现状。');
    }
    for (final name in const [
      'MERGE_HEAD',
      'CHERRY_PICK_HEAD',
      'REVERT_HEAD',
      'rebase-merge',
      'rebase-apply',
      'sequencer',
      'BISECT_LOG'
    ]) {
      final path = await git(['rev-parse', '--git-path', name]);
      if (path.exitCode != 0) return finish('failed', '无法检查仓库状态。');
      if (await FileSystemEntity.type(p.join(repository.path, output(path))) !=
          FileSystemEntityType.notFound) {
        return finish('in_progress', '仓库有尚未完成的 Git 操作，保留现状。');
      }
    }
    final unmerged = await git(['ls-files', '--unmerged', '-z']);
    if (unmerged.exitCode != 0 || output(unmerged).isNotEmpty) {
      return finish('in_progress', '索引存在未解决的合并项，保留现状。');
    }
    // Use the verified local path, rather than a remote fetch refspec/config
    // which may have been customized. Never contact a network remote here.
    final fetch = await git([
      '-c',
      'protocol.file.allow=always',
      'fetch',
      '--no-tags',
      '--no-recurse-submodules',
      '--no-write-fetch-head',
      '--no-auto-maintenance',
      seed.absolute.path,
      'refs/heads/main:refs/remotes/nipaplay/main'
    ]);
    if (fetch.exitCode != 0) return finish('fetch_failed', '无法抓取本机官方种子。');
    final head = await git(['rev-parse', '--verify', 'HEAD']);
    final upstream =
        await git(['rev-parse', '--verify', 'refs/remotes/nipaplay/main']);
    if (head.exitCode != 0 || upstream.exitCode != 0) {
      return finish('failed', '无法读取仓库版本。');
    }
    final before = output(head), incoming = output(upstream);
    receipt.addAll({'previousHead': before, 'seedHead': incoming});
    final included =
        await git(['merge-base', '--is-ancestor', incoming, before]);
    if (included.exitCode == 0) {
      return {...finish('current', '官方种子已合并。'), 'head': before};
    }
    final base = await git(['merge-base', before, incoming]);
    if (base.exitCode != 0) {
      return finish('unrelated_history', '仓库与官方种子没有共同历史，保留现状。');
    }
    final fastForward =
        await git(['merge-base', '--is-ancestor', before, incoming]);
    var target = incoming;
    if (fastForward.exitCode != 0) {
      final preview = await git([
        'merge-tree',
        '--write-tree',
        '--no-messages',
        '--name-only',
        '-z',
        before,
        incoming
      ]);
      if (preview.exitCode == 1) {
        final paths = (preview.stdout as String)
            .split('\x00')
            .skip(1)
            .where((path) => path.isNotEmpty)
            .toList();
        return {
          ...finish('conflict', '官方更新与本地提交有冲突；文件和索引保持原样，请先处理后重启 Next。'),
          'paths': paths
        };
      }
      if (preview.exitCode != 0) {
        return finish('preview_unavailable',
            '无法安全预览合并，请检查 Git 是否支持 merge-tree --write-tree（2.38 或更新）。');
      }
      final tree = (preview.stdout as String).split('\x00').first.trim();
      final commit = await git([
        '-c',
        'user.name=NipaPlay',
        '-c',
        'user.email=harness@localhost',
        'commit-tree',
        tree,
        '-p',
        before,
        '-p',
        incoming,
        '-m',
        'Merge NipaPlay harness seed'
      ]);
      if (commit.exitCode != 0) return finish('failed', '无法创建官方更新的合并提交。');
      target = output(commit);
    }
    final changes = await git(['diff', '--name-only', '-z', before, target]);
    final latest = await git(['rev-parse', '--verify', 'HEAD']);
    final latestBranch = await git(['symbolic-ref', '-q', 'HEAD']);
    if (output(latest) != before || output(latestBranch) != output(branch)) {
      return finish('repository_changed', '检查期间仓库版本发生变化，稍后重试。');
    }
    final apply =
        await _applySeed(repository, hooks, output(branch), before, target);
    receipt.addAll(apply);
    if (apply['state'] != 'updated') {
      return finish(apply['state'] as String, apply['reason'] as String);
    }
    final appliedHead = await git(['rev-parse', '--verify', 'HEAD']);
    final appliedBranch = await git(['symbolic-ref', '-q', 'HEAD']);
    receipt.addAll({
      'branch': output(branch),
      'observedBranch': output(appliedBranch),
      'observedHead': output(appliedHead),
      'targetHead': target,
    });
    if (appliedHead.exitCode != 0 ||
        appliedBranch.exitCode != 0 ||
        output(appliedHead) != target ||
        output(appliedBranch) != output(branch)) {
      return finish('repository_changed',
          '应用更新期间仓库发生并发变化；请核查 observedBranch/observedHead，未自动回退个人修改。');
    }
    return {
      ...finish('updated', '已自动合并官方种子，保留本地历史与个人文件。'),
      'head': target,
      'paths': (changes.stdout as String)
          .split('\x00')
          .where((s) => s.isNotEmpty)
          .toList()
    };
  } on ProcessException {
    return finish('git_unavailable', 'Git 不可用，尚未更新 harness。');
  } on FileSystemException {
    return finish('failed', '无法访问更新所需的文件，保留现状。');
  } on ArgumentError {
    return finish('failed', '无法解析仓库配置，保留现状。');
  } on FormatException {
    return finish('failed', '无法解析仓库配置，保留现状。');
  } finally {
    if (hooks != null) {
      try {
        await hooks.delete(recursive: true);
      } on FileSystemException {/* best effort */}
    }
  }
}

/// Git's prepared HEAD update locks both HEAD and its current branch tip.
/// The real index.lock excludes checkout/commit in other processes while an
/// alternate index preserves unrelated staged work. read-tree's two-tree merge
/// refuses overlapping dirty/untracked/ignored content without a reset/stash.
Future<Map<String, Object?>> _applySeed(Directory repository, Directory hooks,
    String branch, String before, String target) async {
  final indexResult = await Process.run(
      'git', ['rev-parse', '--git-path', 'index'],
      workingDirectory: repository.path);
  if (indexResult.exitCode != 0)
    return {'state': 'failed', 'reason': '无法定位 Git 索引。'};
  final index =
      File(p.absolute(repository.path, (indexResult.stdout as String).trim()));
  final lock = File('${index.path}.lock');
  try {
    await lock.create(exclusive: true);
  } on FileSystemException {
    return {'state': 'in_progress', 'reason': 'Git 索引被另一个操作或中断任务锁定，保留现状。'};
  }
  final alternate =
      File('${index.path}.nipa-seed-${DateTime.now().microsecondsSinceEpoch}');
  final recovery = File('${alternate.path}.json');
  Process? transaction;
  StreamIterator<String>? lines;
  var changedWorktree = false, completed = false, ownsIndexLock = true;
  try {
    if (await index.exists()) await index.copy(alternate.path);
    transaction = await Process.start(
        'git',
        [
          '-c',
          'core.hooksPath=${hooks.path}',
          'update-ref',
          '-m',
          'Merge NipaPlay harness seed',
          '--stdin'
        ],
        workingDirectory: repository.path);
    final errors = transaction.stderr.transform(utf8.decoder).join();
    lines = StreamIterator(transaction.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter()));
    Future<bool> reply(String expected) async {
      final cursor = lines!;
      return await cursor.moveNext().timeout(const Duration(seconds: 10)) &&
          cursor.current == expected;
    }

    transaction.stdin.writeln('start');
    transaction.stdin.writeln('update HEAD $target $before');
    transaction.stdin.writeln('prepare');
    await transaction.stdin.flush();
    if (!await reply('start: ok') || !await reply('prepare: ok')) {
      await transaction.stdin.close();
      await transaction.exitCode;
      final error = await errors;
      return {
        'state': error.contains('unknown command')
            ? 'preview_unavailable'
            : 'repository_changed',
        'reason': '无法原子锁定分支与 HEAD，保留现状；请检查 Git 版本和并发操作。'
      };
    }
    // update HEAD prepares locks on both the symbolic HEAD and its referent.
    // Read the branch while those locks are held, including same-tip switches.
    final pinned = await Process.run('git', ['symbolic-ref', '-q', 'HEAD'],
        workingDirectory: repository.path);
    if (pinned.exitCode != 0 || (pinned.stdout as String).trim() != branch) {
      transaction.stdin.writeln('abort');
      await transaction.stdin.close();
      await transaction.exitCode;
      return {'state': 'repository_changed', 'reason': '锁定前检出分支已变化，保留现状。'};
    }
    await recovery.writeAsString(
        jsonEncode({
          'branch': branch,
          'previousHead': before,
          'targetHead': target,
          'index': index.path,
          'preparedIndex': alternate.path
        }),
        flush: true);
    // read-tree may honor repository/global excludes. Protect every untracked
    // path explicitly, including ignored files and directory/type collisions.
    final others = await Process.run('git', ['ls-files', '--others', '-z'],
        workingDirectory: repository.path);
    final diff = await Process.run(
        'git', ['diff', '--name-only', '-z', before, target],
        workingDirectory: repository.path);
    if (others.exitCode != 0 || diff.exitCode != 0)
      throw const FileSystemException('Cannot inspect personal paths');
    final paths =
        (others.stdout as String).split('\x00').where((s) => s.isNotEmpty);
    final changed =
        (diff.stdout as String).split('\x00').where((s) => s.isNotEmpty);
    final blocked = paths
        .where((path) => changed.any((name) =>
            path == name ||
            path.startsWith('$name/') ||
            name.startsWith('$path/')))
        .toList();
    if (blocked.isNotEmpty) {
      transaction.stdin.writeln('abort');
      await transaction.stdin.close();
      await transaction.exitCode;
      return {
        'state': 'local_changes',
        'reason': '官方更新与个人未跟踪或被忽略的路径重叠，保留现状。',
        'blockedPaths': blocked.take(24).toList()
      };
    }
    final checkout = await Process.run(
        'git',
        [
          '-c',
          'core.hooksPath=${hooks.path}',
          '-c',
          'core.fsmonitor=false',
          '-c',
          'submodule.recurse=false',
          'read-tree',
          '-m',
          '-u',
          before,
          target
        ],
        workingDirectory: repository.path,
        environment: {'GIT_INDEX_FILE': alternate.path});
    if (checkout.exitCode != 0) {
      transaction.stdin.writeln('abort');
      await transaction.stdin.close();
      await transaction.exitCode;
      return {'state': 'local_changes', 'reason': '本地未提交或被忽略的个人文件阻止更新，保留现状。'};
    }
    changedWorktree = true;
    await lock.writeAsBytes(await alternate.readAsBytes(), flush: true);
    transaction.stdin.writeln('commit');
    await transaction.stdin.flush();
    if (!await reply('commit: ok'))
      throw const FileSystemException('Git ref commit failed');
    await transaction.stdin.close();
    if (await transaction.exitCode != 0)
      throw const FileSystemException('Git ref transaction failed');
    await lock.rename(index.path);
    ownsIndexLock = false;
    completed = true;
    return {'state': 'updated', 'reason': '官方种子已更新；分支、HEAD 和索引均经过锁定。'};
  } catch (_) {
    return {
      'state': changedWorktree ? 'interrupted' : 'failed',
      'reason': changedWorktree
          ? '更新中断，已保留索引锁和恢复记录；请核查后恢复，不自动覆盖个人文件。'
          : '无法安全准备更新，保留现状。',
      if (changedWorktree) 'recoveryFile': recovery.path
    };
  } finally {
    transaction?.kill();
    await lines?.cancel();
    if (!changedWorktree || completed) {
      for (final file in [alternate, recovery, if (ownsIndexLock) lock]) {
        if (await file.exists()) await file.delete();
      }
    }
  }
}

Future<ProcessResult> _git(Directory directory, List<String> args,
    {Set<int> accepted = const {0}}) async {
  final result =
      await Process.run('git', args, workingDirectory: directory.path);
  if (!accepted.contains(result.exitCode)) {
    throw StateError('Harness git ${args.first} failed: ${result.stderr}');
  }
  return result;
}

Future<void> _writeSeed(
    Directory directory, Map<String, List<int>> seed) async {
  for (final entry in seed.entries) {
    final file = File(p.join(directory.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.value);
  }
  if (!Platform.isWindows && seed.containsKey('nipa')) {
    final result =
        await Process.run('chmod', ['755', p.join(directory.path, 'nipa')]);
    if (result.exitCode != 0) {
      throw StateError('Cannot make nipa executable.');
    }
  }
}

Future<void> _commitSeed(Directory directory) async {
  await _git(directory, [
    '-c',
    'user.name=NipaPlay',
    '-c',
    'user.email=harness@localhost',
    '-c',
    'commit.gpgSign=false',
    '-c',
    'core.hooksPath=${p.join(directory.path, '.git', 'no-hooks')}',
    'commit',
    '--allow-empty',
    '-m',
    'Update NipaPlay harness seed'
  ]);
}

/// Application-owned history. Harnesses clone it so later versions share ancestry.
/// Without git, repository creation can still deliver the seed files.
Future<Directory?> maintainHarnessSeed(
    Directory directory, Map<String, List<int>> seed) async {
  await directory.create(recursive: true);
  try {
    if (!await Directory(p.join(directory.path, '.git')).exists()) {
      await _git(directory, ['init', '--template=', '--initial-branch=main']);
    }
    final tracked = await _git(directory, ['ls-files', '-z']);
    for (final path in (tracked.stdout as String).split('\x00')) {
      if (path.isNotEmpty && !seed.containsKey(path)) {
        await _git(directory, ['rm', '-f', '--', path]);
      }
    }
    await _writeSeed(directory, seed);
    await _git(directory, ['add', '--all', '--force', '.']);
    final diff = await _git(directory, ['diff', '--cached', '--quiet'],
        accepted: {0, 1});
    final head = await _git(directory, ['rev-parse', '--verify', 'HEAD'],
        accepted: {0, 128});
    if (diff.exitCode == 1 || head.exitCode != 0) {
      await _commitSeed(directory);
    }
    return directory;
  } on ProcessException catch (error) {
    if (error.errorCode != 2) rethrow;
    return null;
  }
}

/// Staging prevents a failed copy from becoming an apparently existing harness.
/// Existing paths (including symlinks) belong entirely to the user.
Future<bool> createHarnessRepository(
    Directory directory, Map<String, List<int>> seed,
    {Directory? upstream}) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return false;
  }
  await directory.parent.create(recursive: true);
  final staging = await directory.parent.createTemp('.nipaplay-seed-');
  try {
    if (upstream != null) {
      await _git(staging, [
        'clone',
        '--template=',
        '--origin',
        'nipaplay',
        '--no-local',
        upstream.absolute.path,
        '.'
      ]);
    } else {
      await _writeSeed(staging, seed);
      try {
        await _git(staging, ['init', '--template=', '--initial-branch=main']);
        await _git(staging, ['add', '.']);
        await _commitSeed(staging);
      } on ProcessException catch (error) {
        if (error.errorCode != 2) rethrow; // git is not installed.
      }
    }
    // Another creator may have finished while we staged; never replace it.
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return false;
    }
    await staging.rename(directory.path);
    return true;
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
