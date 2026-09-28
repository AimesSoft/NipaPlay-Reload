// iOS-only renderer comparison. See README.md in this directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/danmaku_dfm/dfm_plus_overlay.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

var renderer =
    const String.fromEnvironment('DFM_BENCH_RENDERER', defaultValue: 'dfm');
const host = String.fromEnvironment('DFM_BENCH_HOST',
    defaultValue: 'http://127.0.0.1:8765');
const duration = 30;

// The green comment can be tracked in a simctl recording. Repeated ordinary
// comments keep density/atlas work identical between runs.
final comments = <Map<String, dynamic>>[
  for (int i = 0; i < 900; i++)
    {
      'time': 0.5 + i / 30,
      'content': '流畅弹幕测试 ${i % 10} NipaPlay',
      'type': 'scroll',
      'originalType': 1,
      'fontSize': 25,
      'color': 0xFFFFFF
    },
  for (int i = 0; i < 4; i++)
    {
      'time': 1.0 + i * 8,
      'content': '████ TRACK ████',
      'type': 'scroll',
      'originalType': 1,
      'fontSize': 25,
      'color': 0x00FF00
    },
]..sort((a, b) => (a['time'] as num).compareTo(b['time'] as num));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isIOS) throw UnsupportedError('Run this benchmark on iOS.');
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ensureRustInitialized();
  // A local config lets the same installed native binary run either renderer
  // with hot restart, avoiding different native builds in the comparison.
  final client = HttpClient();
  try {
    final response =
        await (await client.getUrl(Uri.parse('$host/config.json'))).close();
    if (response.statusCode == 200) {
      final config =
          jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      renderer = config['renderer'] as String? ?? renderer;
    }
  } finally {
    client.close();
  }
  runApp(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child:
          const MaterialApp(debugShowCheckedModeBanner: false, home: Bench())));
}

class Bench extends StatefulWidget {
  const Bench({super.key});
  @override
  State<Bench> createState() => _BenchState();
}

