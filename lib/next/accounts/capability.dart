import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/bangumi_sync_service.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'service.dart';

const _provider = StringSchema(values: ['dandanplay', 'bangumi']);
const _id = IntegerSchema(minimum: 1);
const _output = ObjectSchema({}, additionalProperties: true);
const _collectionChange = ObjectSchema({
  'workId': _id,
  'status': StringSchema(values: [
    'favorited',
    'finished',
    'abandoned',
    'wish',
    'done',
    'doing',
    'onHold',
    'dropped'
  ]),
  'rating': IntegerSchema(minimum: 1, maximum: 10),
  'comment': StringSchema(),
  'private': BooleanSchema(),
  'remove': BooleanSchema(),
}, required: [
  'workId'
]);

final class AccountsCapability implements Capability {
  AccountsCapability(AccountsService service)
      : actions = [for (final spec in _specs) _AccountAction(spec, service)];
  @override
  final List<Action> actions;
}

const _specs = [
  ActionSpec(
      id: 'accounts.status',
      title: 'Read account login state',
      description:
          'Read Classic Dandanplay and Bangumi login state without exposing credentials. This is local state, not a live server check.',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: _output),
  ActionSpec(
      id: 'accounts.login',
      title: 'Initiate account login',
      description:
          'Log in through the Classic account service. Without a user-provided secret, the user logs in in NipaPlay’s own window: while the Next interface shows, a 需要登录 card under your reply opens it when they press it; otherwise the window opens at once. Dandanplay uses username/password; Bangumi uses a personal access token. A secret voluntarily supplied by the user in conversation may be passed here; never search for secrets. Returns a jobId; it ends when they log in or close the window, so task.wait or a followup on it tells you. Secrets stay in memory until authentication and never enter job inputs or receipts.',
      effect: Effect.write,
      input: ObjectSchema({
        'provider': _provider,
        'username': StringSchema(minLength: 1),
        'password': StringSchema(minLength: 1, secret: true),
        'accessToken': StringSchema(minLength: 1, secret: true),
      }, required: [
        'provider'
      ]),
      output: _output),
  ActionSpec(
      id: 'accounts.logout',
      title: 'Log out of an account',
      description:
          'Clear Classic login state and its saved credential for the selected provider.',
      effect: Effect.write,
      input: ObjectSchema({'provider': _provider}, required: ['provider']),
      output: _output),
  ActionSpec(
      id: 'accounts.collections.list',
      title: '按状态列出收藏',
      description: 'List anime collections through the Classic account client. '
          'statuses use this provider\'s names (Dandanplay favorited/finished/abandoned; '
          'Bangumi wish/done/doing/onHold/dropped); omitted or empty means all. '
          'items contain provider workId, status and rating (null when the list does not supply it). '
          'Pass nextCursor with the same provider/statuses/limit. No per-work requests. '
          'Pages observe the live provider list; remote changes can shift Bangumi offsets.',
      effect: Effect.read,
      input: ObjectSchema({'provider': _provider,
        'statuses': ArraySchema(StringSchema()),
        'limit': IntegerSchema(minimum: 1, maximum: 100),
        'cursor': StringSchema(minLength: 1)}, required: ['provider']),
      output: ObjectSchema({
        'items': ArraySchema(ObjectSchema({'workId': _id,
          'status': StringSchema(), 'rating': IntegerSchema(nullable: true)},
          required: ['workId', 'status', 'rating'])),
        'nextCursor': StringSchema(nullable: true)
      }, required: ['items', 'nextCursor'])),
  ActionSpec(
      id: 'accounts.collections.get',
      title: 'Read favorites, ratings and work status',
      description:
          'Read current account collections for a batch of work IDs through Classic. Dandanplay workId is animeId; Bangumi workId is subjectId. Returns each request result or failure independently.',
      effect: Effect.read,
      input: ObjectSchema({'provider': _provider, 'workIds': ArraySchema(_id)},
          required: ['provider', 'workIds']),
      output: _output),
  ActionSpec(
      id: 'accounts.collections.update',
      title: 'Update favorites, ratings and work status',
      description:
          'Update a batch through Classic. Dandanplay statuses: favorited/finished/abandoned; remove=true removes a favorite. Bangumi statuses: wish/done/doing/onHold/dropped; private is Bangumi-only. Rating is 1–10; omitted fields remain unchanged. New Bangumi collections require status. Per-item acknowledged results describe writes; collections.get reads back current state.',
      effect: Effect.write,
      input: ObjectSchema(
          {'provider': _provider, 'items': ArraySchema(_collectionChange)},
          required: ['provider', 'items']),
      output: _output),
  ActionSpec(
      id: 'accounts.episodes.get',
      title: 'Read account episode watch state',
      description:
          'Read remote episode state through Classic. Bangumi requires workId and returns episode collections; Dandanplay returns its account play history. Request failures remain failures.',
      effect: Effect.read,
      input: ObjectSchema({'provider': _provider, 'workId': _id},
          required: ['provider']),
      output: _output),
  ActionSpec(
      id: 'accounts.episodes.update',
      title: 'Update account episode watch state',
      description:
          'Mark a batch of episode IDs watched through Classic. Both providers accept only state=2, as in Classic episode progress. Each write is acknowledged independently.',
      effect: Effect.write,
      input: ObjectSchema({
        'provider': _provider,
        'items': ArraySchema(ObjectSchema(
            {'episodeId': _id, 'state': IntegerSchema(minimum: 2, maximum: 2)},
            required: ['episodeId', 'state']))
      }, required: [
        'provider',
        'items'
      ]),
      output: _output),
  ActionSpec(
      id: 'accounts.bangumi.sync',
      title: 'Synchronize watch history to Bangumi',
      description:
          'Run Classic’s local-watch-history-to-Bangumi sync. Incremental by default; full=true repeats all works. Returns a task for task.wait with Classic per-work results, including partial failures. Interrupted writes are not automatically replayed.',
      effect: Effect.write,
      input: ObjectSchema({'full': BooleanSchema()}),
      output: _output),
  ActionSpec(
      id: 'accounts.bangumi.sync_status',
      title: 'Read Bangumi sync statistics',
      description: 'Read Classic’s saved last sync time and per-work summary.',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: _output),
];

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _AccountAction extends Action<_Json, _Json> {
  _AccountAction(this.spec, this.service);
  @override
  final ActionSpec spec;
  final AccountsService service;
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json decoded, Invocation invocation) async {
    final input = decoded.value;
    try {
      final provider = input['provider'] as String?;
      final JsonMap result;
      switch (spec.id) {
        case 'accounts.status':
          result = {
            'accounts': [
              service.status('dandanplay'),
              service.status('bangumi')
            ]
          };
        case 'accounts.login':
          result = await service.login(input);
        case 'accounts.logout':
          result = await service.logout(provider!);
        case 'accounts.collections.get':
          result = await batch(input['workIds'] as List,
              (id) => service.collection(provider!, id as int));
        case 'accounts.collections.list':
          result = await service.collections(input);
        case 'accounts.collections.update':
          result = await batch(
              input['items'] as List,
              (item) => service.updateCollection(
                  provider!, Map<String, Object?>.from(item as Map)));
        case 'accounts.episodes.get':
          result = await service.episodes(provider!, input);
        case 'accounts.episodes.update':
          result = await batch(
              input['items'] as List,
              (item) => service.updateEpisode(
                  provider!, Map<String, Object?>.from(item as Map)));
        case 'accounts.bangumi.sync':
          result = await service.sync(input);
        case 'accounts.bangumi.sync_status':
          result =
              service.checked(await BangumiSyncService.getSyncStatistics());
        default:
          throw StateError(spec.id);
      }
      return Completed(_Json(result));
    } on Failure catch (error) {
      return Failed(error);
    } catch (error) {
      return Failed(
          Failure(FailureCode.unavailable, SecretRedactor.text('$error')));
    }
  }

  Future<JsonMap> batch(
      List items, Future<JsonMap> Function(Object?) run) async {
    if (items.isEmpty || items.length > 100) {
      throw const Failure(FailureCode.invalidInput, 'Supply 1 to 100 items.');
    }
    final results = <JsonMap>[];
    for (var i = 0; i < items.length; i++) {
      try {
        results.add(
            {'index': i, 'status': 'completed', 'result': await run(items[i])});
      } catch (error) {
        final failure = error is Failure
            ? error
            : Failure(FailureCode.unavailable, SecretRedactor.text('$error'));
        results
            .add({'index': i, 'status': 'failed', 'error': failure.toJson()});
      }
    }
    return {'results': results};
  }
}
