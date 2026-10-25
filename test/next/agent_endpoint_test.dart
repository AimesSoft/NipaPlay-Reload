import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/capabilities/classic_action.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart' show UiNowPlaying;

import 'test_support.dart';
import 'support/platform.dart';
import 'package:path/path.dart' as ppath;

void main() {
  late Directory root, repository;
  late File credentials;
  late AgentEndpoint endpoint;
  late HttpClient client;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('endpoint-constraints-');
    repository = Directory('${root.path}/harness');
    credentials = File('${root.path}/private/endpoint.json');
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {'nipa': utf8.encode('#!/usr/bin/env python3\n')},
        appVersion: 'test',
        credentialFile: credentials,
        port: 0);
    client = HttpClient()..findProxy = (_) => 'DIRECT';
  });
  tearDown(() async {
    client.close(force: true);
    await endpoint.stop();
    await root.delete(recursive: true);
  });

  group('status playback', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() => HttpOverrides.global = null);
    Future<Map> playbackOf(PlaybackFixture fixture,
        Future<UiNowPlaying?> Function(String)? nowPlaying) async {
      endpoint = AgentEndpoint(
          harness: fixture.harness,
          seed: {},
          appVersion: 'test',
          nowPlaying: nowPlaying,
          instanceFacts: () async => {},
          credentialFile: credentials,
          port: 0);
      final running = await endpoint.start(repository) as AgentEndpointRunning;
      final token =
          (jsonDecode(await credentials.readAsString()) as Map)['token'];
      final call = await client.postUrl(running.url.replace(path: '/harness'));
      call.headers.set('Authorization', 'Bearer $token');
      call.write(jsonEncode({'operation': 'status'}));
      final response = await call.close();
      final body = jsonDecode(await utf8.decodeStream(response)) as Map;
      return (body['body'] as Map)['playback'] as Map;
    }

    test('a series episode carries work, episode and position', () async {
      final playback = await playbackOf(
          PlaybackFixture(),
          (path) async => path == '/media/episode.mkv'
              ? const UiNowPlaying(
                  workId: 'w1',
                  work: 'Work',
                  episodeId: 'e3',
                  episode: '第 3 集 Title')
              : null);
      expect(playback, {
        'state': 'playing',
        'workId': 'w1',
        'work': 'Work',
        'episodeId': 'e3',
        'episode': '第 3 集 Title',
        'positionMs': 500,
        'durationMs': 1000,
        'path': '/media/episode.mkv',
      });
    });

    test('a film has no episode number and a paused state shows', () async {
      final fixture = PlaybackFixture()..player.paused = true;
      final playback = await playbackOf(
          fixture,
          (_) async => const UiNowPlaying(
              workId: 'w2', work: 'Film', episodeId: 'e9'));
      expect(playback['state'], 'paused');
      expect(playback['work'], 'Film');
      expect(playback.containsKey('episode'), false);
    });

    test('without a library name only the player facts are given', () async {
      final playback = await playbackOf(PlaybackFixture(), null);
      expect(playback['state'], 'playing');
      expect(playback['positionMs'], 500);
      expect(playback.containsKey('work'), false);
    });

    test('nothing playing is idle', () async {
      final fixture = PlaybackFixture()..player.hasVideo = false;
      final playback = await playbackOf(
          fixture, (_) async => throw StateError('not asked'));
      expect(playback, {'state': 'idle'});
    });
  });

  group('status summaries', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() => HttpOverrides.global = null);

    ClassicAction read(String id, Future<JsonMap> Function(JsonMap) run) =>
        ClassicAction(
            ActionSpec(
                id: id,
                title: id,
                description: 'Fixture',
                effect: Effect.read,
                input: const ObjectSchema({}, additionalProperties: true),
                output: const ObjectSchema({}, additionalProperties: true)),
            (input, _) => run(input));

    Future<Map> bodyOf(Capability capability) async {
      endpoint = AgentEndpoint(
          harness: Harness([capability]),
          seed: {},
          appVersion: 'test',
          instanceFacts: () async => {},
          credentialFile: credentials,
          port: 0);
      final running = await endpoint.start(repository) as AgentEndpointRunning;
      final token =
          (jsonDecode(await credentials.readAsString()) as Map)['token'];
      final call = await client.postUrl(running.url.replace(path: '/harness'));
      call.headers.set('Authorization', 'Bearer $token');
      call.write(jsonEncode({'operation': 'status'}));
      final response = await call.close();
      final body = jsonDecode(await utf8.decodeStream(response)) as Map;
      return body['body'] as Map;
    }

    test('each part is a short summary and says where its detail is', () async {
      final views = <String, List<Map>>{
        'media.sources': [
          {
            'connectionState': 'connected',
            'unreachableAddressCount': 0,
            'credentialState': 'saved',
            'syncResult': 'succeeded'
          },
          {
            'connectionState': 'failed',
            'unreachableAddressCount': 2,
            'credentialState': 'rejected',
            'syncResult': 'failed'
          },
          {
            'connectionState': 'unverified',
            'unreachableAddressCount': 1,
            'credentialState': 'missing',
            'syncResult': 'running'
          },
        ],
        'downloads.engine': [
          {
            'enabled': true,
            'running': 2,
            'queued': 1,
            'paused': 0,
            'downloadBytesPerSecond': 1000,
            'uploadBytesPerSecond': 10
          },
          {
            'enabled': true,
            'running': 1,
            'queued': 0,
            'paused': 1,
            'downloadBytesPerSecond': 500,
            'uploadBytesPerSecond': 0
          },
        ],
        'library.scan': [
          {'scanning': true, 'rootCount': 2, 'failedFileCount': 3}
        ],
        'network.observations': [
          {'availability': 'reachable'},
          {'availability': 'failed'},
        ],
        'app.update': [
          {
            'checked': true,
            'checkedAt': '2026-10-22T00:00:00.000Z',
            'hasUpdate': false,
            'latestVersion': '1.0.0',
            'errorCode': null
          }
        ],
        'harness.hooks': [
          {'state': 'ready'},
          {'state': 'ready', 'lastState': 'failed'},
          {'state': 'not_executable'},
          {'state': 'absent'},
          {'state': 'unrecognized'},
        ],
        'harness.schedules': [
          {
            'index': 0,
            'valid': true,
            'file': 'valid',
            'skippedLate': 2,
            'skippedWhileRunning': 1
          },
          {'index': 1, 'valid': false, 'file': 'valid'},
        ],
        'mesh.devices': [
          {'online': true},
          {'online': false},
        ],
      };
      final body = await bodyOf(_Fixture([
        read('state.query', (input) async => {
              'rows': views[input['view']] ??
                  (throw StateError('no ${input['view']}'))
            }),
        read('download.directories', (_) async => {'defaultDirectory': '/d'}),
        read('storage.status', (_) async => {
              'volumes': [
                {'availableBytes': 1, 'totalBytes': 10},
                {'availableBytes': 2, 'totalBytes': 20},
              ]
            }),
      ]));
      expect(body['sources'], {
        'count': 3,
        'connected': 1,
        'failed': 1,
        'unreachableAddresses': 3,
        'credentialRejected': 1,
        'credentialMissing': 1,
        'syncFailed': 1,
        'syncRunning': 1,
      });
      expect(body['downloads'], {
        'directory': '/d',
        'enabled': true,
        'running': 3,
        'queued': 1,
        'paused': 1,
        'downloadBytesPerSecond': 1500,
        'uploadBytesPerSecond': 10,
      });
      expect(body['space'], {
        'availableBytes': 1,
        'totalBytes': 10,
        'volumes': [
          {'availableBytes': 1, 'totalBytes': 10},
          {'availableBytes': 2, 'totalBytes': 20},
        ],
      });
      expect(body['scan'], {'scanning': true, 'roots': 2, 'failedFiles': 3});
      expect(body['network'], {'observed': 2, 'failed': 1});
      expect(body['updates'], {
        'checked': true,
        'checkedAt': '2026-10-22T00:00:00.000Z',
        'hasUpdate': false,
        'latestVersion': '1.0.0',
        'errorCode': null,
      });
      expect(body['hooks'], {
        'ready': 2,
        'notExecutable': 1,
        'unrecognized': 1,
        'failedLastRun': 1,
        'schedules': {
          'file': 'valid',
          'entries': 2,
          'invalid': 1,
          'skipped': 3,
          'failedLastRun': 0,
        },
      });
      expect(body['mesh'], {'devices': 2, 'online': 1});
      expect((body['views'] as Map)['sources'],
          ['media.sources', 'media.source_addresses']);
      expect((body['views'] as Map)['hooks'],
          ['harness.hooks', 'harness.schedules']);
    });

    test('playback carries the current error and the newest failure; '
        'diagnostics counts this run\'s errors and unread unclean exits',
        () async {
      final asked = <Map>[];
      final body = await bodyOf(_Fixture([
        read('playback.state', (_) async => {
              'state': {
                'status': 'error',
                'hasVideo': false,
                'path': '/media/a.mkv',
                'error': {
                  'code': 'media_load_failed',
                  'stage': 'media_open',
                  'category': 'unsupported_format',
                  'failureId': 'pf-1',
                },
              }
            }),
        read('playback.failures', (input) async {
          asked.add(input);
          return {
            'failures': [
              {
                'failureId': 'pf-1',
                'at': '2026-10-22T00:00:00.000Z',
                'category': 'unsupported_format',
                'stage': 'media_open',
                'kernel': 'mdk',
                'path': '/media/a.mkv',
                'messages': {'kernel': 'not shown here'},
              }
            ],
            'total': 1,
          };
        }),
        read('diagnostics.errors', (input) async {
          asked.add(input);
          return {
            'recording': true,
            'thisRun': {'errors': 2, 'occurrences': 5},
            'uncleanExits': {
              'total': 3,
              'unread': 1,
              'latestDetectedAt': '2026-10-22T01:00:00.000Z',
            },
          };
        }),
      ]));
      expect(body['playback'], {
        'state': 'error',
        'path': '/media/a.mkv',
        'error': {
          'stage': 'media_open',
          'category': 'unsupported_format',
          'failureId': 'pf-1',
        },
        'lastFailure': {
          'failureId': 'pf-1',
          'at': '2026-10-22T00:00:00.000Z',
          'category': 'unsupported_format',
          'stage': 'media_open',
          'kernel': 'mdk',
          'path': '/media/a.mkv',
        },
      });
      expect(body['diagnostics'], {
        'recording': true,
        'uncaughtErrors': 2,
        'uncaughtOccurrences': 5,
        'uncleanExitUnread': true,
        'uncleanExitsUnread': 1,
        'latestUncleanExitAt': '2026-10-22T01:00:00.000Z',
      });
      expect(asked, [
        {'limit': 1},
        {'summaryOnly': true},
      ]);
    });

    test('nothing failed and nothing playing is still idle alone', () async {
      final body = await bodyOf(_Fixture([
        read('playback.state', (_) async => {
              'state': {'status': 'idle', 'hasVideo': false}
            }),
        read('playback.failures', (_) async => {'failures': [], 'total': 0}),
      ]));
      expect(body['playback'], {'state': 'idle'});
      expect(body['diagnostics'], containsPair('unavailable', 'diagnostics.errors'));
    });

    test('a part that cannot be read says why, without hiding the rest',
        () async {
      final body = await bodyOf(_Fixture([
        read('state.query', (input) async {
          if (input['view'] == 'media.sources') {
            throw const Failure(FailureCode.unavailable, 'source list broke');
          }
          return {'rows': <Map>[]};
        }),
        read('storage.status', (_) async => {'volumes': <Map>[]}),
      ]));
      final sources = body['sources'] as Map;
      expect(sources['unavailable'], 'state.query');
      expect(sources['reason'], containsPair('code', 'unavailable'));
      expect((sources['reason'] as Map)['message'], contains('source list broke'));
      expect((body['network'] as Map)['observed'], 0);
      expect(body['space'], isNull);
      // A part whose action does not exist at all is told the same way.
      final missing = body['accounts'] as Map;
      expect(missing['unavailable'], 'accounts.status');
      expect(missing['reason'], isNotNull);
    });
  });

  test(
      'enable rotates private credentials while preserving every repository file',
      () async {
    await endpoint.start(repository);
    final original = jsonDecode(await credentials.readAsString()) as Map;
    final config = File('${repository.path}/.codex/config.toml');
    await config.parent.create();
    await config.writeAsString('User configuration');
    final before = await config.stat();
    await endpoint.stop();
    final running = await endpoint.start(repository) as AgentEndpointRunning;
    final rotated = jsonDecode(await credentials.readAsString()) as Map;
    expect(rotated['token'], isNot(original['token']));
    expect(await config.readAsString(), 'User configuration');
    expect((await config.stat()).modified, before.modified);
    if (!Platform.isWindows) {
      expect((await credentials.stat()).mode & 0x1ff, 0x180);
    }
    for (final path in ['/mcp', '/harness']) {
      final rejected = await client.postUrl(running.url.replace(path: path));
      rejected.headers.set('Authorization', 'Bearer ${original['token']}');
      final response = await rejected.close();
      expect(response.statusCode, 401);
      await response.drain<void>();
      final valid = await client.postUrl(running.url.replace(path: path));
      valid.headers.set('Authorization', 'Bearer ${rotated['token']}');
      valid.write(jsonEncode(path == '/mcp'
          ? {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}
          : {'operation': 'list'}));
      final accepted = await valid.close();
      expect(accepted.statusCode, 200);
      await accepted.drain<void>();
    }
  });

  test(
      'status endpoint and seed CLI expose seed location and fresh lag without fetching',
      () async {
    final cli = await File('assets/next/harness/nipa').readAsBytes();
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {'nipa': cli},
        appVersion: 'x8-fixture',
        instanceFacts: () async => {'pid': pid, 'windowTitle': 'Fixture'},
        credentialFile: credentials,
        port: 0);
    await endpoint.start(repository);
    final seedFile = File('${endpoint.seedRepository.path}/nipa');
    await seedFile
        .writeAsString('${await seedFile.readAsString()}\n# fixture upgrade\n');
    final commit = await Process.run(
        'git',
        [
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@localhost',
          '-c',
          'commit.gpgSign=false',
          '-c',
          'core.hooksPath=${endpoint.seedRepository.path}/.git/no-hooks',
          'commit',
          '-am',
          'Fixture upgrade'
        ],
        workingDirectory: endpoint.seedRepository.path);
    expect(commit.exitCode, 0, reason: commit.stderr.toString());
    final result = await Process.run(
        pythonCommand, [ppath.join(repository.path, 'nipa'), 'status'],
        workingDirectory: repository.path,
        environment: {'NIPAPLAY_ENDPOINT_FILE': credentials.path});
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final value = jsonDecode(result.stdout as String) as Map;
    expect(value['harnessSeed']['path'], endpoint.seedRepository.absolute.path);
    expect(value['harnessSeed']['trackingBehindSeed'], true);
    // ignore: avoid_print
    print('X8 nipa status: ${jsonEncode(value)}');
  });

  test('an unknown action names the actions that end the same way', () async {
    endpoint = AgentEndpoint(
        harness: Harness([_WriteCapability()]),
        seed: {},
        appVersion: 'test',
        credentialFile: credentials,
        port: 0);
    final running = await endpoint.start(repository) as AgentEndpointRunning;
    final token = (jsonDecode(await credentials.readAsString()) as Map)['token'];
    final call = await client.postUrl(running.url.replace(path: '/harness'));
    call.headers.set('Authorization', 'Bearer $token');
    call.write(jsonEncode(
        {'operation': 'call', 'action': 'other.write', 'input': {}}));
    final response = await call.close();
    expect(response.statusCode, 404);
    final body = jsonDecode(await utf8.decodeStream(response)) as Map;
    expect(body['similar'], ['fixture.write']);
  });

  test(
      'chat disclosure revokes both endpoints and records session origin without credentials',
      () async {
    final journal = File('${root.path}/invocations.jsonl');
    endpoint = AgentEndpoint(
        harness:
            Harness([_WriteCapability()], observers: [JsonlJournal(journal)]),
        seed: {},
        appVersion: 'test',
        credentialFile: credentials,
        port: 0);
    final running = await endpoint.start(repository) as AgentEndpointRunning;
    final before = jsonDecode(await credentials.readAsString()) as Map;
    final call = await client.postUrl(running.url.replace(path: '/harness'));
    call.headers.set('Authorization', 'Bearer ${before['token']}');
    call.headers.set('X-NipaPlay-Chat', 'nipa-session-123');
    call.write(jsonEncode(
        {'operation': 'call', 'action': 'fixture.write', 'input': {}}));
    final response = await call.close();
    expect(response.statusCode, 200);
    await response.drain<void>();
    expect(jsonDecode(await journal.readAsString())['origin'],
        'harness_cli:chat:nipa-session-123');
    final helperCall = await client.postUrl(running.url.replace(path: '/harness'));
    helperCall.headers.set('Authorization', 'Bearer ${before['token']}');
    helperCall.headers.set('X-NipaPlay-Chat', 'helper-job-fixture');
    helperCall.write(jsonEncode(
        {'operation': 'call', 'action': 'fixture.write', 'input': {}}));
    await (await helperCall.close()).drain<void>();
    expect(jsonDecode((await journal.readAsLines()).last)['origin'],
        'harness_cli:helper:job-fixture');
    final nativeCall = await client.postUrl(running.url.replace(path: '/harness'));
    nativeCall.headers.set('Authorization', 'Bearer ${before['token']}');
    nativeCall.headers
        .set('X-NipaPlay-Chat', 'native-5fa829c2-07bb-4418-b09d-f233b8c7d371');
    nativeCall.write(jsonEncode(
        {'operation': 'call', 'action': 'fixture.write', 'input': {}}));
    await (await nativeCall.close()).drain<void>();
    expect(jsonDecode((await journal.readAsLines()).last)['origin'],
        'codex_native:5fa829c2-07bb-4418-b09d-f233b8c7d371');
    expect(
        endpoint.chatEnvironment({
          'PATH': '/bin',
          'NIPAPLAY_AGENT_TOKEN': 'synthetic',
          'OTHER': before['token'] as String
        }),
        {
          'PATH': '/bin',
          'NO_PROXY': '127.0.0.1,localhost,::1',
          'no_proxy': '127.0.0.1,localhost,::1'
        });
    expect(endpoint.chatEnvironment({'no_proxy': '.corp, localhost'})['NO_PROXY'],
        '.corp,localhost,127.0.0.1,::1');
    await endpoint.inspectChatText('output: ${before['token']}');
    final after = jsonDecode(await credentials.readAsString()) as Map;
    expect(after['token'], isNot(before['token']));
    for (final path in ['/mcp', '/harness']) {
      final rejected = await client.postUrl(running.url.replace(path: path));
      rejected.headers.set('Authorization', 'Bearer ${before['token']}');
      expect((await rejected.close()).statusCode, 401);
    }
    final log =
        await File('${endpoint.seedRepository.parent.path}/journal.jsonl')
            .readAsString();
    expect(log, contains('chat.endpoint_token_rotated'));
    expect(log, isNot(contains(before['token'])));
    expect(log, isNot(contains(after['token'])));
    final token = after['token'] as String;
    final (first, pending) =
        await endpoint.protectChatDelta('', token.substring(0, 20));
    expect(first, '');
    final (second, remainder) =
        await endpoint.protectChatDelta(pending, token.substring(20));
    expect('$first$second$remainder', isNot(contains(token)));
    final splitRotated = jsonDecode(await credentials.readAsString()) as Map;
    expect(splitRotated['token'], isNot(token));
  });

  test(
      'credentials cannot be placed inside the repository including via symlink',
      () async {
    await repository.create();
    final bad = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'test',
        credentialFile: File('${repository.path}/endpoint.json'),
        port: 0);
    expect(await bad.start(repository), isA<AgentEndpointFailed>());
    if (!Platform.isWindows) {
      await Link('${root.path}/alias').create(repository.path);
      final aliased = AgentEndpoint(
          harness: Harness([]),
          seed: {},
          appVersion: 'test',
          credentialFile: File('${root.path}/alias/private/endpoint.json'),
          port: 0);
      expect(await aliased.start(repository), isA<AgentEndpointFailed>());
    }
    expect(await credentials.exists(), isFalse);
  });
}

final class _WriteCapability implements Capability {
  @override
  List<Action> get actions => [_WriteAction()];
}

final class _WriteAction extends Action<NoInput, NoInput> {
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'fixture.write',
      title: 'Write',
      description: 'Fixture',
      effect: Effect.write,
      input: ObjectSchema({}),
      output: ObjectSchema({}));
  @override
  NoInput decodeInput(JsonMap json) => const NoInput();
  @override
  Future<Outcome<NoInput>> run(NoInput input, Invocation invocation) async =>
      const Completed(NoInput());
}

final class _Fixture implements Capability {
  _Fixture(this.actions);
  @override
  final List<Action> actions;
}
