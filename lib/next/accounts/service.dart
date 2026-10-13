import 'dart:async';
import 'collections.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';
import 'package:nipaplay/services/bangumi_sync_service.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/security/credential_vault.dart';
import '../media/identity_store.dart';

final class AccountsService {
  late TaskEngine engine;
  StreamSubscription<Job>? _events;
  Future<JsonMap?> Function(JsonMap, Future<void>)? requestLogin;
  final Map<String, JsonMap> _credentials = {};

  void attach(TaskEngine value) {
    engine = value;
    _events = engine.changes.listen((job) {
      if (job.type == 'accounts.login' && job.state.isTerminal) {
        _credentials.remove(job.jobId);
      }
    });
  }

  Future<void> close() async {
    await _events?.cancel();
    _credentials.clear();
  }

  JsonMap status(String provider) => {
        'provider': provider,
        'loggedIn': provider == 'dandanplay'
            ? DandanplayService.isLoggedIn
            : BangumiApiService.isLoggedIn,
        'username': provider == 'dandanplay'
            ? DandanplayService.userName
            : BangumiApiService.userInfo?['username'],
      };

  void requireLogin(String provider) {
    if (status(provider)['loggedIn'] != true) {
      throw const Failure(
          FailureCode.unavailable, 'Log in to this account first.');
    }
  }

  JsonMap checked(Map<String, dynamic> result) {
    if (result['success'] != true) {
      throw Failure(
          FailureCode.unavailable,
          SecretRedactor.text(
              '${result['message'] ?? result['errorMessage'] ?? 'Account request failed.'}'));
    }
    return Map<String, Object?>.from(result);
  }

  Future<JsonMap> login(JsonMap input) async {
    final provider = input['provider'] as String;
    final secretKey = provider == 'dandanplay' ? 'password' : 'accessToken';
    if (input
        .containsKey(provider == 'dandanplay' ? 'accessToken' : 'password')) {
      throw const Failure(
          FailureCode.invalidInput, 'Secret belongs to a different provider.');
    }
    final supplied = input[secretKey] != null;
    if (supplied && provider == 'dandanplay' && input['username'] == null) {
      throw const Failure(FailureCode.invalidInput,
          'A username is required with the password.');
    }
    if (!supplied && requestLogin == null) {
      throw const Failure(FailureCode.unavailable,
          'The NipaPlay login window is not attached.');
    }
    for (final job in await engine.list(type: 'accounts.login')) {
      if (!job.state.isTerminal) {
        throw const Failure(
            FailureCode.conflict, 'An account login is already pending.');
      }
    }
    final id = newMediaId('account-login');
    if (supplied) {
      SecretRedactor.remember(
          CredentialRef('account_login', id), input[secretKey] as String);
      _credentials[id] = {
        'username': input['username'],
        secretKey: input[secretKey]
      };
    }
    try {
      final job = await engine.submit(
          type: 'accounts.login',
          jobId: id,
          title: 'Log in to $provider',
          input: {
            'provider': provider,
            'method': supplied ? 'provided' : 'window',
            if (input['username'] != null) 'username': input['username']
          });
      return {'provider': provider, 'method': job.input['method'], 'jobId': id};
    } catch (_) {
      _credentials.remove(id);
      rethrow;
    }
  }

