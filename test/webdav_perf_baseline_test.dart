import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// WebDAV 性能基线采集 harness。
// 用真实 WebDAVService（webdav_client + dio 全链路，不注入 validator）打本地 mock
// WebDAV 服务器，逐请求记录 method/path/Depth 与耗时，输出 docs/webdav/perf-baseline.json。
//
// 可测量指标：目录遍历 HTTP 请求数、切换/回访目录重复请求数、目录加载时延（本地 mock 骨架）、
// 搜索串行 vs 有界并发耗时对比。mock 服务器对每个 PROPFIND 额外引入 60ms 延迟，
// 用于模拟真实服务器往返，使并发收益可测。
// 不可测量指标（需真机/真实播放链路）：起播延迟、播放内存曲线 → 记入 unverified。
//
// 运行：flutter test test/webdav_perf_baseline_test.dart
// 刷新基线文件：WEBDAV_PERF_BASELINE_WRITE=1 flutter test test/webdav_perf_baseline_test.dart

class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.depth, this.elapsedMs);
  final String method;
  final String path;
  final String? depth;
  final int elapsedMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method,
        'path': path,
        'depth': depth,
        'at_ms': elapsedMs,
      };

  String get wire => '$method $path depth=$depth';
}

class _MockDavServer {
  _MockDavServer({this.propfindLatencyMs = 0, this.latencyFor});

  /// 每个 PROPFIND 引入的模拟服务器延迟（模拟真实往返）
  final int propfindLatencyMs;

  /// 按路径覆盖 PROPFIND 延迟（返回 null 时使用 [propfindLatencyMs]）
  final int? Function(String path)? latencyFor;

  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  final Stopwatch _clock = Stopwatch()..start();
  HttpServer? _server;
  int _activePropfind = 0;

  /// 同时在处理中的 PROPFIND 最大数量（观察客户端实际并发度）
  int maxActivePropfind = 0;

  int get count => requests.length;
  void reset() {
    requests.clear();
    maxActivePropfind = 0;
  }

  // 模拟目录树：
  // /  → Series/ Movies/ Bench/ readme.txt
  // /Series/ → Season 1/
  // /Series/Season 1/ → EP01.mkv EP02.mkv
  // /Movies/ → Movie1.mp4
  // /Bench/ → Dir0..Dir9（每个目录内 1 个 needle_*.mkv，用于搜索基准）
  late final Map<String, List<List<String>>> tree = _buildTree();

  Map<String, List<List<String>>> _buildTree() {
    final t = <String, List<List<String>>>{
      '/': <List<String>>[
        <String>['d', 'Series'],
        <String>['d', 'Movies'],
        <String>['d', 'Bench'],
        <String>['f', 'readme.txt'],
      ],
      '/Series/': <List<String>>[
        <String>['d', 'Season 1'],
      ],
      '/Series/Season 1/': <List<String>>[
        <String>['f', 'EP01.mkv'],
        <String>['f', 'EP02.mkv'],
      ],
      '/Movies/': <List<String>>[
        <String>['f', 'Movie1.mp4'],
      ],
      '/Bench/': <List<String>>[
        for (var i = 0; i < 10; i++)
          <String>['d', 'Dir$i'],
      ],
    };
    for (var i = 0; i < 10; i++) {
      t['/Bench/Dir$i/'] = <List<String>>[
        <String>['f', 'needle_$i.mkv'],
        <String>['f', 'other_$i.txt'],
      ];
    }
    // 不挂在根目录下，只供并发调度测试从 /Solo/ 起搜：
    // /Solo/ → Inner/ → D0..D5（每个目录内 1 个 needle）
    t['/Solo/'] = <List<String>>[
      <String>['d', 'Inner'],
    ];
    t['/Solo/Inner/'] = <List<String>>[
      for (var i = 0; i < 6; i++) <String>['d', 'D$i'],
    ];
    for (var i = 0; i < 6; i++) {
      t['/Solo/Inner/D$i/'] = <List<String>>[
        <String>['f', 'needle_solo_$i.mkv'],
      ];
    }
    return t;
  }

