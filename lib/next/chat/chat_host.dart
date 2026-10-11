import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../agent_endpoint.dart';
import '../harness_redaction.dart';
import 'liveness.dart';

typedef ChatMessage = Map<String, dynamic>;

final class ChatRpcError implements Exception {
  ChatRpcError(this.error);
  final ChatMessage error;
  @override
  String toString() => jsonEncode(error);
}

/// One stdio server, with Codex owning thread history and NipaPlay owning facts.
final class ChatHost {
  ChatHost({required this.endpoint, required this.repository, this.labRoot})
      : sessionId = 'nipa-${DateTime.now().microsecondsSinceEpoch}-'
            '${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  final AgentEndpoint endpoint;
  final Directory repository;
  final Directory? labRoot;
  final String sessionId;
  final liveness = ChatLiveness();
  final _events = StreamController<ChatMessage>.broadcast();
  final _display = StreamController<ChatMessage>.broadcast();
  final _questions = StreamController<ChatMessage>.broadcast();

  /// Redacted messages, preserving wire order, for non-UI consumers.
  Stream<ChatMessage> get events => _events.stream;

  /// Reasoning is combined into at most one update per 100 ms per item.
  Stream<ChatMessage> get display => _display.stream;
  Stream<ChatMessage> get userInputRequests => _questions.stream;
  final _pending = <int, Completer<ChatMessage>>{};
  final _inputRequests = <Object, ChatMessage>{};
  final _reasoning = <String, StringBuffer>{};
  final _deltaTails = <String, ChatMessage>{};
  Process? _process;
  Timer? _flush, _clock;
  Future<void>? _reader, _stderr;
  bool _closing = false;
  Future<void>? _closeFuture;
  int _nextId = 0;
  String? threadId, model, provider;
  ChatMessage? thread;
  Map<String, String> launchEnvironment = {};

