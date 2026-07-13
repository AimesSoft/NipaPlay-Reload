import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/external_player_session.dart';
import 'package:nipaplay/services/external_player_console_service.dart';

ExternalPlayerSession _session(Process process, {String? ipcPath}) {
  return ExternalPlayerSession(
    playerPath: '/bin/mpv',
    mediaPath: '/video/${process.pid}.mkv',
    processId: process.pid,
    animeTitle: '测试番剧',
    episodeTitle: '第 1 话',
    episodeId: 12345,
    ipcPath: ipcPath,
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
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met within $timeout');
}

void main() {
  group('ExternalPlayerPlaybackProgress', () {
    test('clamps its fraction to the valid range', () {
      const progress = ExternalPlayerPlaybackProgress(
        position: Duration(minutes: 25),
        duration: Duration(minutes: 20),
      );

      expect(progress.fraction, 1.0);
    });

    test('has no fraction when duration is unavailable', () {
      const progress = ExternalPlayerPlaybackProgress(
        position: Duration.zero,
        duration: Duration.zero,
      );

      expect(progress.fraction, isNull);
    });
  });

  group(
    'ExternalPlayerConsoleService on Linux',
    () {
      test('only keeps the latest external player session', () async {
        final firstProcess = await _startPlayer();
        final secondProcess = await _startPlayer();
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(days: 1),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
        });

        service.showSession(_session(firstProcess));
        service.showSession(_session(secondProcess));

        expect(service.session?.processId, secondProcess.pid);
        expect(service.progress, isNull);
        expect(await firstProcess.exitCode, isNotNull);
      });

      test('close hides the session and terminates the player', () async {
        final process = await _startPlayer();
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(days: 1),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await _stopProcess(process);
        });
        service.showSession(_session(process));

        service.closePlayerAndConsole();
        service.closePlayerAndConsole();

        expect(service.session, isNull);
        expect(service.progress, isNull);
        expect(await process.exitCode, isNotNull);
      });

      test('automatically clears the session after the player exits', () async {
        final process = await _startPlayer(duration: '0.05');
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(milliseconds: 10),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await _stopProcess(process);
        });
        service.showSession(_session(process));

        await _waitUntil(() => service.session == null);

        expect(service.progress, isNull);
      });

      test('reads playback progress through mpv JSON IPC', () async {
        final process = await _startPlayer();
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
                  ? 75.5
                  : requestId == 2
                      ? 1500.0
                      : false,
              'error': 'success',
              'request_id': requestId,
            }));
          });
        });
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(milliseconds: 10),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        service.showSession(_session(process, ipcPath: socketPath));

        await _waitUntil(() => service.progress != null);

        expect(
          service.progress?.position,
          const Duration(seconds: 75, milliseconds: 500),
        );
        expect(service.progress?.duration, const Duration(minutes: 25));
        expect(service.progress?.fraction, closeTo(0.0503, 0.0001));
        expect(service.isPaused, isFalse);
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
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(days: 1),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await server.close();
          await _stopProcess(process);
          await tempDir.delete(recursive: true);
        });
        service.showSession(_session(process, ipcPath: socketPath));

        await service.togglePause();
        await service.togglePause();

        expect(commands, <bool>[true, false]);
        expect(service.isPaused, isFalse);
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
        final service = ExternalPlayerConsoleService(
          monitorInterval: const Duration(milliseconds: 10),
        );
        addTearDown(() async {
          service.closePlayerAndConsole();
          service.dispose();
          await server.close();
          await _stopProcess(firstProcess);
          await _stopProcess(secondProcess);
          await tempDir.delete(recursive: true);
        });
        service.showSession(_session(firstProcess, ipcPath: socketPath));
        await _waitUntil(() => service.progress != null);

        service.showSession(_session(secondProcess));

        expect(service.session?.processId, secondProcess.pid);
        expect(service.progress, isNull);
      });
    },
    skip: !Platform.isLinux,
  );
}
