import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the headless host finds the files it reads at run time.
///
/// An installed package keeps them in `assets/next/<name>` next to the
/// directory the executable is in (`libexec/` beside `assets/`), or directly
/// beside the executable. A host started from a source checkout (or by a test)
/// has none of those and finds them in the working directory, as before.
String headlessAssetPath(String name,
    {String? executable,
    String? workingDirectory,
    bool Function(String path)? exists}) {
  final found = exists ?? (path) => Directory(path).existsSync();
  final directory = p.dirname(executable ?? Platform.resolvedExecutable);
  final inWorkingDirectory = p.join(
      workingDirectory ?? Directory.current.path, 'assets', 'next', name);
  for (final candidate in [
    p.normalize(p.join(directory, '..', 'assets', 'next', name)),
    p.join(directory, 'assets', 'next', name),
    inWorkingDirectory,
  ]) {
    if (found(candidate)) return candidate;
  }
  return inWorkingDirectory;
}

/// The application version, stamped into the executable by the package build
/// (`-DNIPAPLAY_VERSION=<pubspec version>`); `dev` for a build from a checkout.
const headlessVersion =
    String.fromEnvironment('NIPAPLAY_VERSION', defaultValue: 'dev');

/// What this host reports as its version on the instance and endpoint.
const headlessAppVersion = '$headlessVersion-headless';

/// Provenance belongs to the compiled binary, not the surrounding package.
const headlessBuildFacts = <String, Object?>{
  'appVersion': headlessVersion,
  'sourceCommit': String.fromEnvironment('NIPAPLAY_SOURCE_COMMIT'),
  'sourceDirty':
      bool.fromEnvironment('NIPAPLAY_SOURCE_DIRTY', defaultValue: true),
};
