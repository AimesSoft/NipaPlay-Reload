import 'dart:io';

const _generatedOverrides = 'pubspec_overrides.yaml';
const _harmonyOverrides = 'pubspec_overrides.ohos.yaml';
const _linuxOverrides = 'pubspec_overrides.linux.yaml';
const _tvOSOverrides = 'pubspec_overrides.tvos.yaml';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !const {'ohos', 'linux', 'tvos', 'mainline'}.contains(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tool/configure_flutter_dependencies.dart '
      '<ohos|linux|tvos|mainline>',
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

  if (arguments.single == 'linux') {
    final linuxFile = File(_linuxOverrides);
    if (!linuxFile.existsSync()) {
      stderr.writeln('Missing $_linuxOverrides');
      exitCode = 66;
      return;
    }
    generatedFile.writeAsStringSync(linuxFile.readAsStringSync());
    stdout.writeln(
      'Linux Flutter 3.47 dependency overrides enabled. '
      'Run flutter pub get next.',
    );
    return;
  }

  if (arguments.single == 'tvos') {
    final tvOSFile = File(_tvOSOverrides);
    if (!tvOSFile.existsSync()) {
      stderr.writeln('Missing $_tvOSOverrides');
      exitCode = 66;
      return;
    }
    generatedFile.writeAsStringSync(tvOSFile.readAsStringSync());
    stdout.writeln(
      'tvOS dependency overrides enabled. Run flutter-tvos pub get next.',
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
