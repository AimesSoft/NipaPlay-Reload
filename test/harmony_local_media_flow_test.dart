import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/media_library/pick_local_media_directory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const directoryChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.pickMediaDirectory',
    StandardMessageCodec(),
  );
  const importChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.FileSelectorApi.importMediaFiles',
    StandardMessageCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockDecodedMessageHandler<Object?>(
        directoryChannel,
        (_) async => [
              'directory-selection-unsupported',
              '当前设备不支持直接选择文件夹。',
              null,
            ]);
  });
  tearDown(() {
    messenger.setMockDecodedMessageHandler<Object?>(directoryChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(importChannel, null);
  });

  Future<void> mount(WidgetTester tester, Completer<String?> result) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppearanceSettingsProvider(),
      child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            try {
              result.complete(await pickHarmonyLocalMediaDirectory(context));
            } catch (error, stack) {
              result.completeError(error, stack);
            }
          },
          child: const Text('添加媒体'),
        );
      }))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加媒体'));
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported device explains storage usage before importing',
      (tester) async {
    var importCalls = 0;
    messenger.setMockDecodedMessageHandler<Object?>(importChannel, (_) async {
      importCalls++;
      return [null];
    });
    final result = Completer<String?>();
    await mount(tester, result);
    expect(find.textContaining('额外占用存储空间'), findsOneWidget);
    expect(importCalls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result.future, isNull);
    expect(importCalls, 0);
    expect(find.text('添加媒体'), findsOneWidget);
  });

  testWidgets(
      'cancelled file picker dismisses progress and leaves the page intact',
      (tester) async {
    messenger.setMockDecodedMessageHandler<Object?>(
        importChannel, (_) async => [null]);
    final result = Completer<String?>();
    await mount(tester, result);
    await tester.tap(find.text('选择视频并导入'));
    await tester.pumpAndSettle();
    expect(await result.future, isNull);
    expect(find.text('正在导入视频'), findsNothing);
    expect(find.text('添加媒体'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'import progress blocks duplicate actions until the native copy finishes',
      (tester) async {
    final nativeResult = Completer<Object?>();
    messenger.setMockDecodedMessageHandler<Object?>(
        importChannel, (_) => nativeResult.future);
    final result = Completer<String?>();
    await mount(tester, result);
    await tester.tap(find.text('选择视频并导入'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('正在导入视频'), findsOneWidget);
    expect(result.isCompleted, isFalse);
    nativeResult.complete([
      {
        'directory': '/app/files/ImportedMedia',
        'importedCount': 1,
        'failedCount': 1,
      }
    ]);
    await tester.pumpAndSettle();
    expect(await result.future, '/app/files/ImportedMedia');
    expect(find.text('正在导入视频'), findsNothing);
    expect(find.textContaining('1 个失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