  Future<void> start() async {
    if (_process != null) throw StateError('Chat server already started.');
    if (Platform.isWindows) {
      throw UnsupportedError('Chat login-shell launch requires a POSIX shell.');
    }
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    final inherited = endpoint.chatEnvironment(Platform.environment);
    final login = await Process.run(shell, ['-l', '-c', 'exec /usr/bin/env -0'],
        environment: inherited,
        includeParentEnvironment: false,
        stdoutEncoding: null,
        stderrEncoding: null,
        workingDirectory: repository.path);
    if (login.exitCode != 0) {
      throw ProcessException(
          shell, ['-l'], 'Cannot read login environment', login.exitCode);
    }
    final env = <String, String>{};
    for (final field
        in utf8.decode(login.stdout as List<int>).split('\u0000')) {
      final eq = field.indexOf('=');
      if (eq > 0) env[field.substring(0, eq)] = field.substring(eq + 1);
    }
    final clean = endpoint.chatEnvironment(env);
    final removed = env.keys.where((key) => !clean.containsKey(key)).toList();
    if (removed
        .any((key) => !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key))) {
      throw StateError(
          'Cannot unset a secret environment name in login shell.');
    }
    clean['NIPAPLAY_CHAT'] = sessionId;
    if (labRoot case final root?) {
      final home = Directory('${root.path}/codex-home');
      if (!await File('${home.path}/config.toml').exists()) {
        throw StateError(
            'Prepare provider configuration inside the lab CODEX_HOME.');
      }
      clean['CODEX_HOME'] = home.path;
      clean['TMPDIR'] =
          (await Directory('${root.path}/temp').create(recursive: true)).path;
    }
    launchEnvironment = {
      for (final key in [
        'PATH',
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'ALL_PROXY',
        'http_proxy',
        'https_proxy',
        'all_proxy',
        'NO_PROXY',
        'CODEX_HOME',
        'TMPDIR',
        'NIPAPLAY_CHAT'
      ])
        if (clean[key] != null) key: redactHarnessText(clean[key]!)
    };
    // Reapply host-owned values after shell startup files; keep user's PATH/proxy.
    final script = '${removed.isEmpty ? '' : 'unset ${removed.join(' ')}; '}'
        'export NIPAPLAY_CHAT="\$1"; '
        '${labRoot == null ? '' : 'export CODEX_HOME="\$2" TMPDIR="\$3"; '}'
        r'exec codex app-server -c "shell_environment_policy.set.NIPAPLAY_CHAT=\"$1\""';
    _process = await Process.start(
        shell,
        [
          '-l',
          '-c',
          script,
          'nipaplay-chat',
          sessionId,
          clean['CODEX_HOME'] ?? '',
          clean['TMPDIR'] ?? ''
        ],
        workingDirectory: repository.path,
        environment: inherited,
        includeParentEnvironment: false);
    _reader = _read();
    _stderr = _readErrors();
    _clock = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _display.add({
              'method': 'host/liveness',
              'params': liveness.snapshot(DateTime.now())
            }));
    await _request('initialize', {
      'clientInfo': {'name': 'nipaplay', 'title': 'NipaPlay', 'version': '0.1'},
      'capabilities': {'experimentalApi': false}
    });
    _send({'method': 'initialized', 'params': {}});
  }

  Future<void> _read() async {
    try {
      await for (final line in _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        await endpoint.inspectChatText(line);
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Expected RPC object');
        }
        final message =
            Map<String, dynamic>.from(redactHarnessJson(decoded) as Map);
        liveness.observe(message, DateTime.now());
        final wireMethod = decoded['method'] as String? ?? '';
        final wireParams = decoded['params'] as Map?;
        if (wireMethod == 'turn/started' || wireMethod == 'turn/completed') {
          File('${endpoint.seedRepository.parent.path}/journal.jsonl')
              .writeAsStringSync(
                  '${jsonEncode({
                        'event': 'chat.turn_boundary',
                        'origin': 'harness_cli:chat:$sessionId',
                        'threadId': wireParams!['threadId'],
                        'turnId': wireParams['turn']['id'],
                        'phase': wireMethod == 'turn/started'
                            ? 'started'
                            : 'completed',
                        'status': wireParams['turn']['status'],
                        'startedAt': DateTime.now().toUtc().toIso8601String(),
                      })}\n',
                  mode: FileMode.append,
                  flush: true);
        }
        if (const {
          'item/agentMessage/delta',
          'item/reasoning/textDelta',
          'item/reasoning/summaryTextDelta',
          'item/commandExecution/outputDelta',
          'item/fileChange/outputDelta'
        }.contains(wireMethod)) {
          if (wireParams?['delta'] case final String delta) {
            final key = '$wireMethod:${wireParams!['itemId']}:'
                '${wireParams['contentIndex'] ?? wireParams['summaryIndex']}';
            final previous =
                _deltaTails[key]?['params']['delta'] as String? ?? '';
            final (safe, tail) =
                await endpoint.protectChatDelta(previous, delta);
            (message['params'] as Map)['delta'] = safe;
            _deltaTails[key] = {
              'method': wireMethod,
              'params': {
                ...Map<String, dynamic>.from(wireParams),
                'delta': tail
              }
            };
          }
        }
        if (wireMethod == 'item/completed' || wireMethod == 'turn/completed') {
          final itemId = wireParams?['item']?['id'];
          for (final key in _deltaTails.keys.toList()) {
            final tail = _deltaTails[key]!;
            if (wireMethod == 'turn/completed' ||
                tail['params']['itemId'] == itemId) {
              _deltaTails.remove(key);
              if (tail['params']['delta'] != '') {
                final safe = _public(tail);
                _events.add(safe);
                if (_isReasoning(safe['method'])) {
                  _showReasoning(safe);
                } else if (_knownDisplay(safe)) {
                  _display.add(safe);
                }
              }
            }
          }
        }
        _events.add(message);
        final id = message['id'];
        if (id is int &&
            (message.containsKey('result') || message.containsKey('error'))) {
          final pending = _pending.remove(id);
          if (pending != null) {
            if (message['error'] case final Map error) {
              pending.completeError(
                  ChatRpcError(Map<String, dynamic>.from(error)));
            } else {
              // Control data stays exact; only public streams are redacted.
              pending.complete(
                  Map<String, dynamic>.from(decoded['result'] as Map));
            }
          }
        } else if (id != null && message['method'] != null) {
          if (message['method'] == 'item/tool/requestUserInput') {
            _inputRequests[id] = message;
            _questions.add(message);
          } else {
            _send({
              'id': id,
              'error': {
                'code': -32601,
                'message': 'NipaPlay does not support this server request'
              }
            });
          }
        }
        final method = message['method'] as String? ?? '';
        if (_isReasoning(method)) {
          _showReasoning(message);
        } else {
          if (method == 'item/completed' || method == 'turn/completed') {
            _flushReasoning();
          }
          if (_knownDisplay(message)) _display.add(message);
        }
      }
      if (!_closing) _transportError('app-server stdout closed');
    } catch (error) {
      _transportError(redactHarnessText(error.toString()));
    } finally {
      for (final completer in _pending.values) {
        completer.completeError(StateError('app-server connection closed'));
      }
      _pending.clear();
      _flushReasoning();
    }
  }

  bool _knownDisplay(ChatMessage m) {
    final method = m['method'] as String?;
    if (method == 'item/started' || method == 'item/completed') {
      return const {
        'agentMessage',
        'userMessage',
        'reasoning',
        'commandExecution',
        'fileChange',
        'mcpToolCall',
        'plan',
        'webSearch'
      }.contains((m['params'] as Map)['item']['type']);
    }
    return const {
      'turn/started',
      'turn/completed',
      'thread/started',
      'error',
      'item/agentMessage/delta',
      'item/commandExecution/outputDelta',
      'item/fileChange/outputDelta',
      'turn/diff/updated',
      'turn/plan/updated',
      'item/tool/requestUserInput'
    }.contains(method);
  }

  bool _isReasoning(Object? method) =>
      method == 'item/reasoning/textDelta' ||
      method == 'item/reasoning/summaryTextDelta';

  void _showReasoning(ChatMessage message) {
    final params = message['params'] as Map;
    final key = '${params['itemId']}:${message['method']}:'
        '${params['contentIndex'] ?? params['summaryIndex']}';
    (_reasoning[key] ??= StringBuffer()).write(params['delta']);
    _flush ??= Timer(const Duration(milliseconds: 100), _flushReasoning);
  }

  Future<void> _readErrors() async {
    await for (final line in _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      await endpoint.inspectChatText(line);
      _events.add({
        'method': 'host/stderr',
        'params': {'text': redactHarnessText(line)}
      });
    }
  }

  void _transportError(String text) {
    liveness.latestError = text;
    _display.add({
      'method': 'host/error',
      'params': {'message': text}
    });
  }

  void _flushReasoning() {
    _flush?.cancel();
    _flush = null;
    for (final entry in _reasoning.entries) {
      _display.add({
        'method': 'host/reasoning',
        'params': {'key': entry.key, 'delta': entry.value.toString()}
      });
    }
    _reasoning.clear();
  }

  void _send(ChatMessage message) =>
      _process!.stdin.writeln(jsonEncode(message));
  Future<ChatMessage> _request(String method, ChatMessage params) async {
    await endpoint.inspectChatText(jsonEncode(params));
    if (_closing || _process == null) {
      throw StateError('Chat server is not running');
    }
    final id = ++_nextId;
    final result = Completer<ChatMessage>();
    _pending[id] = result;
    _send({'id': id, 'method': method, 'params': params});
    return result.future;
  }

  ChatMessage get _common => {
        'cwd': repository.path,
        'sandbox': 'danger-full-access',
        'approvalPolicy': 'never'
      };
  Future<ChatMessage> startThread() => _select('thread/start', _common);
  Future<ChatMessage> resumeThread(String id) =>
      _select('thread/resume', {..._common, 'threadId': id});
  Future<ChatMessage> _select(String method, ChatMessage params) async {
    if (liveness.status == 'inProgress' || liveness.status == 'starting') {
      throw StateError('Interrupt the current turn before switching threads');
    }
    final response = await _request(method, params);
    thread = _public(Map<String, dynamic>.from(response['thread'] as Map));
    threadId = thread!['id'] as String;
    model = response['model'] as String;
    provider = response['modelProvider'] as String;
    return Map<String, dynamic>.from(redactHarnessJson(response) as Map);
  }

  Future<ChatMessage> listThreads({String? cursor, int limit = 30}) async =>
      _public(await _request('thread/list', {
        'cwd': repository.path,
        'modelProviders': [],
        'limit': limit,
        if (cursor != null) 'cursor': cursor
      }));
  ChatMessage _public(ChatMessage message) =>
      Map<String, dynamic>.from(redactHarnessJson(message) as Map);
  List<ChatMessage> _input(String text) => [
        {'type': 'text', 'text': text}
      ];
  Future<ChatMessage> startTurn(String text) async {
    if (threadId == null) throw StateError('Select a thread first');
    if (liveness.status == 'inProgress' || liveness.status == 'starting') {
      throw StateError('Use steer for an active turn');
    }
    liveness.starting(DateTime.now());
    try {
      return _public(await _request(
          'turn/start', {'threadId': threadId, 'input': _input(text)}));
    } catch (error) {
      liveness.status = 'startFailed';
      liveness.endedAt = DateTime.now();
      rethrow;
    }
  }

  Future<ChatMessage> steer(String text) async =>
      _public(await _request('turn/steer', {
        'threadId': threadId,
        'expectedTurnId': liveness.turnId,
        'input': _input(text)
      }));
  Future<ChatMessage> interrupt() async => _public(await _request(
      'turn/interrupt', {'threadId': threadId, 'turnId': liveness.turnId}));
  Future<void> answerUserInput(
      Object id, Map<String, List<String>> answers) async {
    if (!_inputRequests.containsKey(id)) {
      throw ArgumentError('Unknown input request');
    }
    await endpoint.inspectChatText(jsonEncode(answers));
    _send({
      'id': id,
      'result': {
        'answers': {
          for (final entry in answers.entries)
            entry.key: {'answers': entry.value}
        }
      }
    });
    _inputRequests.remove(id);
  }

  Map<String, Object?> get header => {
        'sessionId': sessionId,
        'threadId': threadId,
        'model': model,
        'provider': provider,
        'cwd': repository.path
      };

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    _clock?.cancel();
    _flush?.cancel();
    // Closing the process ends its active turn; no liveness timer does this.
    if (_process case final process?) {
      process.kill();
      final exited = await Future.any<Object>([
        process.exitCode,
        Future.delayed(const Duration(seconds: 3), () => 'timeout')
      ]);
      if (exited == 'timeout') {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      await _reader;
      await _stderr;
    }
    await _events.close();
    await _display.close();
    await _questions.close();
  }
}
