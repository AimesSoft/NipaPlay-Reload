import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

String webVttToSrt(String text) {
  if (!text.trimLeft().startsWith('WEBVTT')) {
    throw const Failure(
        FailureCode.invalidInput, 'WebVTT must begin with WEBVTT.');
  }
  final timing = RegExp(
      r'^((?:\d{2,}:)?\d{2}:\d{2}\.\d{3})\s+-->\s+((?:\d{2,}:)?\d{2}:\d{2}\.\d{3})');
  String time(String value) =>
      (value.split(':').length == 2 ? '00:$value' : value).replaceAll('.', ',');
  final cues = <String>[];
  for (final block in text.split(RegExp(r'\r?\n\r?\n+'))) {
    final lines = block.split(RegExp(r'\r?\n'));
    if (lines.first.startsWith('NOTE') ||
        lines.first == 'STYLE' ||
        lines.first == 'REGION') {
      continue;
    }
    final index = lines.indexWhere((line) => timing.hasMatch(line));
    if (index < 0) continue;
    final match = timing.firstMatch(lines[index])!;
    final content = lines
        .skip(index + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
    if (content.isEmpty) continue;
    cues.add(
        '${cues.length + 1}\n${time(match[1]!)} --> ${time(match[2]!)}\n$content');
  }
  return cues.join('\n\n');
}

Future<String> prepareWebVtt(String path, Directory root) async {
  final text = webVttToSrt(await File(path).readAsString());
  final hash = sha256.convert(utf8.encode(text)).toString();
  final dir = await Directory('${root.path}/subtitles').create(recursive: true);
  final saved = File('${dir.path}/vtt-$hash.srt');
  if (!await saved.exists()) await saved.writeAsString(text, flush: true);
  return saved.path;
}
