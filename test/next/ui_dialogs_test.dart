import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/accounts/login_dialog.dart';
import 'package:nipaplay/next/media_sources/login_dialog.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';
import 'package:nipaplay/next/ui/widgets/dialog.dart';
import 'package:nipaplay/next/ui/widgets/sheet.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// NipaPlay's own windows (asking before deleting, logging in): in Next's
/// look while Next is the interface, Classic's dialogs otherwise; closing
/// one is a no, a stopped request takes it away, Return in the secret logs
/// in, and the debug `type` still finds the fields of the window in front.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'),
            (call) async => call.method == 'isMinimized' ? false : null);
  });
  tearDown(() {
    globals.nextShellHostsPlayer = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<void> app(WidgetTester tester, {required bool next}) async {
    globals.nextShellHostsPlayer = next;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: globals.navigatorKey,
        home: const Scaffold(body: Center(child: Text('页面')))));
  }

  const preview = {
    'downloads': [
      {
        'files': [
          {'path': '/dl/Frieren/Frieren - 05.mkv', 'expectedSize': 1 << 30},
          {'path': '/dl/Frieren/Frieren - 06.mkv', 'expectedSize': 1 << 30},
          {'path': '/dl/Frieren/Frieren - 07.mkv', 'expectedSize': 1 << 29},
          {'path': '/dl/Frieren/Frieren - 08.mkv', 'expectedSize': 1 << 29},
          {'path': '/dl/Frieren/Frieren - 09.mkv', 'expectedSize': 1 << 29},
        ]
      }
    ]
  };

  Future<bool> askToDelete({Future<void>? stopped}) =>
      showUserConsent('删除文件', downloadDeletionWords(preview), '删除',
          stopped: stopped, destructive: true);

  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is NextDialogButton && w.label == label);

  /// What the debug `type` reaches: with a window open, only its fields.
  List<EditableTextState> frontFields(WidgetTester tester) {
    final all =
        tester.stateList<EditableTextState>(find.byType(EditableText)).toList();
    bool inDialog(EditableTextState s) {
      final route = ModalRoute.of(s.context);
      return route is PopupRoute && route.isCurrent;
    }

    return all.any(inDialog) ? all.where(inDialog).toList() : all;
  }

  /// As `type submit=1` does it.
  void typeInto(EditableTextState field, String text, {bool submit = false}) {
    field.widget.controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    if (submit) field.widget.onSubmitted?.call(text);
  }

  group('Next on', () {
    testWidgets('the deletion question: names, how many more, how much',
        (tester) async {
      await app(tester, next: true);
      final answer = askToDelete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NextDialog), findsOneWidget);
      expect(find.byType(SheetSurface), findsOneWidget,
          reason: "the sheets' own surface");
      expect(ModalRoute.of(tester.element(find.byType(NextDialog))),
          isA<NextDialogRoute<bool>>());
      expect(find.text('删除文件'), findsOneWidget);
      for (final name in [
        'Frieren - 05.mkv',
        'Frieren - 06.mkv',
        'Frieren - 07.mkv'
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Frieren - 08.mkv'), findsNothing);
      expect(find.text('还有 2 个文件'), findsOneWidget);
      expect(find.text('共约 3.5 GB。'), findsOneWidget);
      // Crimson to be seen, never the white of a recommendation.
      expect(tester.widget<NextDialogButton>(button('删除')).kind,
          NextDialogButtonKind.danger);
      expect(tester.widget<NextDialogButton>(button('取消')).kind,
          NextDialogButtonKind.cancel);
      expect(
          tester
              .widgetList<NextDialogButton>(find.byType(NextDialogButton))
              .where((b) => b.kind == NextDialogButtonKind.primary),
          isEmpty);
      // Return does not delete.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(NextDialog), findsOneWidget);

      await tester.tap(button('删除'));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
      expect(find.byType(NextDialog), findsNothing);
    });

    testWidgets('closing it is a no: Esc, 取消', (tester) async {
      await app(tester, next: true);
      var answer = askToDelete();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(find.byType(NextDialog), findsNothing);

      answer = askToDelete();
      await tester.pumpAndSettle();
      await tester.tap(button('取消'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);

      // A click beside it (bringing the window forward) answers nothing.
      answer = askToDelete();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(NextDialog), findsOneWidget);
      await tester.tap(button('取消'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });

    testWidgets('a stopped request takes its window away', (tester) async {
      await app(tester, next: true);
      final stopped = Completer<void>();
      final answer = askToDelete(stopped: stopped.future);
      await tester.pumpAndSettle();
      expect(find.byType(NextDialog), findsOneWidget);
      stopped.complete();
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(find.byType(NextDialog), findsNothing);
      expect(find.text('页面'), findsOneWidget);

      final stopLogin = Completer<void>();
      final login =
          showAccountLogin({'provider': 'dandanplay'}, stopLogin.future);
      await tester.pumpAndSettle();
      expect(find.text('登录弹弹play'), findsOneWidget);
      stopLogin.complete();
      await tester.pumpAndSettle();
      expect(await login, isNull);
      expect(find.byType(NextDialog), findsNothing);
    });

    testWidgets('弹弹play: two fields, Return in the password logs in',
        (tester) async {
      await app(tester, next: true);
      final login = showAccountLogin(
          {'provider': 'dandanplay'}, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NextDialogField), findsNWidgets(2));
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.last.obscureText, isTrue);
      expect(fields.first.obscureText, isFalse);
      // Nothing to log in with yet.
      expect(tester.widget<NextDialogButton>(button('登录')).onTap, isNull);
      expect(tester.widget<NextDialogButton>(button('登录')).kind,
          NextDialogButtonKind.primary);

      await tester.enterText(find.byType(TextField).first, ' nipa ');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await login, {'username': 'nipa', 'password': 'secret'});
      expect(find.byType(NextDialog), findsNothing);
    });

    testWidgets('the debug type finds the window\'s fields and submits',
        (tester) async {
      await app(tester, next: true);
      // A field of the page under the window.
      await tester.pumpWidget(MaterialApp(
          navigatorKey: globals.navigatorKey,
          home: const Scaffold(body: Center(child: TextField()))));
      final login = showAccountLogin(
          {'provider': 'dandanplay'}, Completer<void>().future);
      await tester.pumpAndSettle();
      final fields = frontFields(tester);
      expect(fields, hasLength(2), reason: 'only the window\'s');
      typeInto(fields[0], 'nipa');
      typeInto(fields[1], 'secret', submit: true);
      await tester.pumpAndSettle();
      expect(await login, {'username': 'nipa', 'password': 'secret'});
    });

    testWidgets('Bangumi: one token; Esc is a cancel', (tester) async {
      await app(tester, next: true);
      var login =
          showAccountLogin({'provider': 'bangumi'}, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(find.text('登录 Bangumi'), findsOneWidget);
      expect(find.byType(NextDialogField), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await login, isNull);

      login =
          showAccountLogin({'provider': 'bangumi'}, Completer<void>().future);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'token');
      await tester.pump();
      await tester.tap(button('登录'));
      await tester.pumpAndSettle();
      expect(await login, {'accessToken': 'token'});
    });

    testWidgets('a media source: who logs in, then the password',
        (tester) async {
      await app(tester, next: true);
      final stopped = Completer<void>();
      final login = showMediaSourceLogin({
        'name': '家里的 Jellyfin',
        'type': 'jellyfin',
        'url': 'http://192.168.1.20:8096',
        'username': 'sakiko'
      }, stopped.future);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('登录 家里的 Jellyfin'), findsOneWidget);
      expect(find.text('http://192.168.1.20:8096'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, hasLength(2));
      expect(fields.first.readOnly, isTrue);
      expect(fields.first.controller!.text, 'sakiko');
      expect(fields.last.obscureText, isTrue);
      final front = frontFields(tester);
      typeInto(front[1], 'user-typed-secret', submit: true);
      await tester.pumpAndSettle();
      expect(await login, 'user-typed-secret');

      final again = showMediaSourceLogin({
        'name': '家里的 Jellyfin',
        'type': 'jellyfin',
        'url': 'http://192.168.1.20:8096',
        'username': 'sakiko'
      }, Completer<void>().future);
      await tester.pumpAndSettle();
      await tester.tap(button('取消'));
      await tester.pumpAndSettle();
      expect(await again, isNull);
    });
  });

  group('Next off', () {
    testWidgets('Classic\'s Material dialogs, as before', (tester) async {
      await app(tester, next: false);
      final answer = askToDelete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(NextDialog), findsNothing);
      expect(ModalRoute.of(tester.element(find.byType(AlertDialog))),
          isA<DialogRoute<bool>>());
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);

      final login = showAccountLogin(
          {'provider': 'dandanplay'}, Completer<void>().future);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(NextDialogField), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'nipa');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await login, {'username': 'nipa', 'password': 'secret'});

      final stopped = Completer<void>();
      final source = showMediaSourceLogin(
          {'name': 'NAS', 'url': 'smb://nas:445', 'username': 'sakiko'},
          stopped.future);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
      stopped.complete();
      await tester.pumpAndSettle();
      expect(await source, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
