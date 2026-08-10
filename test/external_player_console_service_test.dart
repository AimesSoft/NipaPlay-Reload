import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/danmaku/mode.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/models/danmaku/blocked_item.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/pages/external_player_console_page.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';
import 'package:nipaplay/utils/external_player_danmaku_ass.dart';
import 'package:nipaplay/utils/mpv_utils.dart';

_TestSession _session(
  Process process, {
  String mediaPath = '/tmp/test-video.mkv',
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  double danmakuOutlineWidth = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
  List<DanmakuItem> danmakuList = const [],
  AssExportSettings? danmakuAssSettings,
  bool pollPlaybackState = false,
}) {
  return _sessionFromProcessId(
    process.pid,
    mediaPath: mediaPath,
    ipcPath: ipcPath,
    danmakuAssPath: danmakuAssPath,
    danmakuOpacity: danmakuOpacity,
    danmakuOutlineWidth: danmakuOutlineWidth,
    position: position,
    duration: duration,
    isPaused: isPaused,
    danmakuList: danmakuList,
    danmakuAssSettings: danmakuAssSettings,
    monitorProcess: true,
    processExitCode: process.exitCode,
    pollPlaybackState: pollPlaybackState,
  );
}

_TestSession _sessionFromProcessId(
  int processId, {
  String mediaPath = '/tmp/test-video.mkv',
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  double danmakuOutlineWidth = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
  List<DanmakuItem> danmakuList = const [],
  AssExportSettings? danmakuAssSettings,
  bool monitorProcess = false,
  Future<int>? processExitCode,
  bool pollPlaybackState = false,
}) {
  final settings = danmakuAssSettings ?? const AssExportSettings(fontSize: 30);
  return _TestSession(
    playerPath: '/bin/mpv',
    mediaPath: mediaPath,
    processId: processId,
    ipcPath: ipcPath,
    duration: duration,
    position: position,
    isPaused: isPaused,
    danmakuAssPath: danmakuAssPath,
    danmakuList: danmakuList,
    danmakuStyle: DanmakuStyle(
      opacity: danmakuOpacity,
      outlineWidth: danmakuOutlineWidth,
      danmakuFontSize: settings.fontSize,
      danmakuOffset: settings.timeOffsetSeconds,
      danmakuAllowStacking: settings.allowStacking,
    ),
    processExitCode: monitorProcess ? processExitCode : null,
    pollPlaybackState: pollPlaybackState,
  );
}

void _showSession(
  _TestSession session, {
  EpisodeMetaData? episodeMetaData,
}) {
  ExternalPlayerConsoleService.setState(ConsoleState(
    session: session,
    episodeMetaData: episodeMetaData,
    danmakuList: session.danmakuList,
    danmakuStyle: session.danmakuStyle,
  ));
}

