import 'dart:io';

import 'package:path/path.dart' as p;

/// HOME is the account home in the non-sandboxed Next host.
String get harnessHome => Platform.isWindows
    ? Platform.environment['USERPROFILE']!
    : Platform.environment['HOME']!;
String get defaultHarnessPath => p.join(harnessHome, 'nipaplay-harness');
File get defaultEndpointFile => Platform.isWindows
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