  Future<String> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      requests.add(_RecordedRequest(
        request.method,
        request.uri.path,
        request.headers.value('depth'),
        _clock.elapsedMilliseconds,
      ));
      try {
        if (request.method == 'OPTIONS') {
          request.response.statusCode = 200;
          request.response.headers.set('DAV', '1, 2');
          request.response.headers.set('MS-Author-Via', 'DAV');
          request.response.headers.set(
            'Allow',
            'OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK',
          );
          await request.response.close();
          return;
        }
        if (request.method == 'PROPFIND') {
          _activePropfind++;
          if (_activePropfind > maxActivePropfind) {
            maxActivePropfind = _activePropfind;
          }
          try {
            final latency =
                latencyFor?.call(Uri.decodeComponent(request.uri.path)) ??
                    propfindLatencyMs;
            if (latency > 0) {
              await Future<void>.delayed(Duration(milliseconds: latency));
            }
            final depth = request.headers.value('depth') ?? '1';
            final body = _multistatusFor(request.uri.path, depth);
            request.response.statusCode = 207;
            request.response.headers.contentType =
                ContentType('application', 'xml', charset: 'utf-8');
            request.response.write(body);
            await request.response.close();
          } finally {
            _activePropfind--;
          }
          return;
        }
        request.response.statusCode = 405;
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = 500;
          await request.response.close();
        } catch (_) {}
      }
    });
    return 'http://127.0.0.1:${server.port}/';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static String _dirHrefKey(String path) {
    final p = path.endsWith('/') ? path : '$path/';
    return p.isEmpty ? '/' : p;
  }

  String _multistatusFor(String rawPath, String depth) {
    var path = Uri.decodeComponent(rawPath);
    if (!path.startsWith('/')) path = '/$path';
    final selfIsDir = path == '/' || path.endsWith('/');
    final normalized = _dirHrefKey(path);
    final children =
        depth != '0' ? (tree[normalized] ?? const <List<String>>[]) : const <List<String>>[];

    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<D:multistatus xmlns:D="DAV:">');
    void addEntry(String href, bool isDir, {String? size}) {
      final display = Uri.decodeComponent(
          href.endsWith('/') ? href.substring(0, href.length - 1) : href);
      final parts = display.split('/').where((s) => s.isNotEmpty).toList();
      final name = parts.isEmpty ? '/' : parts.last;
      sb.writeln('  <D:response>');
      sb.writeln('    <D:href>$href</D:href>');
      sb.writeln('    <D:propstat>');
      sb.writeln('      <D:prop>');
      if (isDir) {
        sb.writeln('        <D:resourcetype><D:collection/></D:resourcetype>');
      } else {
        sb.writeln('        <D:resourcetype/>');
        sb.writeln(
            '        <D:getcontentlength>${size ?? '1048576'}</D:getcontentlength>');
      }
      sb.writeln('        <D:displayname>$name</D:displayname>');
      sb.writeln(
          '        <D:getlastmodified>Mon, 01 Jan 2026 00:00:00 GMT</D:getlastmodified>');
      sb.writeln('      </D:prop>');
      sb.writeln('      <D:status>HTTP/1.1 200 OK</D:status>');
      sb.writeln('    </D:propstat>');
      sb.writeln('  </D:response>');
    }

    addEntry(rawPath.isEmpty ? '/' : rawPath, selfIsDir);
    for (final child in children) {
      final isDir = child[0] == 'd';
      final name = child[1];
      final href = isDir
          ? '${normalized == '/' ? '/' : normalized}${Uri.encodeComponent(name)}/'
          : '${normalized == '/' ? '/' : normalized}${Uri.encodeComponent(name)}';
      addEntry(href, isDir);
    }
    sb.writeln('</D:multistatus>');
    return sb.toString();
  }
}

