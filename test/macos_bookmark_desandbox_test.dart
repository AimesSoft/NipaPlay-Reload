import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('security_bookmark');
  const original = '/fixture/media';
  final key = 'security_bookmark_${base64Encode(utf8.encode(original))}';
  var stale = false;
  final calls = <String>[];

  setUp(() {
    stale = false;
    calls.clear();
    SharedPreferences.setMockInitialValues({
      key: base64Encode([1, 2, 3])
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'isSandboxed' => false,
        'resolveBookmark' => {
            'path': '/fixture/relocated-media',
            'isStale': stale,
            'didStartAccessing': false,
          },
        'createBookmark' => Uint8List.fromList([4, 5, 6]),
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'ordinary bookmark returns relocated folder without an active scoped grant',
      () async {
    expect(await SecurityBookmarkService.resolveBookmark(original),
        '/fixture/relocated-media');
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('active_security_resources'),
        isNull);
    expect(calls, contains('resolveBookmark'));
  }, skip: !Platform.isMacOS);

  test('stale bookmark is refreshed after ordinary resolution', () async {
    stale = true;
    expect(await SecurityBookmarkService.resolveBookmark(original),
        '/fixture/relocated-media');
    expect(calls, contains('createBookmark'));
    final refreshedKey =
        'security_bookmark_${base64Encode(utf8.encode('/fixture/relocated-media'))}';
    expect((await SharedPreferences.getInstance()).getString(refreshedKey),
        base64Encode([4, 5, 6]));
  }, skip: !Platform.isMacOS);
}
