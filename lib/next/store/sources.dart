import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'rika_store.dart';
import 'store_fetch.dart';

/// Where the official list is: the repository's `main` branch, then a CDN
/// copy of it for where GitHub is slow or blocked. Every file the list names
/// is held to its SHA-256, so the copy can only be late, never different.
const officialStoreSources = [
  'https://raw.githubusercontent.com/AimesSoft/rika_plugins/main/',
  'https://cdn.jsdelivr.net/gh/AimesSoft/rika_plugins@main/',
];

/// npm's registry, then npmmirror's copy of it.
const defaultNpmRegistries = [
  'https://registry.npmjs.org',
  'https://registry.npmmirror.com',
];

/// The list sources: `NIPAPLAY_STORE_INDEX`, when set, names a checkout of
/// the store repository (a folder, or an address) to use instead, for
/// developing items before they are published.
List<Uri> storeListSources([Map<String, String>? environment]) {
  final override = (environment ?? Platform.environment)['NIPAPLAY_STORE_INDEX'];
  if (override != null && override.trim().isNotEmpty) {
    final value = override.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return [Uri.parse(value.endsWith('/') ? value : '$value/')];
    }
    final folder = p.basename(value) == 'index.json' ? p.dirname(value) : value;
    return [Uri.directory(p.absolute(folder))];
  }
  return [for (final source in officialStoreSources) Uri.parse(source)];
}

/// The store of the Next data root [root]. [dshRuntime] is where NipaPlay
/// keeps its downloaded DSH runtime (`<root>/dsh-runtime` by default): its
/// registry mirror is the store's too, and its packages are what a plugin
/// from npm may depend on.
RikaStore rikaStore(Directory root, {Directory? dshRuntime}) {
  final runtime = dshRuntime ?? Directory(p.join(root.path, 'dsh-runtime'));
  return RikaStore(
    root: Directory(p.join(root.path, 'store')),
    fetch: StoreFetch(HttpClient.new),
    listSources: storeListSources,
    registries: () async {
      final settings = File(p.join(runtime.path, 'settings.json'));
      if (await settings.exists()) {
        try {
          final mirror =
              (jsonDecode(await settings.readAsString()) as Map)['registryMirror'];
          if (mirror is String && mirror.isNotEmpty) return [mirror];
        } on FormatException {
          // Unreadable settings: the defaults.
        }
      }
      return defaultNpmRegistries;
    },
    provided: () => runtimePackages(runtime),
  );
}

/// The packages in the newest installed runtime under [runtime]
/// (`dsh-*/lib/node_modules`), null when none is installed.
Future<Set<String>?> runtimePackages(Directory runtime) async {
  if (!await runtime.exists()) return null;
  final installs = [
    await for (final entity in runtime.list(followLinks: false))
      if (entity is Directory &&
          p.basename(entity.path).startsWith('dsh-') &&
          await File(p.join(entity.path, 'installed.json')).exists())
        entity
  ]..sort((a, b) => a.path.compareTo(b.path));
  if (installs.isEmpty) return null;
  final modules = Directory(p.join(installs.last.path, 'lib', 'node_modules'));
  return nodeModulesPackages(modules);
}

/// The package names directly under a `node_modules` folder.
Future<Set<String>> nodeModulesPackages(Directory modules) async {
  final names = <String>{};
  if (!await modules.exists()) return names;
  await for (final entity in modules.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    if (name.startsWith('@') && entity is Directory) {
      await for (final scoped in entity.list(followLinks: false)) {
        names.add('$name/${p.basename(scoped.path)}');
      }
    } else {
      names.add(name);
    }
  }
  return names;
}
