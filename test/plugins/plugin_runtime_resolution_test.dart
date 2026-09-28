import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/plugins/js_runtime_io.dart';
import 'package:nipaplay/plugins/url_resolver.dart';

void main() {
  test('script resolves through the native runtime and host protocol',
      () async {
    final runtime = FlutterJsRuntimeAdapter();
    addTearDown(runtime.dispose);
    runtime.evaluate(r'''
function pluginResolveUrl(input) {
  if (!input.state) {
    return { type: 'request', request: { url: 'https://example.test/view' },
      state: { step: 'metadata' } };
  }
  if (input.state.step === 'metadata') {
    const data = JSON.parse(input.response.body);
    return { type: 'select', title: data.title, items: data.items,
      preferredId: '22', state: { step: 'selected', title: data.title } };
  }
  if (input.state.step === 'selected') {
    return { type: 'request',
      request: { url: 'https://example.test/media?id=' + input.selectedId },
      state: { step: 'media', title: input.state.title, id: input.selectedId } };
  }
  return { type: 'play', url: JSON.parse(input.response.body).url,
    sourceUrl: 'https://example.test/watch?id=' + input.state.id,
    title: '第二话', searchTitle: input.state.title };
}
''');
    var requests = 0;
    final resolver = PluginUrlResolver(
        runtime: runtime,
        isActive: () => true,
        client: MockClient((request) async {
          requests++;
          final metadata = request.url.path.endsWith('/view');
          if (!metadata) expect(request.url.queryParameters['id'], '22');
          return http.Response(
              jsonEncode(metadata
                  ? {
                      'title': '示例标题',
                      'items': [
                        {'id': '11', 'title': '第一话'},
                        {'id': '22', 'title': '第二话'}
                      ],
                    }
                  : {'url': 'https://media.test/video.mp4'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    final result = await resolver.resolve('https://example.test/watch?id=22',
        select: (title, choices, preferredId) async {
      expect(title, '示例标题');
      expect(choices.length, 2);
      return preferredId;
    });
    expect(requests, 2);
    expect(result!.sourceUrl, endsWith('?id=22'));
    expect(result.title, contains('第二话'));
    expect(result.searchTitle, '示例标题');
  }, skip: !Platform.isMacOS);
}
