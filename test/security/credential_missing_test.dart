import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/security/credential_capability.dart';
import 'package:nipaplay/security/credential_notice.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'memory_vault.dart';

void main() {
  const ref = CredentialRef('smb_connections', 'smb-one');
  late MemoryVault vault;
  late CredentialStore store;
  late SharedPreferences prefs;
  late Map<String, Object?> json;

  setUp(() async {
    json = {
      'id': ref.key,
      'name': '书房 NAS',
      'host': '192.168.1.9',
      'username': 'user',
      'password': ref.placeholder,
    };
    SharedPreferences.setMockInitialValues({
      'smb_connections': jsonEncode([json]),
    });
    prefs = await SharedPreferences.getInstance();
    vault = MemoryVault();
    store = CredentialStore(vault, desktop: true, platform: TargetPlatform.macOS);
    final previous = CredentialStore.instance;
    CredentialStore.instance = store;
    addTearDown(() => CredentialStore.instance = previous);
  });

  Widget banner() =>
      const MaterialApp(home: CredentialNotice(child: Text('内容')));

  testWidgets('a missing credential is no banner, it marks its connection',
      (tester) async {
    final connection = SMBConnection.fromJson(json);
    for (var i = 0; i < 3; i++) {
      await expectLater(connection.resolvePassword(), throwsStateError);
    }
    expect(store.notices.value, isEmpty);
    expect(store.failures, isEmpty);
    expect(store.missing.value, {ref});
    expect(connection.passwordMissing, true);
    expect(await connection.hasPassword(), false);

    await tester.pumpWidget(banner());
    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(Material).evaluate().where((e) {
      final material = e.widget as Material;
      return material.color == const Color(0xffffe0b2);
    }), isEmpty);

    final api = harness.Harness([CredentialCapability(store)]);
    final status = jsonEncode((await api.invokeJson('credentials.status', {},
            harness.Invocation(origin: 'test')))
        .toEnvelope());
    expect(status, contains('SMB 连接「书房 NAS」需要重新输入密码'));
    expect(status, isNot(contains('CredentialRef')));
  });

  testWidgets('entering the password again clears the state', (tester) async {
    final connection = SMBConnection.fromJson(json);
    await expectLater(connection.resolvePassword(), throwsStateError);
    expect(store.missing.value, {ref});

    json['password'] = 'new-secret';
    await store.write(prefs, 'smb_connections', jsonEncode([json]));
    expect(store.missing.value, isEmpty);
    expect(store.notices.value, isEmpty);
    expect(vault.values[ref], 'new-secret');
    expect(connection.passwordMissing, false);
    expect(await connection.hasPassword(), true);
    await connection.resolvePassword();
    expect(connection.password, 'new-secret');
  });

  testWidgets('a refused vault still shows one dismissible banner',
      (tester) async {
    vault.denied = ref;
    final connection = SMBConnection.fromJson(json);
    await expectLater(connection.resolvePassword(), throwsStateError);
    await tester.pumpWidget(banner());
    expect(store.notices.value, hasLength(1));
    expect(find.textContaining('钥匙串'), findsOneWidget);
    expect(find.textContaining('CredentialRef'), findsNothing);
    expect(find.textContaining('smb-one'), findsNothing);
    expect(find.textContaining('storage_access_denied'), findsNothing);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining('钥匙串'), findsNothing);
    expect(find.text('内容'), findsOneWidget);
    // A refusal that already blocked this run does not bring the banner back.
    await expectLater(connection.resolvePassword(), throwsStateError);
    await tester.pump();
    expect(find.textContaining('钥匙串'), findsNothing);
  });

  testWidgets('the banner can retry and goes away once the vault answers',
      (tester) async {
    vault.denied = ref;
    vault.values[ref] = 'secret';
    final connection = SMBConnection.fromJson(json);
    await expectLater(connection.resolvePassword(), throwsStateError);
    await tester.pumpWidget(banner());
    vault.denied = null;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('钥匙串'), findsNothing);
    await connection.resolvePassword();
    expect(connection.password, 'secret');
  });
}