  Future<void> completeLogin(JobContext c) async {
    final provider = c.job.input['provider'] as String;
    await c.running(phase: 'awaiting_credentials');
    try {
      if (c.job.input['method'] == 'window' && requestLogin == null) {
        throw const Failure(FailureCode.unavailable,
            'Login window is not attached; start a new login.');
      }
      final credentials = c.job.input['method'] == 'provided'
          ? _credentials.remove(c.job.jobId)
          : await requestLogin!(c.job.input, c.stopRequested);
      if (credentials == null) {
        if (c.job.input['method'] == 'provided') {
          throw const Failure(FailureCode.unavailable,
              'User-provided credentials were discarded at restart; start a new login.');
        }
        final job = await c.snapshot();
        if (job.cancelRequestedAt == null) await engine.cancel(c.job.jobId);
        await c.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged,
            details: status(provider)));
        return;
      }
      if ((await c.snapshot()).cancelRequestedAt != null) {
        await c.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged,
            details: status(provider)));
        return;
      }
      final secretKey = provider == 'dandanplay' ? 'password' : 'accessToken';
      SecretRedactor.remember(CredentialRef('account_login', c.job.jobId),
          credentials[secretKey] as String);
      await c.report(phase: 'authenticating');
      checked(provider == 'dandanplay'
          ? await DandanplayService.login(credentials['username'] as String,
              credentials['password'] as String)
          : await BangumiApiService.saveAccessToken(
              credentials['accessToken'] as String));
      await c.markSideEffectCommitted();
      if (status(provider)['loggedIn'] != true) {
        throw const Failure(FailureCode.conflict,
            'Authentication was accepted but Classic login state did not change.');
      }
      await c.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
        ...status(provider),
        'verificationMeaning':
            'Classic authentication response accepted and local login state read back.'
      }));
    } on Failure catch (error) {
      await c.fail(
          error,
          JobReceipt(
              verification: VerificationLevel.acknowledged,
              details: status(provider)));
    } finally {
      _credentials.remove(c.job.jobId);
    }
  }

  Future<JsonMap> logout(String provider) async {
    for (final job in await engine.list(type: 'accounts.login')) {
      if (job.input['provider'] == provider && !job.state.isTerminal) {
        throw const Failure(FailureCode.conflict,
            'Cancel the pending login before logging out.');
      }
    }
    if (provider == 'dandanplay') {
      await DandanplayService.clearLoginInfo();
    } else {
      checked(await BangumiApiService.clearAccessToken());
    }
    return status(provider);
  }

  Future<JsonMap> collection(String provider, int id) async {
    requireLogin(provider);
    if (provider == 'bangumi') {
      return {
        'provider': provider,
        'workId': id,
        'collection':
            checked(await BangumiApiService.getUserCollection(id))['data']
      };
    }
    final favorites =
        checked(await DandanplayService.getUserFavorites())['favorites']
            as List;
    final details =
        checked(await DandanplayService.getBangumiDetails(id))['bangumi']
            as Map;
    return {
      'provider': provider,
      'workId': id,
      'collection':
          favorites.cast<Map>().where((f) => f['animeId'] == id).firstOrNull,
      'rating': details['userRating'] ?? 0
    };
  }

  Future<JsonMap> collections(JsonMap input) async {
    final provider = input['provider'] as String;
    requireLogin(provider);
    return listCollections(input,
      bangumi: (offset, limit) async => checked(await BangumiApiService.getUserCollections(offset: offset, limit: limit))['data'] as JsonMap,
      dandanplay: () async => (checked(await DandanplayService.getUserFavorites())['favorites'] as List).cast<JsonMap>());
  }

  Future<JsonMap> updateCollection(String provider, JsonMap item) async {
    requireLogin(provider);
    final id = item['workId'] as int;
    if (!['status', 'rating', 'comment', 'private', 'remove']
        .any(item.containsKey)) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply a collection property.');
    }
    if (provider == 'dandanplay') {
      if (item.containsKey('private')) {
        throw const Failure(FailureCode.invalidInput,
            'Dandanplay has no private collection field.');
      }
      final status = item['status'] as String?;
      if (status != null &&
          !['favorited', 'finished', 'abandoned'].contains(status)) {
        throw const Failure(FailureCode.invalidInput,
            'Dandanplay status: favorited, finished, abandoned.');
      }
      if (item['remove'] == true) {
        if (['status', 'rating', 'comment'].any(item.containsKey)) {
          throw const Failure(FailureCode.invalidInput,
              'Remove cannot include collection changes.');
        }
        checked(await DandanplayService.removeFavorite(id));
      } else {
        checked(await DandanplayService.addFavorite(
            animeId: id,
            favoriteStatus: status,
            rating: item['rating'] as int? ?? 0,
            comment: item['comment'] as String?));
      }
    } else {
      if (item.containsKey('remove')) {
        throw const Failure(FailureCode.invalidInput,
            'Bangumi Classic client supports collection status updates.');
      }
      final status = item['status'] as String?;
      const types = {
        'wish': 1,
        'done': 2,
        'doing': 3,
        'onHold': 4,
        'dropped': 5
      };
      if (status != null && !types.containsKey(status)) {
        throw const Failure(FailureCode.invalidInput,
            'Bangumi status: wish, done, doing, onHold, dropped.');
      }
      final existing =
          checked(await BangumiApiService.getUserCollection(id))['data'];
      if (existing == null && status == null) {
        throw const Failure(FailureCode.invalidInput,
            'A new Bangumi collection requires status.');
      }
      checked(await BangumiApiService.updateUserCollection(id,
          type: types[status],
          rate: item['rating'] as int?,
          comment: item['comment'] as String?,
          private: item['private'] as bool?));
    }
    return {'provider': provider, 'workId': id, 'acknowledged': true};
  }

  Future<JsonMap> episodes(String provider, JsonMap input) async {
    requireLogin(provider);
    if (provider == 'bangumi') {
      if (input['workId'] == null) {
        throw const Failure(
            FailureCode.invalidInput, 'Bangumi episodes require workId.');
      }
      return {
        'provider': provider,
        'data': checked(await BangumiApiService.getUserEpisodeCollections(
            input['workId'] as int))['data']
      };
    }
    // Read the throwing service entry; getEpisodesWatchStatus masks request failures as unwatched.
    return {
      'provider': provider,
      'data': checked(await DandanplayService.getUserPlayHistory())
    };
  }

  Future<JsonMap> updateEpisode(String provider, JsonMap item) async {
    requireLogin(provider);
    final id = item['episodeId'] as int, state = item['state'] as int;
    if (state != 2) {
      throw const Failure(FailureCode.invalidInput, 'Classic episode progress accepts only watched (state=2).');
    }
    if (provider == 'dandanplay') {
      // Classic ignores isWatched=false and still posts playhistory. Do not claim an undo.
      if (state != 2) {
        throw const Failure(FailureCode.invalidInput,
            'Dandanplay supports marking watched (state=2).');
      }
      await DandanplayService.updateEpisodeWatchStatus(id, true);
    } else {
      checked(await BangumiApiService.updateEpisodeCollection(id, state));
    }
    return {
      'provider': provider,
      'episodeId': id,
      'state': state,
      'acknowledged': true
    };
  }

  Future<JsonMap> sync(JsonMap input) async {
    requireLogin('bangumi');
    for (final job in await engine.list(type: 'accounts.bangumi.sync')) {
      if (!job.state.isTerminal) {
        throw const Failure(
            FailureCode.conflict, 'Bangumi sync is already pending.');
      }
    }
    final job = await engine.submit(
        type: 'accounts.bangumi.sync',
        title: 'Synchronize watch history to Bangumi',
        input: input);
    return {'jobId': job.jobId};
  }

  Future<void> completeSync(JobContext c) async {
    await c.running(phase: 'sync');
    // The Classic sync can commit per-work effects. An interrupted sync is not replayed.
    await c.markSideEffectCommitted();
    final result = await BangumiSyncService.syncWatchHistoryToBangumi(
        forceFullSync: c.job.input['full'] == true);
    if (result['success'] == true && (result['errorCount'] as int? ?? 0) == 0) {
      final saved = checked(await BangumiSyncService.getSyncStatistics());
      if (result['totalAnimes'] != null &&
          (saved['lastSyncStatus'] as Map?)?['successCount'] !=
              result['successCount']) {
        throw const Failure(
            FailureCode.conflict, 'Bangumi sync summary readback differs.');
      }
      await c.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
        ...result,
        'verificationMeaning':
            'Classic sync completed without per-work errors; saved summary read back. Remote per-episode state is not independently verified.'
      }));
    } else {
      await c.fail(
          Failure(FailureCode.unavailable, '${result['message']}'),
          JobReceipt(verification: VerificationLevel.acknowledged, details: {
            ...result,
            'partial': (result['errorCount'] as int? ?? 0) > 0
          }));
    }
  }
}

List<JobExecutor> accountExecutors(AccountsService service) => [
      _Executor('accounts.login', service.completeLogin),
      _Executor('accounts.bangumi.sync', service.completeSync),
    ];

final class _Executor implements JobExecutor {
  _Executor(this.type, this.run);
  @override
  final String type;
  final Future<void> Function(JobContext) run;
  @override
  Future<void> execute(JobContext c) => run(c);
  @override
  Future<void> recover(JobContext c) async {
    if (c.job.sideEffectCommitted) {
      await c.fail(
          const Failure(FailureCode.unavailable,
              'Account operation was interrupted after effects; query live state before retrying.'),
          JobReceipt(
              verification: VerificationLevel.acknowledged,
              details: {'interrupted': true, 'partial': true}));
    } else {
      await run(c);
    }
  }
}
