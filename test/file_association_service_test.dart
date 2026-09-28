import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/file_association_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('file_association_channel');
  const codec = StandardMethodCodec();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('video extension matching requires the entire extension', () {
    expect(FileAssociationService.isSupportedVideoFile('/Videos/movie.MP4'),
        isTrue);
    expect(FileAssociationService.isSupportedVideoFile('/Videos/movie.mkv'),
        isTrue);
    expect(FileAssociationService.isSupportedVideoFile('/Videos/movie.4'),
        isFalse);
    expect(FileAssociationService.isSupportedVideoFile('/Videos/movie.npb'),
        isFalse);
  });

  test('iOS cold and warm opens drain native file and error queues', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final pendingFiles = Queue<String>.of([
      '/local/cold.mp4',
      '/local/before-listener.mkv',
    ]);
    final pendingErrors = Queue<String>.of(['无法打开文件：bad.mov']);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      switch (call.method) {
        case 'getOpenFileUri':
          return pendingFiles.isEmpty ? null : pendingFiles.removeFirst();
        case 'getOpenFileError':
          return pendingErrors.isEmpty ? null : pendingErrors.removeFirst();
        default:
          fail('Unexpected native method: ${call.method}');
      }
    });

    expect(await FileAssociationService.getOpenFileUri(), '/local/cold.mp4');
    final openedFiles = <String>[];
    final openErrors = <String>[];
    final fileSubscription =
        FileAssociationService.openFileStream.listen(openedFiles.add);
    final errorSubscription =
        FileAssociationService.openFileErrorStream.listen(openErrors.add);
    addTearDown(fileSubscription.cancel);
    addTearDown(errorSubscription.cancel);
    await pumpEventQueue();
    expect(openedFiles, ['/local/before-listener.mkv']);
    expect(openErrors, ['无法打开文件：bad.mov']);

    pendingFiles.add('/local/warm.avi');
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onOpenFileUri')),
      null,
    );
    await pumpEventQueue();
    expect(openedFiles, ['/local/before-listener.mkv', '/local/warm.avi']);
    expect(pendingFiles, isEmpty);

    pendingErrors.add('无法打开文件：missing.mp4');
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onOpenFileError')),
      null,
    );
    await pumpEventQueue();
    expect(openErrors, ['无法打开文件：bad.mov', '无法打开文件：missing.mp4']);
  });

  test('iOS open signal during a drain is not lost', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final firstResult = Completer<String?>();
    final pendingFiles = Queue<String>();
    var firstRequest = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method != 'getOpenFileUri') return null;
      if (firstRequest) {
        firstRequest = false;
        return firstResult.future;
      }
      return pendingFiles.isEmpty ? null : pendingFiles.removeFirst();
    });

    final openedFiles = <String>[];
    final subscription =
        FileAssociationService.openFileStream.listen(openedFiles.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    pendingFiles.add('/local/raced.mp4');
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('onOpenFileUri')),
      null,
    );
    firstResult.complete(null);
    await pumpEventQueue();
    expect(openedFiles, ['/local/raced.mp4']);
  });
}