Future<Map<String, dynamic>> _runBaseline() async {
  final server = _MockDavServer(propfindLatencyMs: 60);
  final baseUrl = await server.start();

  final service = WebDAVService.forTesting();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await service.initialize();

  final scenarios = <Map<String, dynamic>>[];
  final connection = WebDAVConnection(
    name: 'perf-mock',
    url: baseUrl,
    username: '',
    password: '',
  );

  Future<void> record(
    String id,
    String description,
    Future<Object?> Function() action, {
    String target = '',
  }) async {
    server.reset();
    final sw = Stopwatch()..start();
    Object? error;
    Object? result;
    try {
      result = await action();
    } catch (e) {
      error = e.toString();
    }
    final elapsed = sw.elapsedMilliseconds;
    scenarios.add(<String, dynamic>{
      'id': id,
      'description': description,
      'target': target,
      'request_count': server.count,
      'requests': server.requests.map((r) => r.toJson()).toList(),
      'elapsed_ms': elapsed,
      if (error != null) 'error': error,
      if (result is int) 'result_count': result,
    });
  }

  await record(
    'add_connection',
    '首次添加连接（含服务端连通性验证 BFS 首选 URL）',
    () => service.upsertConnection(connection),
    target: 'request_count <= 3（1×OPTIONS 探测 + 1×PROPFIND 根目录）',
  );

  await record(
    'list_root_cold',
    '冷态进入根目录（缓存未命中）',
    () async => (await service.listDirectoryAll(connection, '/')).length,
    target: 'request_count == 1（仅 1 次 PROPFIND Depth:1）；elapsed_ms < 500（本地 mock 骨架）',
  );

  await record(
    'list_root_warm',
    '热态再次进入根目录（2 分钟缓存内）',
    () async => (await service.listDirectoryAll(connection, '/')).length,
    target: 'request_count == 0（缓存命中，0 次网络请求）',
  );

  await record(
    'browse_down_two_levels',
    '浏览下钻：/ → /Series/ → /Series/Season 1/',
    () async {
      await service.listDirectoryAll(connection, '/Series/');
      await service.listDirectoryAll(connection, '/Series/Season 1/');
      return null;
    },
    target: 'request_count == 2（每个新目录恰 1 次 PROPFIND）',
  );

  await record(
    'browse_back_revisit',
    '回访已浏览目录：Season 1 → /Series/ → /（模拟返回键）',
    () async {
      await service.listDirectoryAll(connection, '/Series/Season 1/');
      await service.listDirectoryAll(connection, '/Series/');
      await service.listDirectoryAll(connection, '/');
      return null;
    },
    target: 'request_count == 0（切换/返回目录零重复请求）',
  );

  await record(
    'list_filtered_warm',
    '带过滤的目录列表（listDirectory，视频/文件夹过滤）热态',
    () => service.listDirectory(connection, '/'),
    target: 'request_count == 0（过滤不触发网络）',
  );

  await record(
    'list_force_refresh',
    '用户手动刷新（forceRefresh，绕过缓存）',
    () async => (await service.listDirectoryAll(connection, '/', forceRefresh: true)).length,
    target: 'request_count == 1（显式刷新恰 1 次 PROPFIND）',
  );

  // 搜索基准：12 个待列目录（/ + /Bench/ + 10×/Bench/Dir_i/），每请求 60ms 模拟延迟，
  // requestIntervalMs=50。串行 ≈ 12×60+11×50 ≈ 1.27s；并发 3 受全局限速约束 ≈ 11×50+60 ≈ 0.65s。
  Future<List<WebDAVSearchResult>> runSearch({required int maxConcurrency}) {
    return service.searchFiles(
      connection: connection,
      keyword: 'needle',
      startPath: '/',
      scope: 'global',
      depthLimit: 2,
      requestIntervalMs: 50,
      maxConcurrency: maxConcurrency,
    );
  }

  String requestsFingerprint() {
    final entries = server.requests.map((r) => r.wire).toList()..sort();
    return entries.join('\n');
  }

  List<WebDAVSearchResult>? serialResults;
  String serialFingerprint = '';
  await record(
    'search_serial',
    '全局搜索 needle（串行 maxConcurrency=1，基线对照）',
    () async {
      service.clearDirectoryCache(connectionName: 'perf-mock');
      serialResults = await runSearch(maxConcurrency: 1);
      serialFingerprint = requestsFingerprint();
      return serialResults!.length;
    },
    target: '结果数 == 10；每目录恰 1 次请求',
  );

  List<WebDAVSearchResult>? parallelResults;
  String parallelFingerprint = '';
  await record(
    'search_parallel',
    '全局搜索 needle（有界并发 maxConcurrency=3，优化后）',
    () async {
      service.clearDirectoryCache(connectionName: 'perf-mock');
      parallelResults = await runSearch(maxConcurrency: 3);
      parallelFingerprint = requestsFingerprint();
      return parallelResults!.length;
    },
    target: '结果集与串行一致；请求集合与串行一致；elapsed_ms < search_serial',
  );

  await server.stop();

  int countOf(String id) =>
      scenarios.firstWhere((s) => s['id'] == id)['request_count'] as int;
  int elapsedOf(String id) =>
      scenarios.firstWhere((s) => s['id'] == id)['elapsed_ms'] as int;

  String pathsKey(List<WebDAVSearchResult>? results) =>
      ((results ?? const <WebDAVSearchResult>[])
          .map((r) => r.fullPath)
          .toList()
            ..sort())
          .join('\n');

  final searchResultsEqual = pathsKey(serialResults) == pathsKey(parallelResults);
  final searchRequestsEqual = serialFingerprint == parallelFingerprint;
  final serialElapsed = elapsedOf('search_serial');
  final parallelElapsed = elapsedOf('search_parallel');

  final verdicts = <String, dynamic>{
    'dir_listing_single_propfind': <String, dynamic>{
      'target': 1,
      'actual': countOf('list_root_cold'),
      'pass': countOf('list_root_cold') == 1,
    },
    'repeat_dir_switch_duplicate_requests': <String, dynamic>{
      'target': 0,
      'actual': countOf('browse_back_revisit') + countOf('list_root_warm'),
      'pass':
          countOf('browse_back_revisit') == 0 && countOf('list_root_warm') == 0,
    },
    'dir_load_latency_local_mock_ms': <String, dynamic>{
      'target': 500,
      'actual': elapsedOf('list_root_cold'),
      'pass': elapsedOf('list_root_cold') < 500,
      'caveat': '本地 mock 服务器（含 60ms 模拟延迟），仅代表协议往返+解析骨架耗时，不代表真实广域网场景',
    },
    'search_results_identical': <String, dynamic>{
      'target': '并发搜索结果集 == 串行搜索结果集',
      'actual': searchResultsEqual,
      'pass': searchResultsEqual,
    },
    'search_request_pattern_identical': <String, dynamic>{
      'target': '并发请求集合 == 串行请求集合（协议行为不变，逐目录恰好一次）',
      'actual': searchRequestsEqual,
      'pass': searchRequestsEqual,
    },
    'search_speedup': <String, dynamic>{
      'target': '并发耗时 < 串行耗时（重叠在途往返，全局速率仍受 requestIntervalMs 约束）',
      'actual': {'serial_ms': serialElapsed, 'parallel_ms': parallelElapsed},
      'pass': parallelElapsed < serialElapsed,
    },
  };

  return <String, dynamic>{
    'meta': <String, dynamic>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'generator':
          'test/webdav_perf_baseline_test.dart (flutter test, Windows host)',
      'service_under_test': 'lib/services/webdav_service.dart',
      'client_stack': 'webdav_client 1.2.2 (dio) + legacy http fallback',
      'mock_server':
          'dart:io HttpServer, loopback, PROPFIND/OPTIONS, PROPFIND 延迟 60ms',
      'targets': <String, dynamic>{
        'dir_listing_http_requests_max': 1,
        'duplicate_requests_on_dir_switch_max': 0,
        'dir_render_latency_ms_max': 500,
        'playback_start_latency_ms_max': 2000,
        'memory_growth': 'no sustained growth during playback',
      },
    },
    'scenarios': scenarios,
    'verdicts': verdicts,
    'unverified': <Map<String, dynamic>>[
      <String, dynamic>{
        'metric': 'playback_start_latency_ms',
        'target': 2000,
        'reason':
            '需真实播放链路（WebDAV 源 + 播放器 UI 起播）。当前环境无 Android/iOS 测试设备（用户声明"没有测试平台"，MuMu 模拟器被明确禁用），Windows 真实 WebDAV 源端到端起播未自动化。',
      },
      <String, dynamic>{
        'metric': 'memory_growth_during_playback',
        'target': '无持续上涨',
        'reason': '同上，需真机长稳观测（DevTools memory / HapRay）。本轮未采集。',
      },
      <String, dynamic>{
        'metric': 'dir_render_latency_real_network',
        'target': 500,
        'reason':
            '本基线的 elapsed_ms 采自本地 loopback mock（含 60ms 模拟延迟），不含真实广域网/NAS 高延迟；真实网络时延未测量。',
      },
    ],
  };
}

