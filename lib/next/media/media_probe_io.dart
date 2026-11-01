import 'probe_process.dart';

String? get headlessFfprobe => mediaProbeProcess.executable;
set headlessFfprobe(String? path) => mediaProbeProcess.executable = path;
Future<int?> probeMediaDuration(String path) async =>
    (await probeMediaInfo(path))['durationMs'] as int?;
Future<Map<String, Object?>> probeMediaInfo(String path,
    {Future<void>? stopRequested}) {
  return mediaProbeProcess.run(path, stopRequested: stopRequested);
}
