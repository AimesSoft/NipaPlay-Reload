import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The headless host is plain Dart. Walk the graph it actually loads so a
/// Flutter import cannot return through a helper that happens to be shared
/// with the GUI.
void main() {
  test('the headless import graph never reaches Flutter or dart:ui', () {
    final repository = Directory.current.absolute;
    final config = File('${repository.path}/.dart_tool/package_config.json');
    expect(config.existsSync(), isTrue,
        reason: 'Run flutter pub get before the headless graph guard.');

    final packages = <String, ({Uri root, String packageUri})>{};
    final decoded =
        jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    for (final raw in (decoded['packages'] as List).cast<Map>()) {
      packages[raw['name'] as String] = (
        root: _directory(config.parent.uri.resolve(raw['rootUri'] as String)),
        packageUri: raw['packageUri'] as String? ?? 'lib/',
      );
    }

    final entry =
        File('${repository.path}/bin/nipaplay_headless.dart').absolute.uri;
    final parent = <Uri, Uri>{};
    final visited = <Uri>{};
    final queue = <Uri>[entry];

    bool exists(Uri uri) => File.fromUri(uri).existsSync();

    bool inRepository(Uri uri) {
      final path = File.fromUri(uri).absolute.path;
      return path == repository.path || path.startsWith('${repository.path}/');
    }

    List<String> chainTo(Uri target) {
      final chain = <Uri>[target];
      var current = target;
      while (parent.containsKey(current)) {
        final previous = parent[current]!;
        chain.add(previous);
        current = previous;
      }
      return [for (final uri in chain.reversed) _display(uri, repository)];
    }

    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!visited.add(file)) continue;
      for (final uri in _directives(File.fromUri(file).readAsStringSync())) {
        if (uri == 'dart:ui' || uri.startsWith('package:flutter/')) {
          fail('headless dependency chain reaches $uri:\n'
              '${chainTo(file).join('\n  -> ')}\n  -> $uri');
        }
        final Uri target;
        if (uri.startsWith('dart:')) {
          continue;
        } else if (uri.startsWith('package:')) {
          final slash = uri.indexOf('/');
          expect(slash, greaterThan('package:'.length),
              reason:
                  'Malformed package import $uri in ${_display(file, repository)}');
          final name = uri.substring('package:'.length, slash);
          final package = packages[name];
          if (package == null) {
            fail(
                'Unknown package $name imported by ${_display(file, repository)}');
          }
          target = package.root
              .resolve(package.packageUri)
              .resolve(uri.substring(slash + 1));
          if (!inRepository(target)) continue;
        } else {
          target = file.resolve(uri);
          if (!inRepository(target)) continue;
        }
        if (!exists(target)) {
          fail(
              'Missing import target $target from ${_display(file, repository)}');
        }
        parent.putIfAbsent(target, () => file);
        queue.add(target);
      }
    }

    expect(visited, isNotEmpty);
  });

  test('conditional imports and exports contribute their default branch', () {
    final directives = _directives("""
import 'default.dart'
    if (dart.library.io) 'io.dart';
export 'fallback.dart' if (dart.library.html) 'web.dart';
part 'part.dart';
part of 'parent.dart';
""").toList();

    expect(directives, ['default.dart', 'fallback.dart', 'part.dart']);
  });
}

/// The default URI of each import/export, plus part files. Conditional URIs
/// are selected only on platforms that cannot run the headless host, so the
/// first (unconditional) URI is the graph this guard must protect.
Iterable<String> _directives(String source) {
  final expression = RegExp(
    r'''^\s*(?:import|export|part)(?!\s+of\b)\s+(['"])([^'"]+)\1''',
    multiLine: true,
  );
  return expression.allMatches(source).map((match) => match.group(2)!);
}

String _display(Uri uri, Directory repository) {
  final path = File.fromUri(uri).absolute.path;
  return path.startsWith('${repository.path}/')
      ? path.substring(repository.path.length + 1)
      : path;
}

Uri _directory(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
