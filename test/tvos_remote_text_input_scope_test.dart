import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';

void main() {
  test('tvOS platform keeps remote input enabled when an overlay loses scope',
      () {
    expect(
      resolveTvOSRemoteTextInputEnabled(
        platformIsTelevision: true,
        surface: AppDisplaySurface.desktopTablet,
      ),
      isTrue,
    );
    expect(
      resolveTvOSRemoteTextInputEnabled(
        platformIsTelevision: false,
        surface: AppDisplaySurface.desktopTablet,
      ),
      isFalse,
    );
  });

  testWidgets('select on a focused field opens remote input and backfills it',
      (tester) async {
    final controller = TextEditingController(text: '12');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    TvOSRemoteTextInputTarget? requestedTarget;
    var changedValue = '';

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
            applyTvOSRemoteTextInputValue(target, 'a34');
          },
          child: Material(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: '端口'),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '端口');
    expect(controller.text, '34');
    expect(changedValue, '34');
  });

  testWidgets('focused TV action discovers a nested read-only text field',
      (tester) async {
    final controller = TextEditingController();
    final actionFocusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(actionFocusNode.dispose);
    TvOSRemoteTextInputTarget? requestedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
          },
          child: Material(
            child: TvOSRemoteTextInputAnchor(
              child: NipaplayLargeScreenFocusableAction(
                focusNode: actionFocusNode,
                onActivate: () {},
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  canRequestFocus: false,
                  decoration: const InputDecoration(hintText: '用户名'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    actionFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '用户名');
  });

  testWidgets('large-screen text input opens remote input from control focus',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    TvOSRemoteTextInputTarget? requestedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
          },
          child: Scaffold(
            body: NipaplayLargeScreenTextInput(
              controller: controller,
              hintText: '搜索媒体库',
            ),
          ),
        ),
      ),
    );

    final action = tester.widget<NipaplayLargeScreenFocusableAction>(
      find.byType(NipaplayLargeScreenFocusableAction),
    );
    action.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '搜索媒体库');
  });

  testWidgets('television adaptive field keeps native editor unfocused',
      (tester) async {
    final controller = TextEditingController(text: '8096');
    final controlFocusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(controlFocusNode.dispose);
    TvOSRemoteTextInputTarget? requestedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
          },
          child: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.television,
            child: Material(
              child: AdaptiveMediaTextField(
                controller: controller,
                focusNode: controlFocusNode,
                remoteInputTitle: '服务器端口',
                keyboardType: TextInputType.number,
                maxLength: 5,
              ),
            ),
          ),
        ),
      ),
    );

    controlFocusNode.requestFocus();
    await tester.pump();
    expect(controlFocusNode.hasFocus, isTrue);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '服务器端口');
    expect(requestedTarget!.inputType, 'number');
    expect(requestedTarget!.maxLength, 5);
  });

  testWidgets('television login dialog opens QR input for its first field',
      (tester) async {
    TvOSRemoteTextInputTarget? requestedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
            applyTvOSRemoteTextInputValues(target, const <String, String>{
              'server': 'http://emby.local:8096',
              'password': 'secret',
            });
          },
          child: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.television,
            child: Material(
              child: BlurLoginDialog(
                title: '连接到 Emby 服务器',
                embedded: true,
                fields: const <LoginField>[
                  LoginField(
                    key: 'server',
                    label: '服务器地址',
                    hint: 'http://192.168.1.100:8096',
                  ),
                  LoginField(
                    key: 'password',
                    label: '密码',
                    isPassword: true,
                  ),
                ],
                onLogin: (_) async => const LoginResult(success: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '连接到 Emby 服务器');
    expect(requestedTarget!.fields, hasLength(2));
    expect(
      requestedTarget!.fields.map((field) => field.id),
      <String>['server', 'password'],
    );
    expect(
      requestedTarget!.fields.map((field) => field.title),
      <String>['服务器地址', '密码'],
    );
    expect(requestedTarget!.fields.first.required, isTrue);
    expect(requestedTarget!.fields.last.obscureText, isTrue);
    final editables =
        tester.widgetList<EditableText>(find.byType(EditableText));
    expect(
      editables.map((editable) => editable.controller.text),
      <String>['http://emby.local:8096', 'secret'],
    );
  });

  testWidgets('television form-field wrapper exposes the exact nested input',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    TvOSRemoteTextInputTarget? requestedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            requestedTarget = target;
          },
          child: AppDisplaySurfaceScope(
            surface: AppDisplaySurface.television,
            child: Material(
              child: TvOSRemoteTextInputControl(
                title: '密码',
                child: TextFormField(
                  controller: controller,
                  obscureText: true,
                  maxLines: 1,
                  maxLength: 32,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final control = tester.widget<FocusableActionDetector>(
      find.byType(FocusableActionDetector),
    );
    control.focusNode!.requestFocus();
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(requestedTarget, isNotNull);
    expect(requestedTarget!.title, '密码');
    expect(requestedTarget!.obscureText, isTrue);
    expect(requestedTarget!.maxLength, 32);
  });

  testWidgets('select on an unrelated control is never hijacked',
      (tester) async {
    final controller = TextEditingController();
    final actionFocusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(actionFocusNode.dispose);
    var activationCount = 0;
    var remoteInputCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TvOSRemoteTextInputScope(
          onRemoteInputRequested: (context, target) async {
            remoteInputCount += 1;
          },
          child: Material(
            child: Column(
              children: [
                NipaplayLargeScreenFocusableAction(
                  focusNode: actionFocusNode,
                  onActivate: () => activationCount += 1,
                  child: const Text('普通功能'),
                ),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(hintText: '页面输入框'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    actionFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(activationCount, 1);
    expect(remoteInputCount, 0);
  });
}
