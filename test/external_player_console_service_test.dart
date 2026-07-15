import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

ExternalPlayerSession _session(
  Process process, {
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
}) {
  return _sessionFromProcessId(
    process.pid,
    ipcPath: ipcPath,
    danmakuAssPath: danmakuAssPath,
    danmakuOpacity: danmakuOpacity,
    position: position,
    duration: duration,
    isPaused: isPaused,
  );
}

ExternalPlayerSession _sessionFromProcessId(
  int processId, {
  String? ipcPath,
  String? danmakuAssPath,
  double danmakuOpacity = 1.0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
  bool isPaused = false,
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
  )..initialize(
      danmakuOpacity: danmakuOpacity,
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
