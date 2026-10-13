import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/danmaku/capability.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/app_capabilities.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/security/credential_vault.dart';
import '../security/memory_vault.dart';
import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open(sources: ['dandanplay']);
  });
  tearDown(() => f.close());

  test(
      'capability readiness follows vault changes without exposing a secret or a refusal',
      () async {
    final vault = MemoryVault();
    final service = DanmakuService(
        store: DanmakuStore(f.identities), sources: [], player: NoPlayer());
    final facts = AppCapabilities(
        host: 'headless',
        catalog: () => f.harness.catalog,
        media: f.service,
        danmaku: service,
        settings: SettingsRegistry(f.jobs.database, []),
        vault: vault,
        programEnabled: () => false);
    JsonMap dandanplay(JsonMap value) => (value['providers'] as List)
        .cast<JsonMap>()
        .singleWhere((p) => p['id'] == 'dandanplay');
    expect(dandanplay(await facts.facts())['available'], false);
    const ref = CredentialRef('preferences', 'dandanplay_token');
    await vault.write(ref, 'synthetic-secret-not-a-real-account');
    final ready = await facts.facts();
    expect(dandanplay(ready)['available'], true);
    expect(jsonEncode(ready),
        isNot(contains('synthetic-secret-not-a-real-account')));
    vault
      ..denied = ref
      ..refusal = 'private-refusal-synthetic';
    final blocked = await facts.facts();
    expect(dandanplay(blocked)['available'], false);
    expect(dandanplay(blocked)['reason'], contains('vault is unavailable'));
    expect(jsonEncode(blocked), isNot(contains('private-refusal-synthetic')));
  });

  test(
      'headless binding retries preserve Next identity and a truthful projection receipt',
      () async {
    final media = MediaService(
        store: f.identities,
        providers: f.service.providers.values,
        classic: NoClassic(),
        authorizedRoots: () => [f.media.path],
        durationProbe: (_) async => 60000);
    final fileId = await f.file('sample.mp4');
    final api = Harness([MediaCapability(media)]);
    final input = {
      'requestId': 'headless-binding',
      'entries': [dandanplayBinding(fileId)]
    };
    final first = await api.invokeJson(
        'media.identity.bind_batch', input, Invocation(origin: 'gui'));
    expect(first, isA<Completed>());
    final before = await f.jobs.database.query('media_bindings');
    expect(before, isNotEmpty);
    final replay = await api.invokeJson(
        'media.identity.bind_batch', input, Invocation(origin: 'gui'));
    expect(replay.toEnvelope(), first.toEnvelope());
    expect(await f.jobs.database.query('media_bindings'), before);
    expect(
        (await f.jobs.database.query('media_projection_outbox'))
            .single['state'],
        'not_applicable');
    expect(jsonEncode(first.toEnvelope()), contains('not_applicable'));
    expect(f.classic.applications, 0);
  });

  test(
      'batch import retains committed content and receipt when a later pool is malformed',
      () async {
    final fileId = await f.file('sample.mp4');
    final good = await File('${f.media.path}/good.json').writeAsString(
        '[{"sourceTimeMs":1000,"text":"CC0 fixture","mode":1,"colorRgb":16777215}]');
    final bad = await File('${f.media.path}/bad.json').writeAsString('invalid');
    final service = DanmakuService(
        store: DanmakuStore(f.identities), sources: [], player: NoPlayer());
    final api = Harness([DanmakuCapability(service)]);
    final input = {
      'entries': [
        for (final path in [good.path, bad.path])
          {
            'filePath': path,
            'entityId': fileId,
            'platform': 'cc0-fixture',
            'platformVideoId': 'one'
          }
      ]
    };
    final result = await api.invokeJson(
        'danmaku.import_batch', input, Invocation(origin: 'gui'));
    expect(result, isA<Completed>());
    final rows = (result as Completed).value.toJson()['entries'] as List;
    expect(rows[0]['status'], 'completed');
    expect(rows[1]['status'], 'failed');
    final bindingId = rows[0]['result']['bindingId'];
    final binding = await service.store.binding(bindingId);
    expect(await service.store.entries(binding['cache_key'] as String),
        hasLength(1));
    expect(await good.exists(), true);
    expect(await File('${f.media.path}/sample.mp4').exists(), true);
  });
}
