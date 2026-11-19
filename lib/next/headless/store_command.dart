import 'dart:io';

import '../store/npm_package.dart';
import '../store/sources.dart';
import '../store/store_fetch.dart';
import '../store/store_index.dart';

/// `--store-install-npm SPEC`: what the store's interface does on a desktop
/// for the person at it, for a host without one. An npm package nobody
/// reviewed is installed only from an interactive terminal, after the
/// person types its name back: Nipa's tools run without a terminal, so she
/// cannot install one for herself this way. (She runs as the same system
/// user; this is a step she cannot take by accident, not a wall.) A running
/// host loads it when Nipa next starts (restart the service).
Future<int> runHeadlessStoreInstall(Directory root, String spec,
    {Stdin? input, IOSink? output}) async {
  final terminal = input ?? stdin;
  final out = output ?? stdout;
  final String name;
  try {
    (name, _) = NpmPackages.parseSpec(spec);
  } on StoreFormatException catch (error) {
    stderr.writeln(error.message);
    return 64;
  }
  if (!terminal.hasTerminal) {
    stderr.writeln('Installing an npm package nobody reviewed needs the '
        'person at this host: run it in an interactive terminal.');
    return 64;
  }
  out.writeln('$name is not reviewed. A plugin runs inside Nipa\'s runtime, '
      'a skill\'s scripts are run by Nipa: either can read and change the '
      'files this account can, reach any network address, and see what is '
      'handed to it. Install only a package you trust.');
  out.write('Type the package name to install it: ');
  if (terminal.readLineSync()?.trim() != name) {
    stderr.writeln('Not installed.');
    return 1;
  }
  final store = rikaStore(root);
  try {
    final installed = await store.installNpm(spec);
    final item = installed.item;
    out.writeln('Installed ${item.name} ${item.version} as ${item.id} '
        '(${item.kind.name}, not reviewed).');
    for (final notice in item.notices.skip(1)) {
      out.writeln('  $notice');
    }
    out.writeln('Nipa loads it when she next starts '
        '(systemctl --user restart nipaplay-headless).');
    return 0;
  } on StoreFormatException catch (error) {
    stderr.writeln(error.message);
    return 65;
  } on StoreFetchException catch (error) {
    stderr.writeln(error.message);
    return 69;
  } finally {
    await store.close();
  }
}