void main() {
  test('WebDAV 性能基线采集（WEBDAV_PERF_BASELINE_WRITE=1 时写入 docs/webdav/perf-baseline.json）',
      () async {
    final baseline = await _runBaseline();
    // 普通 flutter test 不改写仓库内文件，只有显式要求时才刷新基线。
    if (Platform.environment['WEBDAV_PERF_BASELINE_WRITE'] == '1') {
      final file = File('docs/webdav/perf-baseline.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(baseline));
    }

    // 硬断言：确定性目标（防回归）。search_speedup 依赖墙钟耗时，只记录在
    // 基线里，不做硬断言；并发调度由下面的确定性用例覆盖。
    final verdicts = baseline['verdicts'] as Map<String, dynamic>;
    bool passOf(String key) =>
        (verdicts[key] as Map<String, dynamic>)['pass'] as bool;
    expect(passOf('dir_listing_single_propfind'), isTrue,
        reason: '单次目录遍历应恰好 1 次 PROPFIND');
    expect(passOf('repeat_dir_switch_duplicate_requests'), isTrue,
        reason: '切换/回访目录不应产生重复网络请求');
    expect(passOf('dir_load_latency_local_mock_ms'), isTrue,
        reason: '本地 mock 下目录加载应 <500ms');
    expect(passOf('search_results_identical'), isTrue,
        reason: '并发搜索的结果集必须与串行完全一致');
    expect(passOf('search_request_pattern_identical'), isTrue,
        reason: '并发搜索的请求集合必须与串行完全一致（协议行为不变）');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('有界并发搜索：相邻请求发起间隔不小于 requestIntervalMs，且 worker 不会提前退出',
      () async {
    // /Solo/ 与 /Solo/Inner/ 很快返回，Inner 下 6 个目录很慢。Inner 出队时
    // 要等限速槽而此刻没有在途请求：若 worker 等待期间不计入在途，其余
    // worker 会把“队列空且无在途”当成结束而退出，6 个慢目录只能串行列出。
    final server = _MockDavServer(
      latencyFor: (path) => path.startsWith('/Solo/Inner/D') ? 150 : 5,
    );
    final baseUrl = await server.start();
    addTearDown(server.stop);

    final service = WebDAVService.forTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await service.initialize();
    final connection = WebDAVConnection(
      name: 'search-mock',
      url: baseUrl,
      username: '',
      password: '',
    );
    await service.upsertConnection(connection);
    server.reset();

    const intervalMs = 50;
    final results = await service.searchFiles(
      connection: connection,
      keyword: 'needle',
      startPath: '/Solo/',
      scope: 'current_with_depth',
      depthLimit: 2,
      requestIntervalMs: intervalMs,
      maxConcurrency: 3,
    );

    expect(results, hasLength(6));
    final starts = server.requests
        .where((r) => r.method == 'PROPFIND')
        .map((r) => r.elapsedMs)
        .toList()
      ..sort();
    expect(starts, hasLength(8), reason: '/Solo/ + Inner + 6 个子目录各 1 次');
    for (var i = 1; i < starts.length; i++) {
      // 留 15ms 余量给连接建立与计时抖动；竞争版本会出现接近 0 的间隔。
      expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(intervalMs - 15),
          reason: '请求发起时刻：$starts');
    }
    expect(server.maxActivePropfind, greaterThanOrEqualTo(2),
        reason: '慢目录应被多个 worker 重叠列出');
  });
}
