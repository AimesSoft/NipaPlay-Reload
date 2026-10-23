import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/player_remote_control_bridge.dart';

import '../ports/session_playback.dart';

bool _installed = false;

/// Installed only for Debug lab profiles. Exercises the production preview
/// decoder and remote bridge without manipulating desktop window placement.
void installDebugPlaybackFeatures(SessionPlayback Function() playback,
    {required List<ActionSpec> Function() catalog}) {
  if (_installed) return;
  _installed = true;
  registerExtension('ext.nipaplay.player.features', (_, params) async {
    try {
      final p = playback();
      final Map<String, Object?> result;
      switch (params['op']) {
        case 'catalog':
          result = {
            'actions': [
              for (final spec in catalog())
                if (spec.id.startsWith('playback.'))
                  {
                    'id': spec.id,
                    'input': spec.input.toJsonSchema(),
                    'output': spec.output.toJsonSchema(),
                    'effect': spec.effect.name
                  }
            ]
          };
        case 'remote':
          result = await PlayerRemoteControlBridge.instance.executeCommand(
              params['command']!,
              Map<String, dynamic>.from(
                  jsonDecode(params['args'] ?? '{}') as Map));
        case 'preview':
          final s = p.session!;
          final bytes = await p.preview.at(
              s.source.uri, Duration(milliseconds: int.parse(params['atMs']!)));
          if (bytes != null) {
            await File(params['outputPath']!).writeAsBytes(bytes);
          }
          result = {
            'enabled': p.preview.enabled,
            'bytes': bytes?.length,
            'sessionId': s.id
          };
        default:
          throw ArgumentError('op must be catalog, remote or preview');
      }
      return ServiceExtensionResponse.result(jsonEncode(result));
    } catch (error) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError, error.toString());
    }
  });
}
