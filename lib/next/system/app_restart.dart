import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../harness_redaction.dart';

/// The executable path and arguments (without the program name) a process
/// was started with, read from a `kern.procargs2` sysctl value on macOS:
/// an int32 argument count, the executable path, padding NULs, then that many
/// NUL-terminated arguments (the environment follows and is ignored).
({String executable, List<String> arguments}) parseProcessArguments(
    List<int> bytes) {
  if (bytes.length < 5) {
    throw const FormatException('Process arguments are too short.');
  }
  final count = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 4)))
      .getInt32(0, Endian.host);
  var i = 4;
  String string() {
    final start = i;
    while (i < bytes.length && bytes[i] != 0) {
      i++;
    }
    final text = String.fromCharCodes(bytes.sublist(start, i));
    i++;
    return text;
  }

  final executable = string();
  while (i < bytes.length && bytes[i] == 0) {
    i++;
  }
  final arguments = <String>[for (var n = 0; n < count && i < bytes.length; n++) string()];
  if (arguments.length != count || count < 1) {
    throw const FormatException('Process arguments are incomplete.');
  }
  return (executable: executable, arguments: arguments.skip(1).toList());
}

/// How long the relaunch helper waits for the old process to exit.
const restartWaitSeconds = 60;

/// The shell command that waits for [pid] to exit, then runs [executable]
/// with [arguments]. The environment is the helper's own, inherited from the
/// process that starts it. Nothing is started if [pid] outlives the wait.
(String, List<String>) relaunchCommand(
        int pid, String executable, List<String> arguments,
        {int waitSeconds = restartWaitSeconds}) =>
    (
      '/bin/sh',
      [
        '-c',
        'pid="\$1"; shift; n=0; '
            'while kill -0 "\$pid" 2>/dev/null; do '
            'n=\$((n+1)); [ "\$n" -gt ${waitSeconds * 5} ] && exit 1; sleep 0.2; done; '
            'exec "\$@"',
        'sh',
        '$pid',
        executable,
        ...arguments,
      ]
    );

