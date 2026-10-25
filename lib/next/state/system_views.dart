import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';

import 'query.dart';

/// Where the system views read from. Each supplier reports what the part of
/// the media system knows now; none of them contacts a server or starts
/// anything. A missing supplier leaves its views out.
final class SystemStatusSources {
  /// `MediaSourcesService.list(withFacts: true)`.
  Future<List<JsonMap>> Function()? sources;

  /// One row per account: provider, loggedIn, username, lastSyncAt.
  Future<List<JsonMap>> Function()? accounts;

  /// The results of `network.status`, `storage.status`, the local library
  /// roots and `app.update.status`.
  Future<JsonMap> Function()? network, storage, scan, update;

  /// `HarnessHooks.status()`.
  Future<JsonMap> Function()? hooks;

  /// `DownloadRuntime.engineStatus()`.
  Future<List<JsonMap>> Function()? downloadEngines;

  /// `DownloadRuntime.qbittorrentTorrents()`.
  Future<List<JsonMap>> Function()? downloadTorrents;
}

StringSchema _text(String description) =>
    StringSchema(description: description, nullable: true);
IntegerSchema _int(String description) =>
    IntegerSchema(description: description, nullable: true);
BooleanSchema _bool(String description) =>
    BooleanSchema(description: description, nullable: true);

final _time = _text('UTC ISO-8601 time of the observation; null when none.');
final _code = _text('Stable failure code; exception text is never kept.');

final _addressFields = {
  'role': _text(
      'lan or wan for SMB and WebDAV; the address id for Jellyfin and Emby; address for a source with one address.'),
  'label': _text('Name of the address, when it has one.'),
  'address': _text('Configured address, without credentials.'),
  'enabled': _bool('Whether the address is in use; null when not applicable.'),
  'reachability': _text(
      'Result of the last attempt on this address: reachable, unreachable or unknown (never attempted).'),
  'lastAttemptAt': _time,
  'lastSuccessAt': _time,
  'lastFailureAt': _time,
  'errorCode': _code,
  'latencyMs': _int('Duration of the last attempt in milliseconds.'),
};

String? _redacted(Object? value) =>
    value == null ? null : SecretRedactor.text('$value');

Map _map(Object? value) => value is Map ? value : const {};

StateView _view(String name, String description, Map<String, Schema> fields,
    Future<List<JsonMap>> Function() rows,
    {Map<String, StateRelation> relations = const {}}) {
  return StateView(
      name: name,
      description: description,
      fields: ObjectSchema(fields),
      relations: relations,
      read: (offset, limit) async =>
          (await rows()).skip(offset).take(limit).toList());
}

