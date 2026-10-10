part of 'kernel.dart';

final class JsonlJournal implements InvocationObserver {
  JsonlJournal(
    File file, {
    Set<Effect> effects = const {Effect.write, Effect.destructive},
  })  : _file = file,
        _effects = Set.of(effects);

  final File _file;
  final Set<Effect> _effects;

  @override
  void onInvocation(InvocationRecord record) {
    if (!_effects.contains(record.effect)) return;
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