class _TestSession extends ChangeNotifier implements ExternalPlayerLaunchSession {
  _TestSession({
    required this.playerPath,
    required this.mediaPath,
    required this.processId,
    required this.duration,
    required this.position,
    required this.isPaused,
    required this.danmakuList,
    required this.danmakuStyle,
    this.ipcPath,
    this.danmakuAssPath,
    Future<int>? processExitCode,
    bool pollPlaybackState = false,
  }) {
    processExitCode?.then((_) => _close());
    if (pollPlaybackState) {
      _stateTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _refreshPlaybackState(),
      );
    }
  }

  @override
  ExternalPlayerType get type => ExternalPlayerType.mpv;
  @override
  final String playerPath;
  @override
  final String mediaPath;
  @override
  final int processId;
  @override
  final String? ipcPath;
  @override
  Duration duration;
  @override
  Duration? position;
  @override
  bool? isPaused;
  final String? danmakuAssPath;
  final List<DanmakuItem> danmakuList;
  final DanmakuStyle danmakuStyle;
  Timer? _stateTimer;
  bool _closed = false;
  bool _disposed = false;

  @override
  double? get fraction {
    if (position == null || duration <= Duration.zero) return null;
    return (position!.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> launch() async {}

  @override
  void terminate() {
    if (_closed) return;
    Process.killPid(processId, ProcessSignal.sigterm);
    _close();
  }

  @override
  void togglePause() {
    final paused = !(isPaused ?? false);
    _sendCommand([
      'set_property',
      'pause',
      paused,
    ], 4).then((succeeded) {
      if (!succeeded || _closed) return;
      isPaused = paused;
      notifyListeners();
    });
  }

  @override
  void seekToFraction(double fraction) {
    if (duration <= Duration.zero) return;
    seekToPosition(Duration(
      milliseconds: (duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    ));
  }

  @override
  bool seekToPosition(Duration target) {
    if (_closed || ipcPath == null || target < Duration.zero) return false;
    final milliseconds = target.inMilliseconds.clamp(0, duration.inMilliseconds);
    position = Duration(milliseconds: milliseconds);
    notifyListeners();
    _sendCommand([
      'seek',
      milliseconds / 1000.0,
      'absolute+exact',
    ], 6);
    return true;
  }

  @override
  Future<bool> refreshDanmaku(
    DanmakuItemSet danmakuSet,
    DanmakuStyle style,
  ) async {
    final path = danmakuAssPath;
    if (_closed || ipcPath == null || path == null) return false;
    final ass = await generateExternalPlayerDanmakuAss(
      danmakuSet.toList(growable: false),
      AssExportSettings(
        fontSize: style.danmakuFontSize,
        opacity: style.opacity,
        timeOffsetSeconds: style.danmakuOffset,
        allowStacking: style.danmakuAllowStacking,
        outlineStyle:
            style.outlineEnabled ? AssOutlineStyle.uniform : AssOutlineStyle.none,
        outlineWidth: style.outlineWidth,
      ),
    );
    final temporaryFile = File('$path.nipaplay.tmp');
    try {
      await temporaryFile.writeAsString(ass, flush: true);
      await temporaryFile.rename(path);
      final scriptName = path.split(Platform.pathSeparator).last;
      return _sendCommand([
        'script-message-to',
        scriptName,
        'nipaplay-danmaku-reload',
        path,
      ], 5);
    } finally {
      if (temporaryFile.existsSync()) await temporaryFile.delete();
    }
  }

  Future<bool> _sendCommand(List<Object> command, int requestId) async {
    final path = ipcPath;
    if (_closed || path == null) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      socket.writeln(jsonEncode({
        'command': command,
        'request_id': requestId,
      }));
      await socket.flush();
      await for (final line in socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800))) {
        final response = jsonDecode(line) as Map<String, dynamic>;
        if (response['request_id'] == requestId) {
          return response['error'] == 'success';
        }
      }
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
    return false;
  }

  Future<void> _refreshPlaybackState() async {
    final path = ipcPath;
    if (_closed || path == null) return;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      for (final request in const [
        (id: 1, property: 'time-pos'),
        (id: 2, property: 'duration'),
        (id: 3, property: 'pause'),
      ]) {
        socket.writeln(jsonEncode({
          'command': ['get_property', request.property],
          'request_id': request.id,
        }));
      }
      await socket.flush();
      final values = <int, dynamic>{};
      await for (final line in socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(milliseconds: 800))) {
        final response = jsonDecode(line) as Map<String, dynamic>;
        values[response['request_id'] as int] = response['data'];
        if (values.length == 3) break;
      }
      position = Duration(
        milliseconds: (((values[1] as num?) ?? 0) * 1000).round(),
      );
      duration = Duration(
        milliseconds: (((values[2] as num?) ?? 0) * 1000).round(),
      );
      isPaused = values[3] as bool? ?? false;
      notifyListeners();
    } catch (_) {
      return;
    } finally {
      socket?.destroy();
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _stateTimer?.cancel();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateTimer?.cancel();
    super.dispose();
  }
}

List<int> _activeDisplayIndices() {
  return ExternalPlayerConsoleService.displayDanmakuList
      .where((item) => item.isActive)
      .map((item) => item.index)
      .toList(growable: false);
}

Future<Process> _startPlayer({String duration = '30'}) {
  return Process.start('/bin/sleep', [duration]);
}

Future<void> _stopProcess(Process process) async {
  Process.killPid(process.pid, ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 1));
  } on TimeoutException {
    Process.killPid(process.pid, ProcessSignal.sigkill);
    await process.exitCode;
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met within $timeout');
}

