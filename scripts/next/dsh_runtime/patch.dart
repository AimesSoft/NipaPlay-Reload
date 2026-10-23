// Writes the `--patch` overlay NipaPlay gives DSH, for a route read from the
// environment (NIPAPLAY_TRACE_URL, NIPAPLAY_TRACE_MODEL, NIPAPLAY_TRACE_WIRE).
// Used by trace.py to find which packages a running Nipa loads.
//
//   dart run scripts/next/dsh_runtime/patch.dart <plugins dir> <harness> <out>
import 'dart:convert';
import 'dart:io';

import 'package:nipaplay/next/chat/dsh_runtime.dart';

Future<void> main(List<String> args) async {
  final plugins = Directory(args[0]);
  final env = Platform.environment;
  final route = DshRoute(
      baseUrl: env['NIPAPLAY_TRACE_URL']!,
      model: env['NIPAPLAY_TRACE_MODEL']!,
      key: 'unused',
      api: env['NIPAPLAY_TRACE_WIRE'] ?? 'openai-responses',
      imageInput: true);
  final patch = dshPatch(
      route: route,
      plugins: plugins,
      personaPrefix: (await File('${plugins.path}/persona-prefix.md').readAsString()).trim(),
      personaSuffix: (await File('${plugins.path}/persona-suffix.md').readAsString()).trim(),
      harness: args[1],
      version: 'trace');
  await File(args[2]).writeAsString(const JsonEncoder.withIndent('  ').convert(patch));
}