List<StateView> systemStateViews(SystemStatusSources s) {
  Future<List<JsonMap>> sourceRows() async => await s.sources!();
  return [
    if (s.sources != null) ...[
      _view(
          'media.sources',
          'Configured media sources with what was last observed of each, kept across restarts. Every time is the moment of that observation (null: none); nothing here contacts a server. reachability unknown means no attempt was observed, not that the address is down. credentialState: none (the source needs no login), saved (a login is on record; the vault is not read), missing (a login is needed and none is saved) or rejected (the source refused the saved login after it last accepted one). Credentials are never part of the facts.',
          {
            'sourceId': _text('Source ID, as in media.sources.list.'),
            'type': _text('smb, webdav, jellyfin, emby, nipaplay or dandanplay_remote.'),
            'name': _text('Source name.'),
            'address': _text('Address in use now.'),
            'username': _text('Configured account name; empty when none.'),
            'connectionState':
                _text('connected, unverified or failed (last observed).'),
            'connected': _bool('Last observed connection.'),
            'selectedLibraryCount': _int('Libraries selected for sync.'),
            'addressCount': _int('Configured addresses.'),
            'unreachableAddressCount':
                _int('Addresses whose last attempt failed.'),
            'credentialState': _text('none, saved, missing or rejected.'),
            'credentialLastRejectedAt': _time,
            'credentialLastRejectedCode': _code,
            'credentialLastVerifiedAt': _time,
            'lastCheckAt': _time,
            'lastCheckResult': _text('succeeded or failed.'),
            'lastCheckErrorCode': _code,
            'lastCheckLatencyMs': _int('Duration of the last check.'),
            'syncResult': _text(
                'running, succeeded, failed, cancelled or interrupted (running when the process ended); null when no sync was observed.'),
            'syncStartedAt': _time,
            'syncFinishedAt': _time,
            'lastSyncAt': _time,
            'syncIndexed': _int('Files the last finished sync indexed.'),
            'syncErrorCode': _code,
            'syncJobId': _text('Task of the last sync; see the tasks view.'),
            'lastErrorCode': _code,
            'lastErrorAt': _time,
            'lastErrorMessage':
                _text('Source-reported text of the last failure, redacted.'),
            'addresses': ArraySchema(ObjectSchema(_addressFields),
                description: 'Every configured address with its last attempt.'),
          },
          () async => [
                for (final row in await sourceRows()) _sourceRow(row)
              ],
          relations: {
            'addressRows': const StateRelation(
                'media.source_addresses', 'sourceId', 'sourceId')
          }),
      _view(
          'media.source_addresses',
          'One row per configured address of each media source with the last attempt on it: when, what it found, a stable error code and how long it took. Classic probes SMB and WebDAV addresses at startup and when connections are tested; Jellyfin and Emby addresses when connecting; a source with one address when it is checked.',
          {
            'sourceId': _text('Source ID.'),
            'sourceType': _text('Source type.'),
            'sourceName': _text('Source name.'),
            ..._addressFields,
          },
          () async => [
                for (final row in await sourceRows())
                  for (final address in (row['addresses'] as List? ?? const []))
                    {
                      'sourceId': row['sourceId'],
                      'sourceType': row['type'],
                      'sourceName': row['name'],
                      ..._addressRow(_map(address)),
                    }
              ]),
    ],
    if (s.accounts != null)
      _view(
          'accounts',
          'Accounts of the metadata providers. loggedIn is the local state, not a live check of the server. lastSyncAt is the last Bangumi watch-history sync Classic recorded.',
          {
            'provider': _text('dandanplay or bangumi.'),
            'loggedIn': _bool('Local login state.'),
            'username': _text('Account name when logged in.'),
            'lastSyncAt': _time,
          },
          () async => await s.accounts!()),
    if (s.network != null) ...[
      _view(
          'network.routes',
          'How requests leave this device now: the proxy in effect and the Dandanplay gateway route. Observed from settings, no request is made.',
          {
            'provider': _text('proxy or dandanplay.'),
            'mode': _text('system or explicit (proxy); gateway mode (dandanplay).'),
            'host': _text('Proxy host when explicit.'),
            'port': _int('Proxy port when explicit.'),
            'effectiveGateway': _text('Gateway origin in use.'),
            'failoverUntil': _int('Unix milliseconds until which the fallback gateway is used; null when none.'),
          },
          () async {
        final r = await s.network!();
        final proxy = _map(r['effectiveProxy']);
        return [
          {
            'provider': 'proxy',
            'mode': proxy['mode'],
            'host': proxy['host'],
            'port': proxy['port'],
          },
          for (final route in (r['routes'] as List? ?? const []))
            {
              'provider': _map(route)['provider'],
              'mode': _map(route)['mode'],
              'effectiveGateway': _map(route)['effectiveGateway'],
              'failoverUntil': _map(route)['failoverUntil'],
            }
        ];
      }),
      _view(
          'network.observations',
          'The last request outcome per origin or source seen by this process. Only this process is covered and URLs and exception text are not kept; an origin never seen is absent, not reachable.',
          {
            'id': _text('Observation ID.'),
            'source': _text('Source or provider the request belonged to.'),
            'origin': _text('scheme://host:port of the request.'),
            'availability': _text('reachable or failed.'),
            'httpStatus': _int('Last HTTP status.'),
            'errorCode': _code,
            'retryable': _bool('Whether the failure is of the kind that a repeat can change.'),
            'lastAttemptAt': _time,
            'lastSuccessAt': _time,
          },
          () async {
        final r = await s.network!();
        return [
          for (final o in (r['observations'] as List? ?? const []))
            {
              'id': _map(o)['id'],
              'source': _map(o)['source'],
              'origin': _map(o)['origin'],
              'availability': _map(o)['availability'],
              'httpStatus': _map(o)['httpStatus'],
              'errorCode': _map(_map(o)['error'])['code'],
              'retryable': _map(_map(o)['error'])['retryable'],
              'lastAttemptAt': _map(o)['lastAttemptAt'],
              'lastSuccessAt': _map(o)['lastSuccessAt'],
            }
        ];
      }),
    ],
    if (s.storage != null) ...[
      _view(
          'storage.volumes',
          'Free and total space of the volumes holding app data and the library roots, as last read from the file system.',
          {
            'path': _text('Directory the volume was read for.'),
            'availableBytes': _int('Free bytes; null when unreadable.'),
            'totalBytes': _int('Total bytes; null when unreadable.'),
            'error': _code,
            'observedAt': _time,
          },
          () async {
        final r = await s.storage!();
        return [
          for (final v in (r['volumes'] as List? ?? const []))
            {
              'path': _map(v)['path'],
              'availableBytes': _map(v)['availableBytes'],
              'totalBytes': _map(v)['totalBytes'],
              'error': _map(v)['error'] is Map
                  ? _map(_map(v)['error'])['code']
                  : _map(v)['error'],
              'observedAt': r['observedAt'],
            }
        ];
      }),
      _view(
          'storage.directories',
          'Size of each directory NipaPlay keeps. Parents include their children, so the sizes do not add up. disposable: can be fetched again; uniqueData: holds what exists nowhere else.',
          {
            'role': _text('Directory role.'),
            'path': _text('Directory.'),
            'bytes': _int('Size in bytes; null when unreadable.'),
            'error': _code,
            'disposable': _bool('Can be recreated.'),
            'uniqueData': _bool('Holds data that exists nowhere else.'),
            'overlap': _text('Note on containing other directories.'),
            'observedAt': _time,
          },
          () async {
        final r = await s.storage!();
        return [
          for (final d in (r['directories'] as List? ?? const []))
            {
              'role': _map(d)['role'],
              'path': _map(d)['path'],
              'bytes': _map(d)['bytes'],
              'error': _map(d)['error'] is Map
                  ? _map(_map(d)['error'])['code']
                  : _map(d)['error'],
              'disposable': _map(d)['disposable'],
              'uniqueData': _map(d)['uniqueData'],
              'overlap': _map(d)['overlap'],
              'observedAt': r['observedAt'],
            }
        ];
      }),
    ],
    if (s.scan != null)
      _view(
          'library.scan',
          'The Classic library scan now: whether it runs, its progress and message, the scanned folders and the files that failed recognition with the recorded reason. One row.',
          {
            'scanning': _bool('A scan is running.'),
            'progress': const NumberSchema(
                nullable: true, description: 'Scan progress from 0 to 1.'),
            'message': _text('Scan message.'),
            'totalFilesFound': _int('Files found by the current or last scan.'),
            'rootCount': _int('Scanned folders.'),
            'failedFileCount': _int('Files that failed recognition.'),
            'roots': const ArraySchema(StringSchema(nullable: true),
                description: 'Scanned folders.'),
            'failedFiles': ArraySchema(
                ObjectSchema({
                  'path': _text('File.'),
                  'reason': _text('Recorded reason.'),
                }),
                description: 'Files that failed recognition.'),
          },
          () async {
        final r = await s.scan!();
        final roots = (r['roots'] as List? ?? const []);
        final failed = (r['failedFiles'] as List? ?? const []);
        return [
          {
            'scanning': r['scanning'],
            'progress': r['progress'],
            'message': _redacted(r['message']),
            'totalFilesFound': r['totalFilesFound'],
            'rootCount': roots.length,
            'failedFileCount': failed.length,
            'roots': roots,
            'failedFiles': [
              for (final f in failed)
                {
                  'path': _map(f)['path'],
                  'reason': _redacted(_map(f)['reason'])
                }
            ],
          }
        ];
      }),
    if (s.update != null)
      _view(
          'app.update',
          'The last update check made by this process. checked=false: none yet. One row.',
          {
            'checking': _bool('A check is running.'),
            'checked': _bool('This process has made a check.'),
            'checkedAt': _time,
            'currentVersion': _text('Version running.'),
            'latestVersion': _text('Latest published version; null when the check failed.'),
            'hasUpdate': _bool('A newer version is published; null when the check failed.'),
            'publishedAt': _text('Publication time of the latest version.'),
            'errorCode': _code,
          },
          () async {
        final r = await s.update!();
        final result = _map(r['result']);
        return [
          {
            'checking': r['checking'],
            'checked': r['checked'],
            'checkedAt': result['checkedAt'],
            'currentVersion': result['currentVersion'],
            'latestVersion': result['latestVersion'],
            'hasUpdate': result['hasUpdate'],
            'publishedAt': result['publishedAt'],
            'errorCode': _map(result['error'])['code'],
          }
        ];
      }),
    if (s.hooks != null) ...[
      _view(
          'harness.hooks',
          'Every hook event with the program that would run for it: state ready (a program exists and is executable), not_executable (it exists but has no execute permission, so it is ignored), absent; files in hooks/ that name no event are listed as unrecognized. Run facts come from the hook tasks (harness.hook) and cover what the task list still holds.',
          {
            'event': _text('Hook event; null for an unrecognized file.'),
            'program': _text('File name in hooks/; null when absent.'),
            'state': _text('ready, not_executable, absent or unrecognized.'),
            'runs': _int('Runs held by the task list.'),
            'lastRunAt': _time,
            'lastFinishedAt': _time,
            'lastState': _text('State of the last run task.'),
            'lastExitCode': _int('Exit code of the last run.'),
            'lastElapsedMs': _int('Duration of the last run.'),
            'lastTimedOut': _bool('The last run exceeded its deadline.'),
            'lastLaunchError': _text('Why the last run could not start, redacted.'),
            'lastJobId': _text('Task of the last run.'),
          },
          () async {
        final r = await s.hooks!();
        return [
          for (final h in (r['hooks'] as List? ?? const []))
            {
              ..._map(h).cast<String, Object?>(),
              'lastLaunchError': _redacted(_map(h)['lastLaunchError']),
            }
        ];
      }),
      _view(
          'harness.schedules',
          'Every entry of hooks/schedules.json: valid or not with the reason, the program and whether it can run, when it runs next, the last run and the occurrences that were not started (skippedLate: the clock was late by 2 seconds or more and the occurrence was dropped, not replayed; skippedWhileRunning: the previous run had not finished). If any entry is invalid none runs. nextDueAt, the skip counts and lastTickAt cover this process only. file: absent, valid or invalid.',
          {
            'index': _int('Position in the file; null for a file-level problem.'),
            'id': _text('Schedule id.'),
            'valid': _bool('The entry is well formed.'),
            'reason': _text('Why the entry or file is invalid.'),
            'file': _text('absent, valid, invalid or unavailable.'),
            'active': _bool('The schedule clock is running.'),
            'lastTickAt': _time,
            'program': _text('Program path inside the harness.'),
            'programState': _text('ready, not_executable or absent.'),
            'everySeconds': _int('Interval, when interval based.'),
            'dailyAt': _text('Time of day HH:mm, when daily.'),
            'nextDueAt': _time,
            'lastStartedDueAt': _time,
            'skippedLate': _int('Occurrences dropped because the clock was late.'),
            'skippedWhileRunning': _int('Occurrences dropped because the previous run was still going.'),
            'lastSkippedDueAt': _time,
            'runs': _int('Runs held by the task list.'),
            'lastRunAt': _time,
            'lastFinishedAt': _time,
            'lastState': _text('State of the last run task.'),
            'lastExitCode': _int('Exit code of the last run.'),
            'lastElapsedMs': _int('Duration of the last run.'),
            'lastTimedOut': _bool('The last run exceeded its deadline.'),
            'lastLaunchError': _text('Why the last run could not start, redacted.'),
            'lastJobId': _text('Task of the last run.'),
          },
          () async {
        final r = await s.hooks!();
        final schedule = _map(r['schedules']);
        final shared = {
          'file': schedule['file'],
          'active': schedule['active'],
          'lastTickAt': schedule['lastTickAt'],
        };
        final entries = (schedule['entries'] as List? ?? const []);
        if (entries.isEmpty && schedule['file'] == 'invalid') {
          return [
            {'index': null, 'valid': false, 'reason': schedule['error'], ...shared}
          ];
        }
        return [
          for (final e in entries)
            {
              ..._map(e).cast<String, Object?>(),
              'lastLaunchError': _redacted(_map(e)['lastLaunchError']),
              ...shared,
            }
        ];
      }),
    ],
    if (s.downloadEngines != null)
      _view(
          'downloads.engine',
          'The download backends: builtin (torrent engine), http, and one row per qBittorrent the person added in settings (backend qbittorrent; use its id in download.add backend {kind: "qbittorrent", id}). For a qBittorrent: name, address (no login), local (it runs on this computer, so its paths are paths here; false: they are paths on the machine it runs on, never opened here), online (asked just now), version and apiVersion (null while offline). A qBittorrent that is off is reported with online false and the error code; its logins are not part of the facts. enabled is the download.enabled setting; while it is off the backends are not asked and rates are null. The counts are tasks in each state; the rates are the sum reported by the backend over tasks that are neither finished nor paused. limits are the session limits read back from the native engine (0 = unlimited; null = not readable: no session, or the backend has no limit control).',
          {
            'backend': _text('builtin, http or qbittorrent.'),
            'id': _text('qbittorrent only: the id to name it in download.add.'),
            'name': _text('qbittorrent only: the name the person gave it.'),
            'address': _text('qbittorrent only: where its WebUI is, without credentials.'),
            'local': _bool('qbittorrent only: it runs on this computer.'),
            'online': _bool('qbittorrent only: it answered just now; null while downloads are off (not asked).'),
            'version': _text('qbittorrent only: its version, as it said.'),
            'apiVersion': _text('qbittorrent only: its WebUI API version.'),
            'enabled': _bool('Downloads are enabled.'),
            'running': _int('Tasks downloading.'),
            'queued': _int('Tasks waiting to start.'),
            'paused': _int('Paused tasks.'),
            'waiting': _int('Tasks waiting for a retry, the user, a decision, or interrupted.'),
            'finished': _int('Tasks in a terminal state.'),
            'total': _int('Tasks of this backend.'),
            'downloadBytesPerSecond': _int('Total download rate.'),
            'uploadBytesPerSecond': _int('Total upload rate.'),
            'limitsSupported': _bool('The backend can limit its rate.'),
            'sessionInitialized': _bool('The native session is up.'),
            'downloadLimitBytesPerSecond': _int('Download limit; 0 is unlimited.'),
            'uploadLimitBytesPerSecond': _int('Upload limit; 0 is unlimited.'),
            'error': _code,
            'observedAt': _time,
          },
          () async => await s.downloadEngines!()),
    if (s.downloadTorrents != null)
      _view(
          'downloads.torrents',
          'The torrents inside each qBittorrent the person added, asked from it just now (its own list, not only what Next follows). One row per torrent: id and name of the qBittorrent, local (its paths are paths on this computer; false: on its machine), infoHash (what download.add recognises; the same magnet or file is not added twice), title, state (qBittorrent\'s own word), paused, finished, completedBytes and totalBytes of the wanted files, rates, savePath, category, and jobId: the download task following it, null when none does. A qBittorrent that does not answer has no rows (see downloads.engine); downloads off: no rows. To follow one, download.add with backend {kind: "qbittorrent", id} and a magnet:?xt=urn:btih:INFOHASH for it.',
          {
            'id': _text('The qBittorrent id (download.add backend id).'),
            'name': _text('Its name.'),
            'local': _bool('It runs on this computer.'),
            'infoHash': _text('The torrent\'s info hash.'),
            'title': _text('The torrent name as qBittorrent shows it.'),
            'state': _text('qBittorrent\'s state word (downloading, stalledUP, stoppedUP, pausedDL, ...).'),
            'paused': _bool('Paused or stopped.'),
            'finished': _bool('All wanted files complete.'),
            'completedBytes': _int('Bytes done of the wanted files.'),
            'totalBytes': _int('Bytes of the wanted files.'),
            'downloadBytesPerSecond': _int('Download rate.'),
            'uploadBytesPerSecond': _int('Upload rate.'),
            'savePath': _text('Where qBittorrent saves it, on its machine.'),
            'category': _text('Its qBittorrent category; empty for none.'),
            'jobId': _text('The download task that follows it; null when none.'),
          },
          () async => await s.downloadTorrents!()),
  ];
}

