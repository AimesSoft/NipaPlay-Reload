import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nipaplay/services/harmony_local_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const importChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.importMediaFiles',
    StandardMessageCodec(),
  );
  const restoreChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.restoreDirectoryPermissions',
    StandardMessageCodec(),
  );
  const accessChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.ensureDirectoryAccess',
    StandardMessageCodec(),
  );
  const directoryChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.pickMediaDirectory',
    StandardMessageCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockDecodedMessageHandler<Object?>(importChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(restoreChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(accessChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(directoryChannel, null);
  });

  test(
      'media picker cancellation and unsupported directory errors remain distinct',
      () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        directoryChannel, (_) async => [null]);
    expect(await HarmonyLocalMediaService.pickMediaDirectory(), isNull);
    messenger.setMockDecodedMessageHandler<Object?>(directoryChannel,
        (_) async => ['directory-selection-unsupported', '请选择视频导入', null]);
    await expectLater(
        HarmonyLocalMediaService.pickMediaDirectory(),
        throwsA(isA<PlatformException>().having(
            HarmonyLocalMediaService.canOfferImport, 'offers import', isTrue)));
    expect(
        HarmonyLocalMediaService.canOfferImport(
            PlatformException(code: 'channel-error')),
        isFalse);
  });

  test('access restoration preserves the path and surfaces revoked grants',
      () async {
    messenger.setMockDecodedMessageHandler<Object?>(accessChannel,
        (args) async {
      expect(args, ['/Movies/番剧 100%']);
      return ['directory-access-denied', '请重新授权', null];
    });
    await expectLater(
        HarmonyLocalMediaService.ensureDirectoryAccess('/Movies/番剧 100%'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'directory-access-denied')));
  });

  test('native cancellation does not create an import result', () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        importChannel, (_) async => [null]);
    expect(await HarmonyLocalMediaService.importMediaFiles(), isNull);
  });

  test('partial import preserves the successful directory and failure count',
      () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        importChannel,
        (_) async => [
              {
                'directory': '/app/files/ImportedMedia',
                'importedCount': 2,
                'failedCount': 1
              },
            ]);
    final result = await HarmonyLocalMediaService.importMediaFiles();
    expect(result!.directory, '/app/files/ImportedMedia');
    expect(result.importedCount, 2);
    expect(result.failedCount, 1);
  });

  test('native failure remains an error rather than cancellation', () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        importChannel, (_) async => ['media-import-failed', '空间不足', null]);
    await expectLater(
        HarmonyLocalMediaService.importMediaFiles(),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'media-import-failed')));
  });

  test('missing native registration is reported', () async {
    await expectLater(
        HarmonyLocalMediaService.importMediaFiles(),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'channel-error')));
  });

  test('restoration exposes inaccessible grants', () async {
    messenger.setMockDecodedMessageHandler<Object?>(
        restoreChannel,
        (_) async => [
              ['file://docs/revoked']
            ]);
    expect(await HarmonyLocalMediaService.restoreDirectoryPermissions(),
        ['file://docs/revoked']);
  });

  test(
      'read validation leaves an empty source untouched and rejects missing paths and URIs',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('nipaplay-media-access-');
    addTearDown(() => directory.delete(recursive: true));
    expect(await HarmonyLocalMediaService.canReadDirectory(directory.path),
        isTrue);
    expect(await directory.list().toList(), isEmpty);
    expect(
        await HarmonyLocalMediaService.canReadDirectory(
            '${directory.path}/missing'),
        isFalse);
    expect(await Directory('${directory.path}/missing').exists(), isFalse);
    expect(
        await HarmonyLocalMediaService.canReadDirectory('file://docs/Movies'),
        isFalse);
  });
}