class _BenchState extends State<Bench> {
  final time = ValueNotifier<double>(0);
  final watch = Stopwatch();
  final timings = <FrameTiming>[];
  Timer? timer;
  WebViewController? web;
  bool playing = false;
  bool visible = true;
  bool manual = false;
  double rate = 1;
  double offset = 0;
  int seekRevision = 0;
  int lastClockUs = 0;
  Map<String, dynamic> layoutSnapshot = {};
  String status = 'Preparing $renderer';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(collect);
    developer.registerExtension('ext.dfmBench.control', (_, params) async {
      if (params['finish'] == 'true') {
        await finish();
      } else if (params['restart'] == 'true') {
        manual = true;
        timer?.cancel();
        watch
          ..stop()
          ..reset();
        time.value = 0;
        seekRevision++;
        timings.clear();
        start();
      } else {
        advanceClock();
        if (params.containsKey('position')) {
          time.value = double.parse(params['position']!) * 1000;
          seekRevision++;
        }
        setState(() {
          if (params.containsKey('playing')) {
            playing = params['playing'] == 'true';
          }
          if (params.containsKey('visible')) {
            visible = params['visible'] == 'true';
          }
          if (params.containsKey('rate')) rate = double.parse(params['rate']!);
          if (params.containsKey('offset')) {
            offset = double.parse(params['offset']!);
          }
          status =
              '$renderer · t=${(time.value / 1000).toStringAsFixed(2)} · rate=$rate · playing=$playing';
        });
        await sendClock();
      }
      return developer.ServiceExtensionResponse.result(jsonEncode(snapshot()));
    });
    developer.registerExtension(
        'ext.dfmBench.snapshot',
        (_, __) async =>
            developer.ServiceExtensionResponse.result(jsonEncode(snapshot())));
    if (renderer == 'titan') {
      unawaited(prepareTitan());
    } else {
      // Let layout, Metal pipelines, and glyph prefetch warm up first.
      timer = Timer(const Duration(seconds: 8), start);
    }
  }

  void collect(List<FrameTiming> batch) {
    if (watch.elapsedMilliseconds > 5000 && playing) timings.addAll(batch);
  }

  Future<void> send(Map<String, dynamic> message) async {
    await web?.runJavaScript(
        'window.NipaDanmakuRenderer.handle(${jsonEncode(message)});');
  }

  Future<void> prepareTitan() async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(Colors.transparent);
    await controller.addJavaScriptChannel('NipaDanmakuHost',
        onMessageReceived: (message) async {
      final data = jsonDecode(message.message) as Map;
      if (data['type'] == 'ready') {
        await controller.runJavaScript('''
          window.nipaBench = {start: null, frames: []};
          function observeFrame(t) {
            if (nipaBench.start !== null && t - nipaBench.start > 5000) {
              nipaBench.frames.push(t);
            }
            requestAnimationFrame(observeFrame);
          }
          requestAnimationFrame(observeFrame);
        ''');
        await send({'type': 'load', 'items': comments});
        await send({
          'type': 'settings',
          'value': {
            'visible': true,
            'displayArea': 1,
            'rendererSettings': {
              'opacity': 1,
              'fontSize': 1,
              'duration': 8.1,
              'limit': 300
            }
          }
        });
        timer = Timer(const Duration(seconds: 8), start);
      } else {
        debugPrint('DFM_BENCH_WEB ${message.message}');
      }
    });
    setState(() => web = controller);
    await controller.loadRequest(Uri.parse('$host/titan.html'));
  }

  void start() {
    if (!mounted) return;
    watch.start();
    lastClockUs = watch.elapsedMicroseconds;
    unawaited(web?.runJavaScript(
        'nipaBench.frames = []; nipaBench.start = performance.now();'));
    setState(() {
      playing = true;
      status = '$renderer · 30 comments/s';
    });
    debugPrint('DFM_BENCH_START $renderer');
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      advanceClock();
      unawaited(sendClock());
      if (!manual && watch.elapsedMilliseconds >= duration * 1000) {
        unawaited(finish());
      }
    });
  }

  void advanceClock() {
    final now = watch.elapsedMicroseconds;
    if (playing) time.value += (now - lastClockUs) / 1000 * rate;
    lastClockUs = now;
  }

  Future<void> sendClock() => send({
        'type': 'clock',
        'positionSeconds': time.value / 1000,
        'playing': playing,
        'playbackRate': rate,
        'seekRevision': seekRevision,
      });

  Map<String, dynamic> snapshot() => {
        'renderer': renderer,
        'position': time.value / 1000,
        'playing': playing,
        'rate': rate,
        'visible': visible,
        'offset': offset,
        'layout': layoutSnapshot,
        'flutter_frames': timings.length,
        'build_p95_us': percentile(
            timings.map((e) => e.buildDuration.inMicroseconds).toList()),
        'raster_p95_us': percentile(
            timings.map((e) => e.rasterDuration.inMicroseconds).toList()),
      };

  int percentile(List<int> values) {
    if (values.isEmpty) return 0;
    values.sort();
    return values[((values.length - 1) * .95).round()];
  }

  Future<void> finish() async {
    final refreshHz = View.of(context).display.refreshRate;
    timer?.cancel();
    watch.stop();
    setState(() {
      playing = false;
      status = '$renderer · complete';
    });
    await sendClock();
    double percentile(List<int> values, double p) {
      if (values.isEmpty) return 0;
      values.sort();
      return values[((values.length - 1) * p).round()] / 1000;
    }

    final frameBudgetUs = 1000000 / (refreshHz >= 30 ? refreshHz : 60);
    final result = <String, dynamic>{
      'renderer': renderer,
      'display_hz': refreshHz,
      'frames': timings.length,
      'build_p95_ms': percentile(
          timings.map((e) => e.buildDuration.inMicroseconds).toList(), .95),
      'raster_p95_ms': percentile(
          timings.map((e) => e.rasterDuration.inMicroseconds).toList(), .95),
      'slow_flutter_frames': timings
          .where((e) =>
              e.buildDuration.inMicroseconds > frameBudgetUs ||
              e.rasterDuration.inMicroseconds > frameBudgetUs)
          .length
    };
    if (web != null) {
      final raw = await web!
          .runJavaScriptReturningResult('JSON.stringify(nipaBench.frames)');
      var decoded = jsonDecode(raw.toString());
      if (decoded is String) decoded = jsonDecode(decoded);
      final frames = (decoded as List).cast<num>();
      final deltas = [
        for (int i = 1; i < frames.length; i++)
          (frames[i] - frames[i - 1]).toDouble()
      ]..sort();
      result['web_raf_frames'] = frames.length;
      if (deltas.isNotEmpty) {
        result['web_raf_interval_p50_ms'] = deltas[deltas.length ~/ 2];
        result['web_raf_interval_p95_ms'] =
            deltas[((deltas.length - 1) * .95).round()];
      }
    }
    debugPrint('DFM_BENCH_RESULT ${jsonEncode(result)}');
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$host/result'));
      final bytes = utf8.encode(jsonEncode(result));
      request.contentLength = bytes.length;
      request.add(bytes);
      await (await request.close()).drain<void>();
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (renderer == 'dfm')
          Positioned.fill(
              child: DfmPlusOverlay(
            danmakuList: comments,
            danmakuListVersion: 1,
            playbackTimeMs: time,
            currentTimeSeconds: 0,
            fontSize: 25,
            isVisible: visible,
            opacity: 1,
            displayArea: 1,
            timeOffset: offset,
            scrollDurationSeconds: 9,
            allowStacking: false,
            mergeDanmaku: false,
            customFontFamily: '',
            customFontFilePath: '',
            outlineWidth: 1,
            shadowStyle: DanmakuShadowStyle.none,
            trackGapRatio: .15,
            isPlaying: playing,
            playbackRate: rate,
            seekRevision: seekRevision,
            onLayoutCalculated: (items) {
              final scroll =
                  items.where((e) => e.typeCode == 1 && e.scrollSpeed > 0);
              final first = scroll.isEmpty ? null : scroll.first;
              layoutSnapshot = {
                'count': items.length,
                if (first != null) ...{
                  'sample_media': first.time +
                      (first.offstageX - first.width - first.x) /
                          first.scrollSpeed,
                  'first_time': first.time,
                  'first_x': first.x,
                  'first_text': first.content.text,
                  'speed': first.scrollSpeed,
                },
              };
            },
          )),
        if (web != null)
          Positioned.fill(child: WebViewWidget(controller: web!)),
        Positioned(
            bottom: 8,
            left: 16,
            child: Text(status,
                style: const TextStyle(color: Colors.red, fontSize: 16))),
      ]));
}
