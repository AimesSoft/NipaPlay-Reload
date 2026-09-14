import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_windows/src/preferences_codec.dart';

class IsolateWitness {
  Map<String, Object?> toJson() => {'isolate': Isolate.current.debugName};
}

void main() {
  test('JSON conversion runs in the worker and returns final UTF-8 bytes',
      () async {
    final bytes = await encodePreferences({
      'position': 1200,
      'text': '弹幕😀\\"\n',
      'witness': IsolateWitness(),
    });
    expect(jsonDecode(utf8.decode(bytes)), {
      'position': 1200,
      'text': '弹幕😀\\"\n',
      'witness': {'isolate': 'nipaplay.preferences.encode'},
    });
  });

  test('encoding failures reach the caller', () async {
    await expectLater(encodePreferences({'invalid': double.nan}),
        throwsA(isA<JsonUnsupportedObjectError>()));
    expect(jsonDecode(utf8.decode(await encodePreferences({'next': 1}))),
        {'next': 1});
  });
}
