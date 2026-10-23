import 'dart:convert';
import 'dart:io';

/// A journal.jsonl as Next wrote it while every read carried its whole
/// result: the invocations 动态 shows (reads and writes, a conflict, a reused
/// invocation ID, credential references), the write a task event names
/// without an origin, chat boundaries and other rows, all at fixed times,
/// and between them as many large reads that 动态 does not show
/// (app.capabilities, task.list, state.query, ...) as [fillerBytes] asks.
///
/// 动态 composed from it is the same whatever [fillerBytes] is.
Future<void> writeJournalFixture(File file, {int fillerBytes = 0}) async {
  final lines = journalFixtureLines();
  final sink = file.openWrite();
  var filler = 0, written = 0, index = 0;
  final perLine = fillerBytes ~/ lines.length;
  for (final line in lines) {
    sink.writeln(jsonEncode(line));
    var target = perLine * (index + 1);
    while (written < target && written < fillerBytes) {
      final text = jsonEncode(_fillerRead(filler++));
      sink.writeln(text);
      written += text.length + 1;
    }
    index++;
  }
  await sink.close();
}

/// The invocation the fixture's task event names with no origin of its own.
const fixtureWriteId = 'inv-fixture-write-1';

String _at(int minute) => DateTime.utc(2026, 10, 1, 8)
    .add(Duration(minutes: minute))
    .toIso8601String();

Map<String, Object?> _invocation(int minute, String id, String action,
        String effect, Object? input,
        {String origin = 'harness_cli:chat:fixture-session',
        String status = 'completed',
        String? failureCode,
        Object? result,
        int elapsedMs = 37}) =>
    {
      'invocationId': id,
      'actionId': action,
      'origin': origin,
      'effect': effect,
      'input': input,
      'status': status,
      if (failureCode != null) 'failureCode': failureCode,
      'startedAt': _at(minute),
      'elapsedMs': elapsedMs,
      if (result != null) 'result': result,
    };

Map<String, Object?> _credential(String key) => {
      'credentialRef': {'namespace': 'invocation', 'key': key}
    };

List<Map<String, Object?>> _items(int count, String prefix) => [
      for (var i = 0; i < count; i++)
        {
          'id': '$prefix-$i',
          'title': '作品 $prefix $i',
          'year': 2000 + i % 26,
          'score': (i * 7 % 100) / 10,
          'tags': ['tag-${i % 5}', 'tag-${i % 3}'],
          'poster': {'width': 300, 'height': 450, 'cached': i.isEven},
        }
    ];

