import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/ui/settings/codex_account_card.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

class _Account implements NextCodexAccountSettings {
  final changes = StreamController<void>.broadcast();
  Map<String, Object?> status = {'status': 'signedOut'};
  bool canceled = false;

  @override
  Stream<void> get codexAccountChanges => changes.stream;

  @override
  Future<Map<String, Object?>> codexAccount() async => status;

  @override
  Future<UiCodexLogin> startCodexLogin({required bool deviceCode}) async => (
        url: Uri.https('auth.openai.com', '/fixture'),
        code: deviceCode ? 'FIXTURE' : null,
      );

  @override
  Future<void> cancelCodexLogin() async => canceled = true;
}

void main() {
  test('projects only allowlisted account metrics and preserves unknown', () {
    final result = codexAccountMetrics({
      'rateLimits': {
        'primary': {'usedPercent': 0, 'token': 'fixture-secret'}
      }
    }, null);
    expect(result['usageAvailable'], false);
    expect(result['rateLimits'], [
      {
        'primary': {'usedPercent': 0}
      }
    ]);
    expect(result.toString(), isNot(contains('fixture-secret')));
  });

  testWidgets('login can be canceled and signed-in facts are displayed',
      (tester) async {
    final host = _Account();
    addTearDown(host.changes.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CodexAccountCard(host: host, canLogin: true))));
    await tester.pump();
    await tester.tap(find.text('使用设备码'));
    await tester.pump();
    expect(find.text('设备码：FIXTURE'), findsOneWidget);
    expect(find.text('打开浏览器'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(host.canceled, true);
    expect(find.text('设备码：FIXTURE'), findsNothing);

    host.status = {
      'status': 'signedIn',
      'email': 'test@example.invalid',
      'plan': 'plus',
      'usage': {'lifetimeTokens': 123},
      'rateLimits': [
        {
          'primary': {'windowDurationMins': 300, 'usedPercent': 42}
        }
      ],
    };
    host.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('已登录'), findsOneWidget);
    expect(find.text('test@example.invalid'), findsOneWidget);
    expect(find.text('plus'), findsOneWidget);
    expect(find.text('123 token'), findsOneWidget);
    expect(find.text('300 分钟窗口 · 已用 42%'), findsOneWidget);
  });

  testWidgets('existing configuration has no login controls', (tester) async {
    final host = _Account();
    addTearDown(host.changes.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CodexAccountCard(host: host, canLogin: false))));
    await tester.pump();
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('登录 ChatGPT'), findsNothing);
    expect(find.text('使用设备码'), findsNothing);
  });
}
