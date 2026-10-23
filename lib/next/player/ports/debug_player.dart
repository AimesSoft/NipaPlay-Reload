import 'dart:convert';
import 'dart:developer';

import '../core/host.dart';

bool _installed = false;

/// Lab-only: `ext.nipaplay.player.host` op=facts (the host's facts) or
/// op=lifecycles (every ended session's kernel lifecycle kept: creation,
/// open and release times).
void installDebugPlayerHost(NextPlayerHost Function() host) {
  if (_installed) return;
  _installed = true;
  registerExtension('ext.nipaplay.player.host', (_, params) async {
    final result = switch (params['op']) {
      'lifecycles' => {'lifecycles': host().lifecycles},
      _ => host().facts(),
    };
    return ServiceExtensionResponse.result(jsonEncode(result));
  });
}