JsonMap _addressRow(Map address) => {
      'role': address['role'],
      'label': address['label'],
      'address': _redacted(address['address']),
      'enabled': address['enabled'],
      'reachability': address['reachability'],
      'lastAttemptAt': address['lastAttemptAt'],
      'lastSuccessAt': address['lastSuccessAt'],
      'lastFailureAt': address['lastFailureAt'],
      'errorCode': address['errorCode'],
      'latencyMs': address['latencyMs'],
    };

JsonMap _sourceRow(JsonMap row) {
  final addresses = (row['addresses'] as List? ?? const []);
  final credential = _map(row['credential']);
  final check = _map(row['lastCheck']);
  final sync = _map(row['sync']);
  final error = _map(row['lastError']);
  return {
    'sourceId': row['sourceId'],
    'type': row['type'],
    'name': row['name'],
    'address': _redacted(row['address']),
    'username': row['username'],
    'connectionState': row['connectionState'],
    'connected': row['connected'],
    'selectedLibraryCount': (row['selectedLibraries'] as List?)?.length,
    'addressCount': addresses.length,
    'unreachableAddressCount': addresses
        .where((a) => _map(a)['reachability'] == 'unreachable')
        .length,
    'credentialState': credential['state'],
    'credentialLastRejectedAt': credential['lastRejectedAt'],
    'credentialLastRejectedCode': credential['lastRejectedCode'],
    'credentialLastVerifiedAt': credential['lastVerifiedAt'],
    'lastCheckAt': check['at'],
    'lastCheckResult': check['result'],
    'lastCheckErrorCode': check['errorCode'],
    'lastCheckLatencyMs': check['latencyMs'],
    'syncResult': sync['result'],
    'syncStartedAt': sync['startedAt'],
    'syncFinishedAt': sync['finishedAt'],
    'lastSyncAt': sync['lastSuccessAt'],
    'syncIndexed': sync['indexed'],
    'syncErrorCode': sync['errorCode'],
    'syncJobId': sync['jobId'],
    'lastErrorCode': error['code'],
    'lastErrorAt': error['at'],
    'lastErrorMessage': _redacted(error['message']),
    'addresses': [
      for (final a in addresses) _addressRow(_map(a)),
    ],
  };
}

void registerSystemViews(StateCapability state, SystemStatusSources sources) {
  for (final view in systemStateViews(sources)) {
    state.views[view.name] = view;
  }
}
