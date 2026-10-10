import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/media/media_executors.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/metadata_provider.dart';
import 'package:nipaplay/next/media/provider_transport.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class FixtureTransport implements MetadataTransport {
  FixtureTransport(String provider)
      : responses = Map<String, Object?>.from(jsonDecode(
            File('test/next/fixtures/media/$provider.json')
                .readAsStringSync()) as Map);
  final Map<String, Object?> responses;
  final List<JsonMap> requests = [];
  final Map<String, JsonMap Function(JsonMap? body)> handlers = {};
  Completer<void>? entered, release;
  ProviderRetry? retry;
  @override
  Future<JsonMap> request(String path,
      {Map<String, String> query = const {}, JsonMap? body}) async {
    requests.add({'path': path, 'query': query, 'body': body});
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await release?.future;
    if (retry case final error?) {
      retry = null;
      throw error;
    }
    if (handlers[path] case final handler?) return handler(body);
    final response = responses[path];
    if (response == null) throw StateError('Unrecorded fixture request: $path');
    return Map<String, Object?>.from(jsonDecode(jsonEncode(response)) as Map);
  }
}

final class MemoryClassic implements ClassicMetadataPort {
  final Map<String, JsonMap> rows = {};
  bool rejectReadback = false;
  int applications = 0;
  @override
  Future<List<JsonMap>> history() async => [
        for (final row in rows.values) {...row}
      ];
  @override
  Future<void> apply(String locator, JsonMap fields) async {
    applications++;
    rows[locator] = {
      ...?(rows[locator]),
      'filePath': locator,
      if (fields['clear'] == true) ...{
        'animeName': '',
        'episodeTitle': null
      } else
        ...fields
    };
  }

  @override
  Future<bool> verify(String locator, JsonMap fields) async {
    if (rejectReadback) return false;
    final row = rows[locator]!;
    if (fields['clear'] == true) {
      return row['animeName'] == '' && row['episodeTitle'] == null;
    }
    return fields.entries.every((field) => row[field.key] == field.value);
  }
}

final class MediaFixture {
  late Directory root, media;
  late SqliteJobStore jobs;
  late IdentityStore identities;
  late MediaService service;
  late TaskEngine engine;
  late Harness harness;
  final classic = MemoryClassic();
  final tmdb = FixtureTransport('tmdb'),
      bangumi = FixtureTransport('bangumi'),
      dandanplay = FixtureTransport('dandanplay');
  Future<void> open({List<String> sources = const ['tmdb']}) async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-media-');
    media = await Directory('${root.path}/media').create();
    await _connect(sources);
  }

  Future<void> _connect(List<String> sources) async {
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    identities = IdentityStore(jobs.database, 'fixture-device');
    final providers = <MetadataProvider>[
      TmdbMetadataProvider(tmdb),
      BangumiMetadataProvider(bangumi),
      DandanplayMetadataProvider(dandanplay)
    ];
    service = MediaService(
        store: identities,
        providers: providers.where((provider) => sources.contains(provider.id)),
        classic: classic,
        authorizedRoots: () => [media.path],
        durationProbe: (_) async => 1440000);
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'fixture-device',
        executors: mediaExecutors(service));
    service.engine = engine;
    harness = Harness([MediaCapability(service), TaskCapability(engine)]);
    await engine.start();
  }

  Future<void> reopen({List<String> sources = const ['tmdb']}) async {
    await engine.close();
    await _connect(sources);
  }

  Future<String> file(String filename) async {
    final file = File('${media.path}/$filename');
    await file.writeAsString('fixture bytes for $filename');
    return service.index(file.path);
  }

  Future<JsonMap> call(String id, JsonMap input,
      {String origin = 'mcp'}) async {
    final outcome =
        await harness.invokeJson(id, input, Invocation(origin: origin));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(harness.lookup(id)!.spec.output.validate(result), isEmpty,
        reason: 'Output schema for $id');
    return result;
  }

  Future<void> close() async {
    await engine.close();
    await root.delete(recursive: true);
  }
}

Future<Job> waitForJob(TaskEngine engine, String id, JobState target) async {
  for (var i = 0; i < 100; i++) {
    final job = await engine.get(id);
    if (job.state == target) return job;
    if (job.state.isTerminal) {
      fail('Expected $target, got ${jsonEncode(job.toJson())}');
    }
    await engine.wait(id,
        afterRevision: job.revision,
        timeout: const Duration(milliseconds: 100));
  }
  throw StateError('Timed out waiting for $id to reach $target');
}

const mediaWorkRef = {
  'provider': 'tmdb',
  'objectType': 'tv',
  'externalId': '9001',
  'scope': ''
};
const mediaReleaseRef = {
  'provider': 'tmdb',
  'objectType': 'season',
  'externalId': '9101',
  'scope': 'tv/9001/season/1'
};
JsonMap mediaEpisodeRef(int number) => {
      'provider': 'tmdb',
      'objectType': 'episode',
      'externalId': '${9200 + number}',
      'scope': 'tv/9001/season/1/episode/$number'
    };
JsonMap tmdbBinding(String fileId, {List<int> episodes = const [1]}) => {
      'kind': 'file',
      'entityId': fileId,
      'workRef': mediaWorkRef,
      'releaseRef': mediaReleaseRef,
      'episodeRefs': [for (final number in episodes) mediaEpisodeRef(number)],
      'reason': 'Agent explicitly selected catalogue episodes',
      'evidence': [
        {'source': 'fixture', 'detail': 'Offline explicit mapping'}
      ]
    };
JsonMap dandanplayBinding(String fileId) => {
      'kind': 'file',
      'entityId': fileId,
      'workRef': {
        'provider': 'dandanplay',
        'objectType': 'anime',
        'externalId': '7001',
        'scope': ''
      },
      'episodeRefs': [
        {
          'provider': 'dandanplay',
          'objectType': 'episode',
          'externalId': '7101',
          'scope': 'anime/7001'
        }
      ],
      'reason': 'Agent accepted hash signal'
    };
