import 'dart:io';

import '../store/sources.dart';
import '../store/store_fetch.dart';
import '../store/store_index.dart';

/// `--store-install-npm SPEC --accept-unreviewed`: what the store's
/// interface does on a desktop for the person at it, for a host without one.
/// An npm package nobody reviewed is never installed without the explicit
/// `--accept-unreviewed`; its notices are printed first. A running host
/// loads it when Nipa next starts (restart the service).
Future<int> runHeadlessStoreInstall(Directory root, String spec,
    {required bool accepted}) async {
  if (!accepted) {
    stderr.writeln('An npm package is not reviewed: it runs with this '
        "account's access to files and the network. Install only a package "
        'you trust, and say so with --accept-unreviewed.');
    return 64;
  }
  final store = rikaStore(root);
  try {
    final installed = await store.installNpm(spec);
    final item = installed.item;
    stdout.writeln('Installed ${item.name} ${item.version} as ${item.id} '
        '(${item.kind.name}, not reviewed).');
    for (final notice in item.notices) {
      stdout.writeln('  $notice');
    }
    stdout.writeln('Nipa loads it when she next starts '
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
