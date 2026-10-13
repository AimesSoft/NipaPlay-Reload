import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

final class HeadlessLibraryRoots implements Capability {
  HeadlessLibraryRoots(this.root, this.paths);
  final Directory root;
  final List<String> paths;
  Future<void> _tail = Future.value();
  Future<JsonMap> run(String operation, JsonMap input) async {
    final requested = (input['paths'] as List? ?? []).cast<String>();
    final canonical = <String>[];
    for (final path in requested) {
      if (!p.isAbsolute(path) || !await Directory(path).exists()) {
        throw const Failure(FailureCode.invalidInput, 'Roots must be existing absolute directories.');
      }
      final real = await Directory(path).resolveSymbolicLinks();
      final data = await root.resolveSymbolicLinks();
      if (p.equals(real, data) || p.isWithin(real, data) || p.isWithin(data, real)) {
        throw const Failure(FailureCode.invalidInput, 'Media roots and data directory must be separate.');
      }
      canonical.add(real);
    }
    if (operation != 'list') {
      final operationFuture = _tail.then((_) async {
        final next = paths.toSet();
        if (operation == 'add') { next.addAll(canonical); } else { next.removeAll(canonical); }
        final file = File(p.join(root.path, 'headless.json'));
        final config = jsonDecode(await file.readAsString()) as JsonMap;
        config['mediaRoots'] = next.toList();
        final pending = File('${file.path}.pending');
        await pending.writeAsString(jsonEncode(config), flush: true);
        await pending.rename(file.path);
        paths..clear()..addAll(next);
      });
      _tail = operationFuture.then<void>((_) {}, onError: (Object e, StackTrace s) {});
      await operationFuture;
    }
    return {'roots': paths.toList(), 'readOnly': true,
      'readOnlyScope': ['indexing', 'downloadDestination'],
      'fileOperations': 'processPermissions'};
  }
  @override
  List<Action> get actions => [for (final operation in ['list', 'add', 'remove']) _RootsAction(this, operation)];
}
final class _RootsJson implements JsonEncodable {
  const _RootsJson(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}
final class _RootsAction extends Action<_RootsJson, _RootsJson> {
  const _RootsAction(this.service, this.operation);
  final HeadlessLibraryRoots service;
  final String operation;
  @override
  ActionSpec get spec => ActionSpec(id: 'media.library.roots.$operation', title: 'Headless media roots $operation',
    description: 'Read or register existing local directories for read-only media indexing. Registration does not scan, bind identities, move or rename files.',
    effect: operation == 'list' ? Effect.read : Effect.write,
    input: ObjectSchema({'paths': const ArraySchema(StringSchema(minLength: 1))}, required: operation == 'list' ? [] : ['paths']),
    output: const ObjectSchema({}, additionalProperties: true));
  @override
  _RootsJson decodeInput(JsonMap json) => _RootsJson(json);
  @override
  Future<Outcome<_RootsJson>> run(_RootsJson input, Invocation invocation) async => Completed(_RootsJson(await service.run(operation, input.json)));
}
