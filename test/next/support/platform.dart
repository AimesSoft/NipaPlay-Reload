import 'dart:io';

/// The interpreter harness scripts run with: Windows installs `python`, and
/// its `python3` is at best a Store stub.
final String pythonCommand = Platform.isWindows ? 'python' : 'python3';

/// Removes a test directory. Windows refuses to delete a file another handle
/// still has open (a SQLite file a killed worker isolate never closed); the
/// directory is in the system temp area and the next reboot clears it.
Future<void> deleteTestDirectory(Directory directory) async {
  for (var attempt = 1;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (!Platform.isWindows) rethrow;
      if (attempt == 5) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

/// Where `cargo build` leaves what the mesh tests run.
String get meshNativeLibraryPath => Platform.isWindows
    ? 'rust/target/debug/rust_lib_nipaplay.dll'
    : 'rust/target/debug/librust_lib_nipaplay.${Platform.isMacOS ? 'dylib' : 'so'}';
String get meshCoordinatorPath =>
    'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator${Platform.isWindows ? '.exe' : ''}';
String get meshIssueExamplePath =>
    'rust/mesh/target/debug/examples/issue${Platform.isWindows ? '.exe' : ''}';

/// What a child started with an empty environment still needs on Windows:
/// without SystemRoot, Winsock cannot start (error 10106).
Map<String, String> get windowsSystemEnvironment => {
      if (Platform.isWindows)
        for (final name in ['SystemRoot', 'windir'])
          if (Platform.environment[name] case final value?) name: value,
    };

/// ffmpeg and ffprobe: Homebrew's on a Mac, else whatever the PATH finds.
String get ffmpegExecutable =>
    Platform.isMacOS ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg';
String get ffprobeExecutable =>
    Platform.isMacOS ? '/opt/homebrew/bin/ffprobe' : 'ffprobe';
