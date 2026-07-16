import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/models/external_player_danmaku_item.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/pages/external_player_console_page.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

ExternalPlayerSession _session(
  Process process, {
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  double danmakuOutlineWidth = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
  List<ExternalPlayerDanmakuItem> danmakuItems = const [],
}) {
  return _sessionFromProcessId(
    process.pid,
    ipcPath: ipcPath,
    danmakuAssPath: danmakuAssPath,
    danmakuOpacity: danmakuOpacity,
    danmakuOutlineWidth: danmakuOutlineWidth,
    position: position,
    duration: duration,
    isPaused: isPaused,
    danmakuItems: danmakuItems,
  );
}

ExternalPlayerSession _sessionFromProcessId(
  int processId, {
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  double danmakuOutlineWidth = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
  List<ExternalPlayerDanmakuItem> danmakuItems = const [],
}) {
  final mediaPath = '/video/$processId.mkv';
  final playableItem = PlayableItem(
    videoPath: mediaPath,
    title: '测试番剧',
    subtitle: '第 1 话',
    episodeId: 12345,
  );
  return ExternalPlayerSession(
    ExternalPlayerType.mpv,
    '/bin/mpv',
    processId,
    ipcPath,
    duration,
    danmakuAssPath,
    playableItem,
    danmakuItems: danmakuItems,
  )..initialize(
      danmakuOpacity: danmakuOpacity,
      danmakuOutlineWidth: danmakuOutlineWidth,
      position: position,
      isPaused: isPaused,
    );
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
  group('ExternalPlayerSession progress', () {
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

    test('finds every danmaku active at an interval boundary', () {
      final session = _sessionFromProcessId(
        1,
        danmakuItems: const [
          ExternalPlayerDanmakuItem(
            id: 'later',
            content: 'later',
            startTime: Duration(seconds: 3),
            endTime: Duration(seconds: 8),
            colorRgb: 0xFFFFFF,
            type: ExternalPlayerDanmakuType.top,
          ),
          ExternalPlayerDanmakuItem(
            id: 'first',
            content: 'first',
            startTime: Duration(seconds: 1),
            endTime: Duration(seconds: 6),
            colorRgb: 0xFF0000,
            type: ExternalPlayerDanmakuType.scroll,
          ),
        ],
      );

      expect(session.danmakuItems.map((item) => item.id), ['first', 'later']);
      expect(session.activeDanmakuIndicesAt(const Duration(seconds: 3)), [0, 1]);
      expect(session.activeDanmakuIndicesAt(const Duration(seconds: 6)), [1]);
      expect(session.activeDanmakuIndicesAt(const Duration(seconds: 8)), isEmpty);
    });
  });

  group(
    'ExternalPlayerConsoleService on Linux',
    () {
      test('only keeps the latest external player session', () async {
        final firstProcess = await _startPlayer();
        final secondProcess = await _startPlayer();
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
        });

        ExternalPlayerConsoleService.showSession(_session(firstProcess));
        ExternalPlayerConsoleService.showSession(_session(secondProcess));

        expect(service.session?.processId, secondProcess.pid);
        expect(service.session?.duration, Duration.zero);
        expect(await firstProcess.exitCode, isNotNull);
      });

      test('close hides the session and terminates the player', () async {
        final process = await _startPlayer();
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        ExternalPlayerConsoleService.showSession(_session(process));

        ExternalPlayerConsoleService.closePlayerAndConsole();
        ExternalPlayerConsoleService.closePlayerAndConsole();

        expect(service.session, isNull);
        expect(await process.exitCode, isNotNull);
      });

      test('automatically clears the session after the player exits', () async {
        final process = await _startPlayer(duration: '0.05');
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await _stopProcess(process);
        });
        ExternalPlayerConsoleService.showSession(_session(process));

        await _waitUntil(() => service.session == null);
      });

      testWidgets('does not show danmaku sources in the list', (tester) async {
        final process = await tester.runAsync(_startPlayer);
        if (process == null) fail('Failed to start the test player process');
        try {
          ExternalPlayerConsoleService.showSession(_session(
            process,
            danmakuItems: const [
              ExternalPlayerDanmakuItem(
                id: 'source-visible',
                content: 'source test',
                startTime: Duration(seconds: 1),
                endTime: Duration(seconds: 6),
                colorRgb: 0xFFFFFF,
                type: ExternalPlayerDanmakuType.scroll,
                source: 'bilibili',
              ),
            ],
          ));

          await tester.pumpWidget(const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ExternalPlayerConsolePage(),
          ));

          expect(find.textContaining('bilibili'), findsNothing);
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
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(_session(
          process,
          ipcPath: socketPath,
        ));
        expect(service.session?.duration, Duration.zero);

        await _waitUntil(
          () => service.session?.duration == const Duration(minutes: 25),
        );
        expect(service.session?.position, Duration.zero);

        positionSeconds = 75.5;
        await _waitUntil(
          () => service.session?.position != Duration.zero,
        );

        expect(
          service.session?.position,
          const Duration(seconds: 75, milliseconds: 500),
        );
        expect(
          service.session?.duration,
          const Duration(minutes: 25),
        );
        expect(service.session?.fraction, closeTo(0.0503, 0.0001));
        expect(service.session?.isPaused, isFalse);
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
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(
          _session(process, ipcPath: socketPath),
        );

        ExternalPlayerConsoleService.togglePause();
        await _waitUntil(
          () => commands.length == 1 && service.session?.isPaused == true,
        );
        ExternalPlayerConsoleService.togglePause();
        await _waitUntil(
          () => commands.length == 2 && service.session?.isPaused == false,
        );

        expect(commands, <bool>[true, false]);
        expect(service.session?.isPaused, isFalse);
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
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(_session(
          process,
          ipcPath: socketPath,
          duration: const Duration(minutes: 20),
          position: const Duration(minutes: 2),
          danmakuItems: const [
            ExternalPlayerDanmakuItem(
              id: 'seek-target',
              content: 'seek target',
              startTime: Duration(minutes: 12),
              endTime: Duration(minutes: 13),
              colorRgb: 0xFFFFFF,
              type: ExternalPlayerDanmakuType.scroll,
            ),
          ],
        ));

        ExternalPlayerConsoleService.seekToFraction(0.625);
        await _waitUntil(() => commands.isNotEmpty);

        expect(
          service.session?.position,
          const Duration(minutes: 12, seconds: 30),
        );
        expect(commands, <List<dynamic>>[
          <dynamic>['seek', 750.0, 'absolute+exact'],
        ]);
        expect(service.activeDanmakuItems.map((item) => item.id), ['seek-target']);
      });

      test('coalesces rapid danmaku opacity updates without truncating ASS', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final assFile = File('${tempDir.path}/danmaku.ass');
        final dialogueLines = List<String>.generate(
          2000,
          (index) => 'Dialogue: 0,{\\1a&H33&}test $index',
        );
        final originalAss = '[Script Info]\n${dialogueLines.join('\n')}\n';
        await assFile.writeAsString(originalAss);
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
            if (command.first == 'script-message') {
              reloadCommands.add(command);
            }
            client.writeln(jsonEncode({
              'data': null,
              'error': 'success',
              'request_id': request['request_id'],
            }));
          });
        });
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(_session(
          process,
          ipcPath: socketPath,
          danmakuAssPath: assFile.path,
          danmakuOpacity: 0.8,
        ));

        expect(service.session?.danmakuOpacity, 0.8);
        expect(service.supportsDanmakuOpacity, isTrue);

        for (final opacity in <double>[0.1, 0.2, 0.3, 0.4, 0.5]) {
          ExternalPlayerConsoleService.setDanmakuOpacity(opacity);
        }
        await _waitUntil(
          () => reloadCommands.isNotEmpty,
        );

        expect(service.session?.danmakuOpacity, 0.5);
        final updatedAss = await assFile.readAsString();
        final opacityTags = RegExp(r'\\1a&H[0-9A-Fa-f]{2}&')
            .allMatches(updatedAss)
            .map((match) => match.group(0))
            .toList();
        expect(updatedAss, isNotEmpty);
        expect(updatedAss.startsWith('[Script Info]\n'), isTrue);
        expect(updatedAss.split('\n').length, originalAss.split('\n').length);
        expect(opacityTags.length, dialogueLines.length);
        expect(opacityTags, everyElement(r'\1a&H80&'));
        expect(File('${assFile.path}.nipaplay.tmp').existsSync(), isFalse);
        expect(reloadCommands, <List<dynamic>>[
          <dynamic>['script-message', 'nipaplay-danmaku-reload'],
        ]);
      });

      test('toggles danmaku outline and restores its width', () async {
        final process = await _startPlayer();
        final tempDir =
            await Directory.systemTemp.createTemp('nipaplay_ipc_test_');
        final socketPath = '${tempDir.path}/mpv.sock';
        final assFile = File('${tempDir.path}/danmaku.ass');
        const stylePrefix =
            'Style: Danmaku,Arial,48.0,&H00FFFFFF,&H00FFFFFF,'
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
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(_session(
          process,
          ipcPath: socketPath,
          danmakuAssPath: assFile.path,
          danmakuOutlineWidth: 2.5,
        ));

        expect(service.supportsDanmakuOutline, isTrue);
        expect(service.session?.danmakuOutlineEnabled, isTrue);

        ExternalPlayerConsoleService.setDanmakuOutlineEnabled(false);
        await _waitUntil(() => reloadCommands.length == 1);
        expect(service.session?.danmakuOutlineEnabled, isFalse);
        expect(await assFile.readAsString(), contains('$stylePrefix' '0.0,0.0'));

        ExternalPlayerConsoleService.setDanmakuOutlineEnabled(true);
        await _waitUntil(() => reloadCommands.length == 2);
        expect(service.session?.danmakuOutlineEnabled, isTrue);
        expect(await assFile.readAsString(), contains('$stylePrefix' '2.5,0.0'));
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
        final service = ExternalPlayerConsoleService.instance;
        addTearDown(() async {
          ExternalPlayerConsoleService.closePlayerAndConsole();
          await server.close();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
          await tempDir.delete(recursive: true);
        });
        ExternalPlayerConsoleService.showSession(_session(
          firstProcess,
          ipcPath: socketPath,
          duration: const Duration(minutes: 20),
        ));
        await _waitUntil(
          () => service.session?.position != Duration.zero,
        );

        ExternalPlayerConsoleService.showSession(_session(secondProcess));

        expect(service.session?.processId, secondProcess.pid);
        expect(service.session?.position, Duration.zero);
        expect(service.session?.duration, Duration.zero);
      });
    },
    skip: !Platform.isLinux,
  );
}
