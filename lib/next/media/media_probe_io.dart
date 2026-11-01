import 'probe_process.dart';

String? get headlessFfprobe => mediaProbeProcess.ffprobeExecutable;
set headlessFfprobe(String? path) => mediaProbeProcess.ffprobeExecutable = path;
Future<int?> probeMediaDuration(String path) async =>
    (await probeMediaInfo(path))['durationMs'] as int?;
Future<Map<String, Object?>> probeMediaInfo(String path,
    {Future<void>? stopRequested}) {
  if (headlessFfprobe == null) return Future.value({'durationMs': null});
  return mediaProbeProcess.run(path, stopRequested: stopRequested);
}
