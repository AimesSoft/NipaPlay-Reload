import 'dart:io';

import '../store/sources.dart';
import '../store/store_fetch.dart';
import '../store/store_index.dart';

/// `--store-install-npm SPEC`: what the store's interface does on a desktop
/// for the person at it, for a host without one. Shows the resolved version
/// and notices before accepting a kind and confirmation.
Future<int> runHeadlessStoreInstall(Directory root, String spec,
    {Stdin? input, IOSink? output}) async {
  final terminal = input ?? stdin;
  final out = output ?? stdout;
  if (!terminal.hasTerminal) {
    stderr.writeln('Installing an npm package nobody reviewed needs the '
        'person at this host: run it in an interactive terminal.');
    return 64;
  }
  final store = rikaStore(root);
  try {
    final preview = await store.resolveNpm(spec);
    out.writeln(
        '${preview.name} ${preview.version} (requested: ${preview.requested})');
    for (final notice in preview.notices) {
      out.writeln(notice);
    }
    final choices = <StoreKind>[];
    for (final entry in preview.options.entries) {
      out.writeln('${entry.key.name}: ${entry.value.reason ?? 'installable'}');
      if (entry.value.item != null) choices.add(entry.key);
    }
    if (choices.isEmpty) return 65;
    out.write('Type the package name and kind to install '
        '(${preview.name} ${choices.map((kind) => kind.name).join('/')}): ');
    final answer = terminal.readLineSync()?.trim();
    final kind = choices
        .where((kind) => answer == '${preview.name} ${kind.name}')
        .firstOrNull;
    if (kind == null) {
      stderr.writeln('Not installed.');
      return 1;
    }
    final installed = await store.installNpm(preview.name,
        version: preview.version, kind: kind);
    final item = installed.item;
    out.writeln('Installed ${item.name} ${item.version} as ${item.id} '
        '(${item.kind.name}, not reviewed).');
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
