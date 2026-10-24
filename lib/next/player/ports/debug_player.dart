import 'dart:convert';
import 'dart:developer';

import 'package:flutter/services.dart';

import '../core/host.dart';
import '../core/session.dart';

bool _installed = false;

/// Lab-only: `ext.nipaplay.player.host` op=facts (the host's facts),
/// op=lifecycles (every ended session's kernel lifecycle kept: creation,
/// open and release times), op=kernel (the kernel's own facts, read in its
/// queue: tracks, decoder reports) or op=open path=… [paused=1] [startMs=…]
/// (an open as playback.open makes it, which can also ask to open paused);
/// `ext.nipaplay.player.windowShot` path=… writes the app's own window as
/// the window server composes it (the native video under a hole included)
/// to that path.
void installDebugPlayerHost(NextPlayerHost Function() host) {
  if (_installed) return;
  _installed = true;
  registerExtension('ext.nipaplay.player.host', (_, params) async {
    final Object result;
    switch (params['op']) {
      case 'lifecycles':
        result = {'lifecycles': host().lifecycles};
      case 'kernel':
        final driver = host().current.value?.driver;
        result = driver == null || driver.fenced
            ? {'kernel': null}
            : await driver.readFacts();
      case 'text':
        // What the kernel says it draws now, or has at atMs.
        final driver = host().current.value?.driver;
        final at = int.tryParse(params['atMs'] ?? '');
        result = {
          'text': driver == null || driver.fenced
              ? null
              : await driver.subtitleText(
                  at: at == null ? null : Duration(milliseconds: at)),
        };
      case 'open':
        final watch = Stopwatch()..start();
        final start = int.tryParse(params['startMs'] ?? '');
        final session = await host().open(MediaRequest(
          locator: params['path']!,
          origin: 'lab',
          paused: params['paused'] == '1' ? true : null,
          start: start == null ? null : Duration(milliseconds: start),
        ));
        result = {'openedMs': watch.elapsedMilliseconds, ...session.facts()};
      default:
        result = host().facts();
    }
    return ServiceExtensionResponse.result(jsonEncode(result));
  });
  registerExtension('ext.nipaplay.player.windowShot', (_, params) async {
    try {
      final shot = await const MethodChannel('security_bookmark')
          .invokeMethod<Object?>('labWindowShot', {'path': params['path']});
      return ServiceExtensionResponse.result(jsonEncode(shot));
    } on PlatformException catch (error) {
      return ServiceExtensionResponse.result(
          jsonEncode({'error': error.code, 'message': error.message}));
    }
  });
}