/// In file order; times are fixed and not in file order.
List<Map<String, Object?>> journalFixtureLines() => [
      {'existing': true},
      {
        'event': 'chat.turn_boundary',
        'origin': 'harness_cli:chat:fixture-session',
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'phase': 'started',
        'status': 'inProgress',
        'startedAt': _at(0),
      },
      _invocation(1, 'inv-capture-1', 'ui.capture', 'read', {'kind': 'window'},
          result: {'path': '/tmp/capture-1.png', 'width': 1280, 'height': 800}),
      _invocation(2, 'inv-capture-2', 'ui.capture', 'read', {},
          result: {'reason': 'no window'}),
      _invocation(3, 'inv-open-1', 'ui.open', 'write', {'kind': 'native_picker'},
          result: {
            'opened': true,
            'actual': {'kind': 'native_picker_request'}
          }),
      _invocation(
          4, 'inv-open-2', 'ui.open', 'write', {'url': 'https://example.test/'},
          result: {
            'opened': true,
            'actual': {'kind': 'webpage_request'}
          }),
      _invocation(5, 'inv-open-3', 'ui.open', 'write', {'entityId': 'work-9'},
          result: {'opened': false}),
      _invocation(6, 'inv-open-4', 'ui.open', 'write', {'kind': 'folder'},
          result: {
            'opened': true,
            'actual': {'kind': 'folder_request', 'path': '/media'}
          }),
      _invocation(7, 'inv-open-5', 'ui.open', 'write', {'entityId': 'work-1'},
          origin: 'gui',
          result: {
            'opened': true,
            'actual': {'kind': 'work', 'entityId': 'work-1'}
          }),
      _invocation(8, 'inv-close-1', 'ui.close', 'write', {},
          result: {'closed': true}),
      _invocation(9, 'inv-refresh-1', 'discover.refresh', 'write', {},
          result: {'refreshed': true}),
      _invocation(10, 'inv-recommend-1', 'discover.recommendations', 'read',
          {'next': true},
          result: {'changed': true, 'items': _items(12, 'rec')}),
      _invocation(
          11, 'inv-recommend-2', 'discover.recommendations', 'read', {},
          result: {'changed': false, 'items': _items(4, 'rec2')}),
      _invocation(12, 'inv-recommend-3', 'discover.recommendations', 'read',
          {'next': true},
          status: 'failed', failureCode: 'unavailable'),
      _invocation(13, 'inv-search-1', 'media.sources.search', 'read',
          {'query': '葬送', 'sourceIds': ['src-1']},
          result: {
            'sources': [
              {
                'sourceId': 'src-1',
                'entries': _items(3, 'hit'),
                'total': 3,
              }
            ]
          }),
      _invocation(14, 'inv-source-add', 'media.sources.add', 'write', {
        'provider': 'jellyfin',
        'name': 'Home',
        'url': 'http://nas.local:8096',
        'password': _credential('inv-source-add/password'),
      }, result: {
        'sourceId': 'src-1',
        'connectionState': 'connected'
      }),
      _invocation(15, 'inv-source-remove', 'media.sources.remove',
          'destructive', {'sourceId': 'src-0'},
          origin: 'mesh:peer-mac', result: {'removed': true}),
      _invocation(16, 'inv-login-1', 'accounts.login', 'write',
          {'provider': 'bangumi', 'token': _credential('inv-login-1/token')},
          result: {'loggedIn': true, 'user': 'fixture'}),
      _invocation(17, 'inv-account-status', 'accounts.status', 'read',
          {'provider': 'dandanplay'},
          origin: 'application',
          result: {
            'loggedIn': false,
            'session': _credential('inv-account-status/result/session')
          }),
      _invocation(18, 'inv-danmaku-send', 'danmaku.send', 'write',
          {'text': '好看', 'entityId': 'episode-3'},
          result: {'sent': true}),
      _invocation(19, 'inv-danmaku-send-2', 'danmaku.send', 'write',
          {'text': '再来'},
          status: 'failed', failureCode: 'invalid_input'),
      _invocation(20, 'inv-roots-add', 'media.library.roots.add', 'write',
          {'path': '/Volumes/Media'},
          status: 'needs_decision'),
      _invocation(21, 'inv-bind-conflict', 'media.identity.bind_batch',
          'write', {
        'requestId': 'fixture-bind',
        'entries': [
          {
            'entityId': 'work-1',
            'kind': 'work',
            'ref': {'provider': 'tmdb', 'id': '1'},
            'reason': 'title',
            'note': 'not shown'
          },
          {
            'entityId': 'file-2',
            'workRef': {'provider': 'tmdb', 'id': '2'},
            'episodeRefs': [
              {'season': 1, 'episode': 2}
            ]
          },
          {'releaseRef': 'r-1'},
        ]
      },
          status: 'failed', failureCode: 'conflict'),
      _invocation(22, 'inv-query-conflict', 'db.query', 'read',
          {'sql': 'select 1'},
          status: 'failed', failureCode: 'conflict', origin: 'hook:job-7'),
      _invocation(23, 'inv-bind-ok', 'media.identity.bind_batch', 'write', {
        'requestId': 'fixture-bind-2',
        'entries': [
          {'entityId': 'work-3'}
        ]
      }, result: {
        'entries': [
          {'workId': 'work-3'}
        ]
      }),
      _invocation(24, fixtureWriteId, 'settings.set', 'write',
          {'key': 'next.harnessPath', 'value': '/tmp/harness'},
          origin: 'mesh:peer-mac', result: {'revision': 2}),
      _invocation(25, 'inv-dup', 'ui.open', 'write', {'entityId': 'work-5'},
          result: {
            'opened': true,
            'actual': {'kind': 'work'}
          }),
      {
        'event': 'chat.endpoint_token_rotated',
        'origin': 'chat_host',
        'startedAt': _at(26),
      },
      _invocation(27, 'inv-dup', 'ui.close', 'write', {},
          result: {'closed': false}),
      _invocation(28, 'inv-quit', 'app.quit', 'write', {},
          origin: 'gui', result: {'scheduled': true}),
      {
        'event': 'chat.turn_boundary',
        'origin': 'harness_cli:chat:fixture-session',
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'phase': 'completed',
        'status': 'completed',
        'startedAt': _at(29),
      },
    ];

/// Reads 动态 does not show, sized like the ones in an old journal.
Map<String, Object?> _fillerRead(int n) {
  final (action, origin, count) = switch (n % 16) {
    0 => ('app.capabilities', 'application:catalog', 900),
    1 || 2 => ('task.list', 'harness_cli:chat:fixture-session', 700),
    3 || 4 => ('state.query', 'harness_cli:chat:fixture-session', 300),
    5 => ('media.library.works', 'gui', 600),
    6 || 7 || 8 || 9 => ('diagnostics.player_log', 'gui', 50),
    _ => ('playback.state', 'harness_cli:chat:fixture-session', 6),
  };
  return _invocation(-(n % 5000) - 1, 'inv-filler-$n', action, 'read',
      {'limit': 50},
      origin: origin, result: {'items': _items(count, 'f$n')});
}
