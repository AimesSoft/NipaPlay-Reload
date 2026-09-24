import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';
import 'package:nipaplay/plugins/url_resolver.dart';

class FakeRuntime implements PluginJsRuntime {
  FakeRuntime(this.step);
  final dynamic Function(Map<String, dynamic>) step;
  @override
  String evaluate(String code) {
    final start =
        code.indexOf('pluginResolveUrl(') + 'pluginResolveUrl('.length;
    final end = code.lastIndexOf(') : null)');
    return jsonEncode(step(jsonDecode(code.substring(start, end))));
  }

  @override
  void dispose() {}
  @override
  void setupBridge(String channelName, dynamic Function(dynamic) fn) {}
}

Map<String, dynamic> playable() => {
      'type': 'play',
      'url': 'https://media.test/video.mp4',
      'sourceUrl': 'https://source.test/watch?p=2',
      'title': 'Title',
      'searchTitle': 'Search',
    };
Future<String?> selectFirst(
        String _, List<PluginUrlChoice> items, String? __) async =>
    items.first.id;

void main() {
  test('request, choice and playback preserve state and response', () async {
    final runtime = FakeRuntime((input) {
      if (input['state'] == null) {
        return {
          'type': 'request',
          'state': 'info',
          'request': {
            'url': 'https://source.test/info',
            'headers': {'Referer': 'https://source.test/'}
          },
        };
      }
      if (input['state'] == 'info') {
        expect(input['response']['body'], 'metadata');
        expect(input['response']['status'], 200);
        return {
          'type': 'select',
          'title': 'Title',
          'state': 'play',
          'preferredId': 'two',
          'items': [
            {'id': 'one', 'title': 'First'},
            {'id': 'two', 'title': 'Second'}
          ]
        };
      }
      expect(input['selectedId'], 'two');
      return playable();
    });
    final result = await PluginUrlResolver(
      runtime: runtime,
      isActive: () => true,
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.headers['referer'], 'https://source.test/');
        return http.Response('metadata', 200);
      }),
    ).resolve('https://source.test/watch',
        select: (_, items, preferred) async => preferred);
    expect(result!.sourceUrl, 'https://source.test/watch?p=2');
    expect(result.searchTitle, 'Search');
  });

  test('unhandled sources fall back without requests', () async {
    final resolver = PluginUrlResolver(
        runtime: FakeRuntime((_) => null),
        isActive: () => true,
        client: MockClient(
            (_) async => throw StateError('Unexpected network call')));
    expect(
        await resolver.resolve('https://media.test/direct.mp4',
            select: selectFirst),
        isNull);
  });

  test('cancel and disable never return a playback result', () async {
    var active = true;
    final resolver = PluginUrlResolver(
        runtime: FakeRuntime((_) => {
              'type': 'request',
              'request': {'url': 'https://source.test/info'},
            }),
        isActive: () => active,
        client: MockClient((_) async {
          active = false;
          return http.Response('{}', 200);
        }));
    await expectLater(
        resolver.resolve('https://source.test/watch', select: selectFirst),
        throwsA(isA<PluginResolutionCancelled>()));
    final selection = PluginUrlResolver(
        runtime: FakeRuntime((_) => {
              'type': 'select',
              'title': 'Title',
              'items': [
                {'id': '1', 'title': 'One'}
              ],
            }),
        isActive: () => true);
    await expectLater(
        selection.resolve('https://source.test/watch',
            select: (_, __, ___) async => null),
        throwsA(isA<PluginResolutionCancelled>()));
  });

  test('invalid headers, schemes and repeated choices are rejected', () async {
    expect(() => checkedHttpHeaders({'Referer': 'valid\r\nCookie: injected'}),
        throwsFormatException);
    expect(() => checkedHttpHeaders({'Host': 'wrong.test'}),
        throwsFormatException);
    expect(() => checkedHttpUri('file:///tmp/file'), throwsFormatException);
    expect(
        () => PluginResolvedUrl(
            {...playable(), 'url': 'https://user:pass@media.test/'},
            isActive: () => true),
        throwsFormatException);
    final resolver = PluginUrlResolver(
        runtime: FakeRuntime((_) => {
              'type': 'select',
              'title': 'Title',
              'items': [
                {'id': '1', 'title': 'One'},
                {'id': '1', 'title': 'Duplicate'}
              ],
            }),
        isActive: () => true);
    await expectLater(
        resolver.resolve('https://source.test/watch', select: selectFirst),
        throwsFormatException);
  });

  test('response size and continuation count are bounded', () async {
    final runtime = FakeRuntime((_) => {
          'type': 'request',
          'request': {'url': 'https://source.test/'}
        });
    final oversized = PluginUrlResolver(
        runtime: runtime,
        isActive: () => true,
        client: MockClient((_) async => http.Response(
            'x' * (PluginUrlResolver.maxResponseBytes + 1), 200)));
    await expectLater(
        oversized.resolve('https://source.test/', select: selectFirst),
        throwsFormatException);
    var count = 0;
    final looping = PluginUrlResolver(
        runtime: runtime,
        isActive: () => true,
        client: MockClient((_) async {
          count++;
          return http.Response('', 200);
        }));
    await expectLater(
        looping.resolve('https://source.test/', select: selectFirst),
        throwsFormatException);
    expect(count, 16);
  });
}