void main() {
  test('detects mpv from an explicit candidate list', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'nipaplay_mpv_detection_test_',
    );
    final fakeMpv = File('${tempDir.path}/mpv');
    await fakeMpv.writeAsString('fake mpv');
    addTearDown(() => tempDir.delete(recursive: true));

    final detected = await detectInstalledMpv(
      candidatePaths: [
        '${tempDir.path}/missing-mpv',
        fakeMpv.path,
      ],
    );

    expect(detected, fakeMpv.path);
  });

  test('uses the supplied process exit future for lifecycle monitoring',
      () async {
    final exitCode = Completer<int>();
    final session = _sessionFromProcessId(
      999999,
      mediaPath: '/tmp/test-video.mkv',
      ipcPath: null,
      duration: Duration.zero,
      processExitCode: exitCode.future,
      monitorProcess: true,
    );
    addTearDown(session.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(session.isClosed, isFalse);

    exitCode.complete(0);
    await _waitUntil(() => session.isClosed);
  });

  group('MpvSession progress', () {
    test('clamps its fraction to the valid range', () {
      final session = _sessionFromProcessId(
        1,
        position: const Duration(minutes: 25),
        duration: const Duration(minutes: 20),
      );

      expect(session.fraction, 1.0);
    });

    test('has no fraction when duration is unavailable', () {
      final session = _sessionFromProcessId(
        1,
        position: Duration.zero,
        duration: Duration.zero,
      );

      expect(session.fraction, isNull);
    });

    test('keeps process state separate from danmaku state', () {
      final session = _sessionFromProcessId(
        1,
        danmakuList: [
          DanmakuItem(
            danmakuId: 'later',
            content: 'later',
            time: const Duration(seconds: 3),
            colorRgb: 0xFFFFFF,
            mode: DanmakuMode.top,
          ),
          DanmakuItem(
            danmakuId: 'first',
            content: 'first',
            time: const Duration(seconds: 1),
            colorRgb: 0xFF0000,
            mode: DanmakuMode.scroll,
          ),
        ],
        danmakuAssSettings: const AssExportSettings(
          fontSize: 30,
          scrollDurationSeconds: 5,
        ),
      );

      expect(session.fraction, isNull);
    });
  });

  group(
    'ExternalPlayerConsoleService on Linux and macOS',
    () {
      test('only keeps the latest external player session', () async {
        final firstProcess = await _startPlayer();
        final secondProcess = await _startPlayer();
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
        });

        final initialTimestamp = ExternalPlayerConsoleService.stateTimestamp;
        _showSession(_session(firstProcess));
        final firstTimestamp = ExternalPlayerConsoleService.stateTimestamp;
        _showSession(_session(secondProcess));

        expect(firstTimestamp, greaterThan(initialTimestamp));
        expect(
          ExternalPlayerConsoleService.stateTimestamp,
          greaterThan(firstTimestamp),
        );
        expect(ExternalPlayerConsoleService.processId, secondProcess.pid);
        expect(ExternalPlayerConsoleService.duration, Duration.zero);
        expect(await firstProcess.exitCode, isNotNull);
      });

      test(
          'keeps media path in the session and playable metadata in the console service',
          () async {
        final process = await _startPlayer();
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        const episodeMetaData = EpisodeMetaData(
          animeTitle: '测试番剧',
          episodeTitle: '第 1 话',
          episodeId: 200,
        );

        _showSession(
          _session(process, mediaPath: '/video/test.mkv'),
          episodeMetaData: episodeMetaData,
        );

        expect(ExternalPlayerConsoleService.mediaPath, '/video/test.mkv');
        expect(ExternalPlayerConsoleService.animeTitle, '测试番剧');
        expect(ExternalPlayerConsoleService.episodeTitle, '第 1 话');
        expect(ExternalPlayerConsoleService.episodeId, 200);
      });

      test('calculates active danmaku in the console service', () async {
        final process = await _startPlayer();
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        final session = _session(
          process,
          position: const Duration(seconds: 3),
          danmakuList: [
            DanmakuItem(
              danmakuId: 'later',
              content: 'later',
              time: const Duration(seconds: 3),
              mode: DanmakuMode.top,
            ),
            DanmakuItem(
              danmakuId: 'first',
              content: 'first',
              time: const Duration(seconds: 1),
              mode: DanmakuMode.scroll,
            ),
          ],
          danmakuAssSettings: const AssExportSettings(
            fontSize: 30,
            scrollDurationSeconds: 5,
          ),
        );
        _showSession(session);

        expect(_activeDisplayIndices(), [0, 1]);
        final initialDisplayList =
            ExternalPlayerConsoleService.displayDanmakuList;
        ExternalPlayerConsoleService.danmakuStyle.danmakuOffset = 1;
        ExternalPlayerConsoleService.queueDanmakuRefresh();
        expect(ExternalPlayerConsoleService.displayDanmakuList,
            isNot(same(initialDisplayList)));
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.startTime),
          [const Duration(seconds: 2), const Duration(seconds: 4)],
        );
        ExternalPlayerConsoleService.danmakuStyle.danmakuOffset = 0;
        ExternalPlayerConsoleService.queueDanmakuRefresh();
        session.position = const Duration(seconds: 6);
        session.notifyListeners();
        expect(_activeDisplayIndices(), [0, 1]);
        session.position = const Duration(seconds: 8);
        session.notifyListeners();
        expect(_activeDisplayIndices(), [0]);
      });

      test('blocks danmaku by keyword, regex, and sender ID', () async {
        final process = await _startPlayer();
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        _showSession(_session(
          process,
          position: const Duration(seconds: 3),
          danmakuList: [
            DanmakuItem(
              content: 'Alpha comment',
              time: const Duration(seconds: 1),
              senderId: 'sender-one',
            ),
            DanmakuItem(
              content: 'Episode 123',
              time: const Duration(seconds: 2),
              senderId: 'sender-two',
            ),
            DanmakuItem(
              content: 'keep me',
              time: const Duration(seconds: 3),
              senderId: 'sender-three',
            ),
          ],
        ));

        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            'alpha',
            BlockedItemType.keyword,
          ),
          isTrue,
        );
        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            r'\d{3}$',
            BlockedItemType.regex,
          ),
          isTrue,
        );
        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            'sender-three',
            BlockedItemType.userId,
          ),
          isTrue,
        );
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.isBlocked),
          [true, true, true],
        );
        expect(_activeDisplayIndices(), isEmpty);
        expect(
          ExternalPlayerConsoleService.blockedItems.map((item) => item.type),
          [
            BlockedItemType.keyword,
            BlockedItemType.regex,
            BlockedItemType.userId
          ],
        );
        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            '[invalid',
            BlockedItemType.regex,
          ),
          isFalse,
        );

        final regexItem = ExternalPlayerConsoleService.blockedItems[1];
        ExternalPlayerConsoleService.removeBlockedItem(regexItem);
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.isBlocked),
          [true, false, true],
        );
        expect(_activeDisplayIndices(), [1]);
      });

      test('close hides the session and terminates the player', () async {
        final process = await _startPlayer();
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        _showSession(_session(process));

        ExternalPlayerConsoleService.closePlayerAndConsole();
        ExternalPlayerConsoleService.closePlayerAndConsole();

        expect(ExternalPlayerConsoleService.hasActiveSession, isFalse);
        expect(await process.exitCode, isNotNull);
      });

      test('publishes tab availability only while a session is active',
          () async {
        final process = await _startPlayer();
        final values = <bool>[];
        void listener() {
          values.add(ExternalPlayerConsoleService.sessionAvailability.value);
        }

        ExternalPlayerConsoleService.sessionAvailability.addListener(listener);
        addTearDown(() async {
          ExternalPlayerConsoleService.sessionAvailability
              .removeListener(listener);
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });

        _showSession(_session(process));
        ExternalPlayerConsoleService.closePlayerAndConsole();

        expect(values, <bool>[true, false]);
      });

      test('automatically clears the session after the player exits', () async {
        final process = await _startPlayer(duration: '0.05');
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        _showSession(_session(process));

        await _waitUntil(() => !ExternalPlayerConsoleService.hasActiveSession);
      });

      testWidgets('does not expose per-item visibility controls',
          (tester) async {
        final process = await tester.runAsync(_startPlayer);
        if (process == null) fail('Failed to start the test player process');
        try {
          _showSession(_session(
            process,
            danmakuList: [
              DanmakuItem.fromMap({
                'time': 1.0,
                'content': 'source test',
                'type': 'scroll',
                'color': 'rgb(255,255,255)',
                'p': '1.0,1,16777215,sender-hash',
                'cid': 'comment-id',
                'source': 'dandanplay',
              }),
              DanmakuItem(
                time: const Duration(seconds: 2),
                content: 'unblocked comment',
                danmakuId: 'unblocked-id',
                senderId: 'other-sender',
              ),
            ],
          ));
          expect(
            ExternalPlayerConsoleService.addBlockedItem(
              'sender-hash',
              BlockedItemType.userId,
            ),
            isTrue,
          );

          await tester.pumpWidget(const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ExternalPlayerConsolePage(),
          ));

          final modeSelector = find.byKey(
            const Key('external-player-danmaku-block-mode'),
          );
          expect(modeSelector, findsOneWidget);
          expect(find.text('关键词'), findsOneWidget);
          expect(find.text('正则表达式'), findsOneWidget);
          expect(find.text('发送者 ID'), findsWidgets);
          expect(ExternalPlayerConsoleService.blockedItems.single.type,
              BlockedItemType.userId);
          expect(ExternalPlayerConsoleService.blockedItems.single.value,
              'sender-hash');
          expect(
            find.byKey(const ValueKey(
              'external-player-danmaku-block-item-userId-sender-hash',
            )),
            findsOneWidget,
          );

          expect(find.textContaining('sender-hash'), findsWidgets);
          expect(find.textContaining('dandanplay'), findsNothing);
          expect(
            find.byKey(const ValueKey(
              'external-player-danmaku-visibility-0-comment-id',
            )),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey(
              'external-player-danmaku-blocked-0-comment-id',
            )),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey(
              'external-player-danmaku-blocked-1-unblocked-id',
            )),
            findsNothing,
          );
          expect(find.text('弹幕字体大小'), findsOneWidget);
          expect(
            find.byKey(const Key('external-player-danmaku-font-size')),
            findsOneWidget,
          );
          expect(find.text('弹幕描边粗细'), findsOneWidget);
          expect(find.text('启用弹幕描边'), findsNothing);
          expect(find.text('弹幕时间偏移'), findsOneWidget);
          expect(find.text('当前弹幕偏移量为 0 秒'), findsOneWidget);
          final advanceOffset = find.byKey(
            const Key('external-player-danmaku-offset-advance'),
          );
          await tester.ensureVisible(advanceOffset);
          await tester.tap(advanceOffset);
          await tester.pump();
          expect(ExternalPlayerConsoleService.danmakuStyle.danmakuOffset, -0.5);
          expect(find.text('当前弹幕提前出现 0.5 秒'), findsOneWidget);

          final offsetInput = find.byKey(
            const Key('external-player-danmaku-offset-input'),
          );
          await tester.ensureVisible(offsetInput);
          await tester.enterText(offsetInput, '1.25');
          final applyOffset = find.byKey(
            const Key('external-player-danmaku-offset-apply'),
          );
          await tester.ensureVisible(applyOffset);
          await tester.pumpAndSettle();
          await tester.tap(applyOffset);
          await tester.pump();
          expect(ExternalPlayerConsoleService.danmakuStyle.danmakuOffset, 1.25);
          expect(find.text('当前弹幕延后出现 1.25 秒'), findsOneWidget);

          final resetOffset = find.byKey(
            const Key('external-player-danmaku-offset-reset'),
          );
          await tester.ensureVisible(resetOffset);
          await tester.tap(resetOffset);
          await tester.pump();
          expect(ExternalPlayerConsoleService.danmakuStyle.danmakuOffset, 0.0);
          expect(find.text('当前弹幕偏移量为 0 秒'), findsOneWidget);
          expect(
            find.byKey(const Key('external-player-timestamp-input')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('external-player-timestamp-seek')),
            findsOneWidget,
          );
        } finally {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          Process.killPid(process.pid, ProcessSignal.sigkill);
        }
      });

      testWidgets('uses a two-column workspace on desktop widths',
          (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final process = await tester.runAsync(_startPlayer);
        if (process == null) fail('Failed to start the test player process');
        try {
          _showSession(_session(
            process,
            danmakuList: [
              DanmakuItem(
                time: const Duration(seconds: 1),
                content: 'desktop layout comment',
              ),
            ],
          ));
          await tester.pumpWidget(const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ExternalPlayerConsolePage(),
          ));

          expect(
            find.byKey(const Key('external-player-console-two-column')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('external-player-console-single-column')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          Process.killPid(process.pid, ProcessSignal.sigkill);
        }
      });

      test('reads playback progress through mpv JSON IPC', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        var positionSeconds = 0.0;
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            final requestId = request['request_id'];
            client.writeln(jsonEncode({
              'data': requestId == 1
                  ? positionSeconds
                  : requestId == 2
                      ? 1500.0
                      : false,
              'error': 'success',
              'request_id': requestId,
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        _showSession(_session(
          process,
          ipcPath: socketPath,
          pollPlaybackState: true,
        ));
        expect(ExternalPlayerConsoleService.duration, Duration.zero);

        await _waitUntil(
          () =>
              ExternalPlayerConsoleService.duration ==
              const Duration(minutes: 25),
        );
        expect(ExternalPlayerConsoleService.position, Duration.zero);

        positionSeconds = 75.5;
        await _waitUntil(
          () => ExternalPlayerConsoleService.position != Duration.zero,
        );

        expect(
          ExternalPlayerConsoleService.position,
          const Duration(seconds: 75, milliseconds: 500),
        );
        expect(
          ExternalPlayerConsoleService.duration,
          const Duration(minutes: 25),
        );
        expect(ExternalPlayerConsoleService.fraction, closeTo(0.0503, 0.0001));
        expect(ExternalPlayerConsoleService.isPaused, isFalse);
      });

      test('toggles mpv pause state through JSON IPC', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final commands = <bool>[];
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            final command = request['command'] as List<dynamic>;
            if (command.first == 'set_property' && command[1] == 'pause') {
              commands.add(command[2] as bool);
            }
            client.writeln(jsonEncode({
              'data': null,
              'error': 'success',
              'request_id': request['request_id'],
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        _showSession(
          _session(process, ipcPath: socketPath),
        );

        ExternalPlayerConsoleService.togglePause();
        await _waitUntil(
          () =>
              commands.length == 1 &&
              ExternalPlayerConsoleService.isPaused == true,
        );
        ExternalPlayerConsoleService.togglePause();
        await _waitUntil(
          () =>
              commands.length == 2 &&
              ExternalPlayerConsoleService.isPaused == false,
        );

        expect(commands, <bool>[true, false]);
        expect(ExternalPlayerConsoleService.isPaused, isFalse);
      });

      test('seeks mpv through JSON IPC', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final commands = <List<dynamic>>[];
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            final command = request['command'] as List<dynamic>;
            if (command.first == 'seek') {
              commands.add(command);
            }
            client.writeln(jsonEncode({
              'data': null,
              'error': 'success',
              'request_id': request['request_id'],
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        _showSession(_session(
          process,
          ipcPath: socketPath,
          duration: const Duration(minutes: 20),
          position: const Duration(minutes: 2),
          danmakuList: [
            DanmakuItem(
              danmakuId: 'seek-target',
              content: 'seek target',
              time: const Duration(minutes: 12),
              colorRgb: 0xFFFFFF,
              mode: DanmakuMode.scroll,
            ),
          ],
          danmakuAssSettings: const AssExportSettings(
            fontSize: 30,
            scrollDurationSeconds: 60,
          ),
        ));

        ExternalPlayerConsoleService.seekToFraction(0.625);
        await _waitUntil(() => commands.isNotEmpty);

        expect(
          ExternalPlayerConsoleService.position,
          const Duration(minutes: 12, seconds: 30),
        );
        expect(commands, <List<dynamic>>[
          <dynamic>['seek', 750.0, 'absolute+exact'],
        ]);
        expect(_activeDisplayIndices(), isEmpty);

        expect(
          ExternalPlayerConsoleService.seekToTimestamp('12:34.567'),
          isTrue,
        );
        await _waitUntil(() => commands.length == 2);
        expect(
          ExternalPlayerConsoleService.position,
          const Duration(minutes: 12, seconds: 34, milliseconds: 567),
        );
        expect(
          commands.last,
          <dynamic>['seek', 754.567, 'absolute+exact'],
        );

        expect(
          ExternalPlayerConsoleService.seekToTimestamp('invalid'),
          isFalse,
        );
        expect(commands.length, 2);
      });

      test('coalesces rapid danmaku opacity updates without truncating ASS',
          () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final assFile = File('${tempDir.path}/danmaku.ass');
        await assFile.writeAsString('[Script Info]\nstale ASS\n');
        final reloadCommands = <List<dynamic>>[];
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            final command = request['command'] as List<dynamic>;
            if (command.first == 'script-message-to') {
              reloadCommands.add(command);
            }
            client.writeln(jsonEncode({
              'data': null,
              'error': 'success',
              'request_id': request['request_id'],
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        final session = _session(
          process,
          ipcPath: socketPath,
          danmakuAssPath: assFile.path,
          danmakuOpacity: 0.8,
          danmakuList: [
            DanmakuItem(
              time: const Duration(seconds: 1),
              content: 'first regenerated comment',
            ),
            DanmakuItem(
              time: const Duration(seconds: 12),
              content: 'second regenerated comment',
            ),
          ],
          danmakuAssSettings: const AssExportSettings(
            fontSize: 30,
            opacity: 0.8,
          ),
        );
        _showSession(session);

        expect(ExternalPlayerConsoleService.danmakuStyle.opacity, 0.8);

        final initialTimestamp = ExternalPlayerConsoleService.stateTimestamp;
        for (final opacity in <double>[0.1, 0.2, 0.3, 0.4, 0.5]) {
          ExternalPlayerConsoleService.danmakuStyle.opacity = opacity;
          ExternalPlayerConsoleService.queueDanmakuRefresh();
        }
        await _waitUntil(
          () => reloadCommands.isNotEmpty,
        );

        expect(ExternalPlayerConsoleService.danmakuStyle.opacity, 0.5);
        expect(
          ExternalPlayerConsoleService.stateTimestamp,
          greaterThan(initialTimestamp),
        );
        final updatedAss = await assFile.readAsString();
        final opacityTags = RegExp(r'\\alpha&H[0-9A-Fa-f]{2}&')
            .allMatches(updatedAss)
            .map((match) => match.group(0))
            .toList();
        expect(updatedAss, isNotEmpty);
        expect(updatedAss.startsWith('[Script Info]\n'), isTrue);
        expect(updatedAss, contains('first regenerated comment'));
        expect(updatedAss, contains('second regenerated comment'));
        expect(opacityTags, isNotEmpty);
        expect(opacityTags, everyElement(r'\alpha&H80&'));
        expect(File('${assFile.path}.nipaplay.tmp').existsSync(), isFalse);
        expect(reloadCommands, <List<dynamic>>[
          <dynamic>[
            'script-message-to',
            'danmaku.ass',
            'nipaplay-danmaku-reload',
            assFile.path,
          ],
        ]);

        final secondItem =
            ExternalPlayerConsoleService.displayDanmakuList[1].item;
        final keywordTimestamp = ExternalPlayerConsoleService.stateTimestamp;
        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            'SECOND',
            BlockedItemType.keyword,
          ),
          isTrue,
        );
        final addedKeywordTimestamp =
            ExternalPlayerConsoleService.stateTimestamp;
        expect(addedKeywordTimestamp, greaterThan(keywordTimestamp));
        expect(
          ExternalPlayerConsoleService.addBlockedItem(
            'second',
            BlockedItemType.keyword,
          ),
          isFalse,
        );
        expect(
          ExternalPlayerConsoleService.stateTimestamp,
          addedKeywordTimestamp,
        );
        await _waitUntil(() => reloadCommands.length == 2);

        final filteredAss = await assFile.readAsString();
        expect(ExternalPlayerConsoleService.blockedItems, hasLength(1));
        expect(
            ExternalPlayerConsoleService.blockedItems.single.value, 'SECOND');
        expect(ExternalPlayerConsoleService.blockedItems.single.type,
            BlockedItemType.keyword);
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.item.content),
          ['first regenerated comment', 'second regenerated comment'],
        );
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.isBlocked),
          [false, true],
        );
        expect(
          identical(ExternalPlayerConsoleService.displayDanmakuList[1].item,
              secondItem),
          isTrue,
        );
        expect(filteredAss, contains('first regenerated comment'));
        expect(filteredAss, isNot(contains('second regenerated comment')));

        ExternalPlayerConsoleService.removeBlockedItem(
          ExternalPlayerConsoleService.blockedItems.single,
        );
        expect(
          ExternalPlayerConsoleService.stateTimestamp,
          greaterThan(addedKeywordTimestamp),
        );
        await _waitUntil(() => reloadCommands.length == 3);
        expect(ExternalPlayerConsoleService.blockedItems, isEmpty);
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.item.content),
          ['first regenerated comment', 'second regenerated comment'],
        );
        expect(
          ExternalPlayerConsoleService.displayDanmakuList
              .map((item) => item.isBlocked),
          [false, false],
        );
        expect(
          identical(ExternalPlayerConsoleService.displayDanmakuList[1].item,
              secondItem),
          isTrue,
        );
        expect(
          await assFile.readAsString(),
          contains('second regenerated comment'),
        );
      });

      test('adjusts danmaku font size and outline width', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final assFile = File('${tempDir.path}/danmaku.ass');
        const stylePrefix = 'Style: Danmaku,Arial,48.0,&H00FFFFFF,&H00FFFFFF,'
            '&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,';
        await assFile.writeAsString(
          '[V4+ Styles]\n$stylePrefix' '2.5,0.0,2,0,0,0,1\n',
        );
        final reloadCommands = <List<dynamic>>[];
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            reloadCommands.add(request['command'] as List<dynamic>);
            client.writeln(jsonEncode({
              'data': null,
              'error': 'success',
              'request_id': request['request_id'],
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        final session = _session(
          process,
          ipcPath: socketPath,
          danmakuAssPath: assFile.path,
          danmakuOutlineWidth: 2.5,
          danmakuList: [
            DanmakuItem(
              time: const Duration(seconds: 1),
              content: 'outline regenerated comment',
            ),
          ],
          danmakuAssSettings: const AssExportSettings(
            fontSize: 30,
            fontFamily: 'Arial',
            outlineStyle: AssOutlineStyle.stroke,
            outlineWidth: 2.5,
            timeOffsetSeconds: 1.5,
          ),
        );
        _showSession(session);

        expect(ExternalPlayerConsoleService.danmakuStyle.danmakuFontSize, 30.0);
        expect(ExternalPlayerConsoleService.danmakuStyle.danmakuOffset, 1.5);
        expect(ExternalPlayerConsoleService.danmakuStyle.outlineWidth, 2.5);

        ExternalPlayerConsoleService.danmakuStyle.danmakuFontSize = 42.0;
        ExternalPlayerConsoleService.queueDanmakuRefresh();
        await _waitUntil(() => reloadCommands.length == 1);
        expect(ExternalPlayerConsoleService.danmakuStyle.danmakuFontSize, 42.0);
        expect(
          await assFile.readAsString(),
          contains('Style: Danmaku,Microsoft YaHei,67.2,'),
        );
        expect(await assFile.readAsString(), contains('0:00:02.50'));

        ExternalPlayerConsoleService.danmakuStyle.outlineWidth = 4.0;
        ExternalPlayerConsoleService.queueDanmakuRefresh();
        await _waitUntil(() => reloadCommands.length == 2);
        expect(ExternalPlayerConsoleService.danmakuStyle.outlineWidth, 4.0);
        expect(await assFile.readAsString(), contains('6.0,0.0'));

        ExternalPlayerConsoleService.danmakuStyle.outlineWidth = 0.0;
        ExternalPlayerConsoleService.queueDanmakuRefresh();
        await _waitUntil(() => reloadCommands.length == 3);
        expect(ExternalPlayerConsoleService.danmakuStyle.outlineWidth, 0.0);
        expect(await assFile.readAsString(), contains('0.0,0.0'));
        expect(File('${assFile.path}.nipaplay.tmp').existsSync(), isFalse);
      });

      test('replacing a session clears the previous progress', () async {
        final firstProcess = await _startPlayer();
        final secondProcess = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final server = await ServerSocket.bind(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        server.listen((client) {
          client
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
            final request = jsonDecode(line) as Map<String, dynamic>;
            final requestId = request['request_id'];
            client.writeln(jsonEncode({
              'data': requestId == 1
                  ? 60.0
                  : requestId == 2
                      ? 1200.0
                      : false,
              'error': 'success',
              'request_id': requestId,
            }));
          });
        });
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
          await tempDir.delete(recursive: true);
        });
        _showSession(_session(
          firstProcess,
          ipcPath: socketPath,
          duration: const Duration(minutes: 20),
          pollPlaybackState: true,
        ));
        await _waitUntil(
          () => ExternalPlayerConsoleService.position != Duration.zero,
        );

        _showSession(_session(secondProcess));

        expect(ExternalPlayerConsoleService.processId, secondProcess.pid);
        expect(ExternalPlayerConsoleService.position, Duration.zero);
        expect(ExternalPlayerConsoleService.duration, Duration.zero);
      });
    },
    skip: !(Platform.isLinux || Platform.isMacOS),
  );
}
