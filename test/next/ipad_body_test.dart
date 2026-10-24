import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/body/next_body.dart';
import 'package:nipaplay/next/mesh/install_id.dart';
import 'package:nipaplay/next/mesh/presence.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/keychain_credential_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Action extends Action<JsonEncodable, JsonEncodable> {
  _Action(this.id);
  final String id;
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: id,
      description: id,
      effect: Effect.read,
      input: const ObjectSchema({}),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  JsonEncodable decodeInput(JsonMap json) => throw UnimplementedError();
  @override
  Future<Outcome<JsonEncodable>> run(
          JsonEncodable input, Invocation invocation) =>
      throw UnimplementedError();
}

final class _Cap implements Capability {
  _Cap(List<String> ids) : actions = [for (final id in ids) _Action(id)];
  @override
  final List<Action> actions;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => NextBody.debugBodyOnly = null);

  group('presence', () {
    test('a device that never spoke is present', () {
      expect(MeshPresence().absent('x'), isFalse);
    });

    test('background and the other interface are absent, foreground is not',
        () {
      final presence = MeshPresence();
      expect(presence.record('a', {'state': 'background'}), isTrue);
      expect(presence.absent('a'), isTrue);
      presence.record('b', {'state': 'classic'});
      expect(presence.absent('b'), isTrue);
      presence.record('a', {'state': 'foreground'});
      expect(presence.absent('a'), isFalse);
    });

    test('messages that cross are ordered by their own time', () {
      final presence = MeshPresence();
      presence.record('a',
          {'state': 'foreground', 'at': '2026-10-25T10:00:05Z'});
      expect(
          presence.record(
              'a', {'state': 'background', 'at': '2026-10-25T10:00:01Z'}),
          isFalse);
      expect(presence.absent('a'), isFalse);
    });

    test('malformed facts are refused and what was playing is kept', () {
      final presence = MeshPresence();
      expect(presence.record('a', {'state': 'asleep'}), isFalse);
      expect(presence.record('a', 'background'), isFalse);
      presence.record('a', {
        'state': 'background',
        'nowPlaying': {'work': 'x', 'paused': true},
        'progress': {'positionMs': 5, 'durationMs': 9},
      });
      final json = presence.of('a')!.toJson();
      expect(json['present'], isFalse);
      expect((json['nowPlaying'] as Map)['work'], 'x');
      expect((json['progress'] as Map)['positionMs'], 5);
    });

    test('a device that left the roster is forgotten', () {
      final presence = MeshPresence()
        ..record('a', {'state': 'background'})
        ..record('b', {'state': 'background'});
      presence.retain({'b'});
      expect(presence.of('a'), isNull);
      expect(presence.absent('b'), isTrue);
    });
  });

  group('body capabilities', () {
    final ids = [
      'window.control',
      'window.bounds.set',
      'program.run',
      'chat.send',
      'agent.dispatch',
      'memory.read',
      'app.quit',
      'app.restart',
      'playback.state',
      'settings.set',
      'ui.capture',
      'app.capabilities',
    ];

    test('an iPad has none of what only a desktop or a host runs', () {
      NextBody.debugBodyOnly = true;
      final kept = [
        for (final c in NextBody.filter([_Cap(ids)]))
          for (final a in c.actions) a.spec.id
      ];
      expect(kept, [
        'playback.state',
        'settings.set',
        'ui.capture',
        'app.capabilities',
      ]);
    });

    test('a desktop keeps every capability', () {
      NextBody.debugBodyOnly = false;
      final kept = [
        for (final c in NextBody.filter([_Cap(ids)]))
          for (final a in c.actions) a.spec.id
      ];
      expect(kept, ids);
    });
  });

  group('installation identity', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('ipad-body-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('the install number is random, kept, and not the path', () async {
      final first = await meshInstallId(root);
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(await meshInstallId(root), first);
      final other = Directory.systemTemp.createTempSync('ipad-body-2-');
      addTearDown(() => other.deleteSync(recursive: true));
      expect(await meshInstallId(other), isNot(first));
    });
  });

  group('Keychain vault', () {
    const channel = MethodChannel('nipaplay/keychain');
    final keychain = <String, String>{};
    const ref = CredentialRef('mesh', 'abc');

    setUp(() {
      keychain.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        final account = '${args['namespace']}/${args['key']}';
        switch (call.method) {
          case 'read':
            return keychain[account];
          case 'write':
            keychain[account] = args['secret'] as String;
            return null;
          case 'delete':
            keychain.remove(account);
            return null;
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('writes go to the Keychain and read back', () async {
      SharedPreferences.setMockInitialValues({});
      final vault = KeychainCredentialVault();
      await vault.write(ref, 's3cret');
      expect(keychain['mesh/abc'], 's3cret');
      expect(await vault.read(ref), 's3cret');
      await vault.delete(ref);
      expect(await vault.read(ref), isNull);
    });

    test('a secret the old iOS vault kept in preferences moves, once',
        () async {
      final legacy = KeychainCredentialVault.legacyKey(ref);
      SharedPreferences.setMockInitialValues({legacy: 'old'});
      final vault = KeychainCredentialVault();
      expect(await vault.read(ref), 'old');
      expect(keychain['mesh/abc'], 'old');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(legacy), isFalse);
      expect(await vault.read(ref), 'old');
    });

    test('a failing Keychain is an error, never a silent fallback', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel,
              (call) async => throw PlatformException(code: 'vault_operation_failed'));
      SharedPreferences.setMockInitialValues({});
      await expectLater(KeychainCredentialVault().write(ref, 'x'),
          throwsA(isA<StateError>()));
    });
  });
}