/// [argument] as the Windows command line carries it (the rules
/// CommandLineToArgvW reads back): quoted when it holds a space, tab or quote.
String windowsArgument(String argument) {
  if (argument.isNotEmpty && !RegExp(r'[ \t"]').hasMatch(argument)) {
    return argument;
  }
  final out = StringBuffer('"');
  var backslashes = 0;
  for (final unit in argument.runes) {
    final char = String.fromCharCode(unit);
    if (char == r'\') {
      backslashes++;
      continue;
    }
    if (char == '"') {
      out.write(r'\' * (backslashes * 2 + 1));
      out.write('"');
    } else {
      out.write(r'\' * backslashes);
      out.write(char);
    }
    backslashes = 0;
  }
  out.write(r'\' * (backslashes * 2));
  out.write('"');
  return out.toString();
}

/// The Windows form of [relaunchCommand]: PowerShell waits for [pid] to exit
/// (up to [waitSeconds]), then starts [executable] again in its own directory
/// with [arguments]. The script travels encoded, so no quoting survives to be
/// misread; the helper's environment is inherited from the process that starts
/// it, and the new process inherits that.
(String, List<String>) relaunchCommandWindows(
    int pid, String executable, List<String> arguments,
    {int waitSeconds = restartWaitSeconds}) {
  String quoted(String value) => "'${value.replaceAll("'", "''")}'";
  final directory = File(executable).parent.path;
  final script = '\$ErrorActionPreference = \'Stop\'; '
      '\$old = Get-Process -Id $pid -ErrorAction SilentlyContinue; '
      'if (\$old -and -not \$old.WaitForExit(${waitSeconds * 1000})) { exit 1 }; '
      'Start-Process -FilePath ${quoted(executable)} '
      '-WorkingDirectory ${quoted(directory)}'
      '${arguments.isEmpty ? '' : ' -ArgumentList @(${arguments.map((a) => quoted(windowsArgument(a))).join(',')})'}';
  return (
    'powershell.exe',
    [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      base64Encode(script.codeUnits.expand((u) => [u & 255, u >> 8]).toList()),
    ]
  );
}

/// The arguments this Windows process was started with (the command line
/// without the program name), through GetCommandLineW and CommandLineToArgvW.
Future<List<String>> readWindowsArguments() async {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final shell = DynamicLibrary.open('shell32.dll');
  final commandLine = kernel.lookupFunction<Pointer<Utf16> Function(),
      Pointer<Utf16> Function()>('GetCommandLineW');
  final toArgv = shell.lookupFunction<
      Pointer<Pointer<Utf16>> Function(Pointer<Utf16>, Pointer<Int32>),
      Pointer<Pointer<Utf16>> Function(
          Pointer<Utf16>, Pointer<Int32>)>('CommandLineToArgvW');
  final localFree = kernel.lookupFunction<Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('LocalFree');
  final count = calloc<Int32>();
  try {
    final argv = toArgv(commandLine(), count);
    if (argv == nullptr) throw const OSError('CommandLineToArgvW failed');
    try {
      return [for (var i = 1; i < count.value; i++) argv[i].toDartString()];
    } finally {
      localFree(argv.cast());
    }
  } finally {
    calloc.free(count);
  }
}

/// Restarts this application on macOS and Windows: a detached helper outlives the process,
/// waits for it to exit and starts the same executable again with the same
/// arguments and environment (so a lab profile comes back as itself), and this
/// process quits as `app.quit` does. On Windows the helper is PowerShell and
/// the arguments come from the command line. Other platforms have no relaunch
/// that is known to start this very installation, so they report it
/// unavailable.
final class AppRestart {
  AppRestart(
      {required this.quit,
      required this.beforeQuit,
      bool? macos,
      bool? windows,
      int? processId,
      String? executable,
      Future<List<int>> Function(int pid)? readArguments,
      Future<List<String>> Function()? readWindowsArgumentList,
      Future<void> Function(String, List<String>)? spawn,
      this.delay = const Duration(seconds: 1),
      this.profileName})
      : macos = macos ?? Platform.isMacOS,
        windows = windows ?? Platform.isWindows,
        readWindowsArgumentList = readWindowsArgumentList ?? readWindowsArguments,
        processId = processId ?? pid,
        executable = executable ?? Platform.resolvedExecutable,
        readArguments = readArguments ?? readProcessArgumentBytes,
        spawn = spawn ?? _spawnDetached;

  /// Ends the application (Classic's normal exit).
  final Future<void> Function() quit;

  /// Runs before the helper starts (pending settings writes).
  final Future<void> Function() beforeQuit;
  final bool macos;
  final bool windows;
  final Future<List<String>> Function() readWindowsArgumentList;
  final int processId;
  final String executable;
  final Future<List<int>> Function(int pid) readArguments;
  final Future<void> Function(String, List<String>) spawn;
  final Duration delay;
  final String? profileName;
  JsonMap? _scheduled;

  /// The `KERN_PROCARGS2` value of [pid] (macOS), through sysctl(3): the
  /// `sysctl` command line tool has no name for it.
  static Future<List<int>> readProcessArgumentBytes(int pid) async {
    final sysctl = DynamicLibrary.process().lookupFunction<
        Int Function(Pointer<Int>, UnsignedInt, Pointer<Void>, Pointer<Size>,
            Pointer<Void>, Size),
        int Function(Pointer<Int>, int, Pointer<Void>, Pointer<Size>,
            Pointer<Void>, int)>('sysctl');
    final mib = calloc<Int>(3);
    final size = calloc<Size>();
    Pointer<Uint8>? buffer;
    try {
      mib[0] = 1; // CTL_KERN
      mib[1] = 49; // KERN_PROCARGS2
      mib[2] = pid;
      if (sysctl(mib, 3, nullptr, size, nullptr, 0) != 0 || size.value == 0) {
        throw const OSError('sysctl KERN_PROCARGS2 failed');
      }
      buffer = calloc<Uint8>(size.value);
      if (sysctl(mib, 3, buffer.cast(), size, nullptr, 0) != 0) {
        throw const OSError('sysctl KERN_PROCARGS2 failed');
      }
      return Uint8List.fromList(buffer.asTypedList(size.value));
    } finally {
      calloc.free(mib);
      calloc.free(size);
      if (buffer != null) calloc.free(buffer);
    }
  }

  static Future<void> _spawnDetached(String command, List<String> arguments) =>
      Process.start(command, arguments, mode: ProcessStartMode.detached)
          .then((_) {});

  Future<JsonMap> restart() async {
    if (!macos && !windows) {
      throw Failure(FailureCode.unavailable,
          'Restarting the application is available on macOS and Windows only; ${Platform.operatingSystem} has no relaunch that is known to start this installation.');
    }
    if (_scheduled != null) return {..._scheduled!, 'alreadyScheduled': true};
    final List<String> arguments;
    try {
      arguments = windows
          ? await readWindowsArgumentList()
          : parseProcessArguments(await readArguments(processId)).arguments;
    } catch (error) {
      throw Failure(FailureCode.unavailable,
          'The arguments this process started with could not be read (${error.runtimeType}); nothing was restarted.');
    }
    await beforeQuit();
    final (command, helper) = windows
        ? relaunchCommandWindows(processId, executable, arguments)
        : relaunchCommand(processId, executable, arguments);
    try {
      await spawn(command, helper);
    } catch (error) {
      throw Failure(FailureCode.unavailable,
          'The relaunch helper could not be started (${error.runtimeType}); nothing was restarted.');
    }
    Timer(delay, () => unawaited(quit()));
    return _scheduled = redactHarnessJson({
      'scheduled': true,
      'processId': processId,
      'delayMs': delay.inMilliseconds,
      'executablePath': executable,
      'arguments': arguments,
      'environment': 'inherited from this process',
      'profileName': profileName,
      'relaunch':
          'A helper process waits up to $restartWaitSeconds s for this process to exit, then starts the executable again; if this process has not exited by then, nothing is started. The new process has a new processId and starts its own endpoint.',
    }) as JsonMap;
  }
}
