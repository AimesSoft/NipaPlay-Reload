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
    ? LabProfile.location('harness') : p.join(harnessHome, 'nipaplay-harness');
File get defaultEndpointFile => LabProfile.active
    ? File(LabProfile.location('endpoint.json')) : Platform.isWindows
    ? File(
        p.join(Platform.environment['APPDATA']!, 'NipaPlay', 'endpoint.json'))
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
    return {
      'path': seed.absolute.path,
      'head': head,
      'remote': remote,
      'remoteMatchesSeed': remoteMatchesSeed,
      'trackingHead': tracking,
      'trackingBehindSeed': behind,
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
