import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/utils/http_header_utils.dart';

/// 回归背景：Dart 3.13 的 VM 里 `LinkedHashMap.removeWhere` 只标记 `_data`、
/// 不同步 `_index`，残留索引槽中的删除哨兵会被当作 key 交给 `equals`，抛
/// `type 'List<dynamic>' is not a subtype of type 'String'`（dart-lang/sdk#64217）。
/// `http` 的 `headers` 正是带自定义 equals 的大小写不敏感 map。
void main() {
  test('addOrReplaceHeaders 覆盖同名头且不破坏大小写不敏感的查找', () {
    final request = http.Request('GET', Uri.parse('https://example.com'));
    request.headers['Authorization'] = 'Bearer stale';
    request.headers['Accept'] = 'application/json';

    addOrReplaceHeaders(request.headers, {'authorization': 'Bearer fresh'});

    expect(request.headers['Authorization'], 'Bearer fresh');
    expect(
      request.headers.keys.where((key) => key.toLowerCase() == 'authorization'),
      hasLength(1),
    );
    expect(request.headers['Accept'], 'application/json');
  });

  test('removeHeader 之后仍可插入同名头（旧写法会抛 TypeError）', () {
    final request = http.Request('GET', Uri.parse('https://example.com'));
    request.headers['Accept-Encoding'] = 'gzip, deflate';

    removeHeader(request.headers, 'accept-encoding');
    request.headers['accept-encoding'] = 'identity';

    expect(request.headers.containsKey('Accept-Encoding'), isTrue);
    expect(request.headers['accept-encoding'], 'identity');
  });

  test('removeHeaderIfValueMatches 只删值匹配的头', () {
    final request = http.Request('GET', Uri.parse('https://example.com'));
    request.headers['Authorization'] = 'Bearer ours';
    request.headers['X-Other'] = 'kept';

    removeHeaderIfValueMatches(request.headers, 'authorization', 'Bearer other');
    expect(request.headers.containsKey('Authorization'), isTrue);

    removeHeaderIfValueMatches(request.headers, 'authorization', 'Bearer ours');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.headers['X-Other'], 'kept');
  });

  test('removeHeadersWhere 删掉全部命中的头且不留下坏索引', () {
    final request = http.Request('GET', Uri.parse('https://example.com'));
    request.headers['Connection'] = 'keep-alive';
    request.headers['Host'] = 'example.com';
    request.headers['Accept'] = 'application/json';

    removeHeadersWhere(
      request.headers,
      (key, _) => key.toLowerCase() == 'connection' || key.toLowerCase() == 'host',
    );
    request.headers['connection'] = 'close';

    expect(request.headers.containsKey('Host'), isFalse);
    expect(request.headers['connection'], 'close');
    expect(request.headers['Accept'], 'application/json');
  });
}
