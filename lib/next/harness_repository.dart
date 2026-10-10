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

/// Staging prevents a failed copy from becoming an apparently existing harness.
/// Existing paths (including symlinks) belong entirely to the user.
Future<bool> createHarnessRepository(
    Directory directory, Map<String, List<int>> seed) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return false;
  }
  await directory.parent.create(recursive: true);
  final staging = await directory.parent.createTemp('.nipaplay-seed-');
  try {
    for (final entry in seed.entries) {
      final file = File(p.join(staging.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    if (!Platform.isWindows) {
      final result =
          await Process.run('chmod', ['755', p.join(staging.path, 'nipa')]);
      if (result.exitCode != 0) {
        throw StateError('Cannot make nipa executable.');
      }
    }
    try {
      Future<void> git(List<String> args) async {
        final result =
            await Process.run('git', args, workingDirectory: staging.path);
        if (result.exitCode != 0) {
          throw StateError(
              'Harness git ${args.first} failed: ${result.stderr}');
        }
      }

      await git(['init', '--template=']);
      await git(['add', '.']);
      await git([
        '-c',
        'user.name=NipaPlay',
        '-c',
        'user.email=harness@localhost',
        '-c',
        'commit.gpgSign=false',
        '-c',
        'core.hooksPath=${p.join(staging.path, '.git', 'no-hooks')}',
        'commit',
        '-m',
        'Initialize NipaPlay harness'
      ]);
    } on ProcessException catch (error) {
      if (error.errorCode != 2) rethrow; // git is not installed.
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
