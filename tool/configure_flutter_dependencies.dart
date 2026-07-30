import 'dart:io';

const _generatedOverrides = 'pubspec_overrides.yaml';
const _harmonyOverrides = 'pubspec_overrides.ohos.yaml';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      (arguments.single != 'ohos' && arguments.single != 'mainline')) {
    stderr.writeln(
      'Usage: dart run tool/configure_flutter_dependencies.dart '
      '<ohos|mainline>',
    );
    exitCode = 64;
    return;
  }

  final generatedFile = File(_generatedOverrides);
  if (arguments.single == 'ohos') {
    final harmonyFile = File(_harmonyOverrides);
    if (!harmonyFile.existsSync()) {
      stderr.writeln('Missing $_harmonyOverrides');
      exitCode = 66;
      return;
    }
    generatedFile.writeAsStringSync(harmonyFile.readAsStringSync());
    stdout.writeln(
      'HarmonyOS dependency overrides enabled. Run flutter pub get next.',
    );
    return;
  }

  if (generatedFile.existsSync()) {
    generatedFile.deleteSync();
  }
  stdout.writeln(
    'Mainline dependency graph enabled. Run flutter pub get next.',
  );
}
