import 'dart:async';
import 'dart:convert';
import 'dart:io';

String? headlessFfprobe;

Future<int?> probeMediaDuration(String path) async {
  final executable = headlessFfprobe;
  if (executable == null) return null;
  final process = await Process.start(executable,
      ['-v', 'error', '-show_entries', 'format=duration', '-of', 'json', path]);
  final output = utf8.decoder.bind(process.stdout).join();
  final errors = process.stderr.drain<void>();
  int code;
  try {
    code = await process.exitCode.timeout(const Duration(seconds: 15));
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    await output;
    await errors;
    return null;
  }
  final text = await output;
  await errors;
  if (code != 0) return null;
  final json = jsonDecode(text) as Map;
  final duration = (json['format'] as Map?)?['duration'];
  return duration == null ? null : (double.parse('$duration') * 1000).round();
}
