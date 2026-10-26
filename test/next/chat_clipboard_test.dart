import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/chat/copy_message.dart';
import 'package:nipaplay/next/ui/chat/input_paste.dart';
import 'package:nipaplay/services/clipboard_image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        case 'Clipboard.getData':
          return {'text': clipboard};
        case 'Clipboard.hasStrings':
          return {'value': clipboard?.isNotEmpty ?? false};
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('nipaplay/clipboard_image'), null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('copy keeps full Markdown and code, not just visible text',
      (tester) async {
    const text = '梨花的回答\n\n```sh\nprintf hello\n```';
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body:
                CopyChatMessage(text: text, child: Text('rendered answer')))));
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(clipboard, text);
    expect(find.text('已复制'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
        '$platform paste shortcut attaches an image without editing text',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final controller = TextEditingController(text: '看这个');
      final focus = FocusNode();
      final attached = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChatInputPaste(
        controller: controller,
        enabled: true,
        onImages: attached.addAll,
        readImages: () async => ['/saved/clipboard.png'],
        builder: (menu) => TextField(
            controller: controller, focusNode: focus, contextMenuBuilder: menu),
      ))));
      await tester.tap(find.byType(TextField));
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(attached, ['/saved/clipboard.png']);
      expect(controller.text, '看这个');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
      'text paste replaces selection and image-only context menu can paste',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var images = <String>[];
    final controller = TextEditingController(text: 'hello world');
    final attached = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatInputPaste(
      controller: controller,
      enabled: true,
      onImages: attached.addAll,
      readImages: () async => images,
      builder: (menu) =>
          TextField(controller: controller, contextMenuBuilder: menu),
    ))));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    clipboard = '梨花';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'hello 梨花');
    clipboard = null;
    images = ['/saved/screenshot.png'];
    final editor = tester.state<EditableTextState>(find.byType(EditableText));
    editor.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(attached, images);
    expect(controller.text, 'hello 梨花');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'native image reader gets durable destination and leaves clipboard intact',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('nipaplay/clipboard_image'), (call) async {
      received = call;
      return ['/data/next/chat-attachments/clipboard.png'];
    });
    expect(
        await ClipboardImageService.readImageFiles(
            '/data/next/chat-attachments'),
        ['/data/next/chat-attachments/clipboard.png']);
    expect(received!.method, 'readImageFiles');
    expect(received!.arguments, {'directory': '/data/next/chat-attachments'});
  });
}
