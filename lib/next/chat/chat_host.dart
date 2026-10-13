import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../agent_endpoint.dart';
import '../harness_redaction.dart';
import 'liveness.dart';
import 'session_store.dart';
import 'turn_process_store.dart';
import 'model_launch.dart';

typedef ChatMessage = Map<String, dynamic>;

final class ChatRpcError implements Exception {
  ChatRpcError(this.error);
  final ChatMessage error;
  @override
  String toString() => jsonEncode(error);
}

/// One stdio server, with Codex owning thread history and NipaPlay owning facts.
final class ChatHost {
  ChatHost(
      {required this.endpoint,
      required this.repository,
      this.labRoot,
      this.sessions,
      this.modelLaunch,
      this.probe = false,
      this.codexExecutable})
      : sessionId = 'nipa-${DateTime.now().microsecondsSinceEpoch}-'
            '${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  final AgentEndpoint endpoint;
  final Directory repository;
  final Directory? labRoot;
  final SessionStore? sessions;
  final String? codexExecutable;
  final Future<ModelLaunch> Function()? modelLaunch;
  final bool probe;
  ModelLaunch? _launch;
  int? get activeModelRevision => _launch?.revision;
  bool _restarting = false;
  final _rollouts = <String, String>{};
  final _loaded = <String>{};
  Future<void> _rolloutWrites = Future.value();
  ChatMessage _modelDefaults = {};
  File get _rolloutFile => File('${endpoint.seedRepository.parent.path}/chat-rollouts.json');
  String? mainThreadId;
  final String sessionId;
  final threadLiveness = <String, ChatLiveness>{};
  final _idleLiveness = ChatLiveness();
  ChatLiveness get liveness =>
      threadId == null ? _idleLiveness : livenessFor(threadId!);
  ChatLiveness livenessFor(String id) =>
      threadLiveness.putIfAbsent(id, ChatLiveness.new);
  bool busyFor(String id) =>
      const {'inProgress', 'starting'}.contains(livenessFor(id).status);
  final threadOrigins = <String, String>{};
  String originFor(String id) =>
      threadOrigins[id] ?? 'harness_cli:chat:$sessionId';
  String? threadForOrigin(String origin) => origin ==
          'harness_cli:chat:$sessionId'
      ? threadId
      : threadOrigins.entries.where((e) => e.value == origin).firstOrNull?.key;
  final _events = StreamController<ChatMessage>.broadcast();
  final _display = StreamController<ChatMessage>.broadcast();
  final _questions = StreamController<ChatMessage>.broadcast();

  /// Redacted messages, preserving wire order, for non-UI consumers.
  Stream<ChatMessage> get events => _events.stream;

  /// Reasoning is combined into at most one update per 100 ms per item.
  Stream<ChatMessage> get display => _display.stream.where((message) =>
      !const {'host/liveness', 'host/reasoning'}.contains(message['method']) ||
      message['params']['threadId'] == threadId);

  /// Every thread, including background helpers. All thread-local host messages
  /// carry params.threadId; the legacy display selects foreground host updates.
  Stream<ChatMessage> get threadDisplay => _display.stream;
  Stream<ChatMessage> get userInputRequests => _questions.stream;
  final _pending = <int, Completer<ChatMessage>>{};
  final _requestThreads = <int, String>{};
  final _inputRequests = <Object, ChatMessage>{};
  final _reasoning = <String, StringBuffer>{};
  final _deltaTails = <String, ChatMessage>{};
  final _freshThreads = <String, ChatMessage>{};
  Process? _process;
  Timer? _flush, _clock;
  Future<void>? _reader, _stderr;
  bool _closing = false;
  bool _transportClosed = false;
  Future<void> _controls = Future.value();
  Future<void>? _closeFuture;
  int _nextId = 0;
  String? threadId, model, provider;
  ChatMessage? thread;
  Map<String, String> launchEnvironment = {};
  late final processes = TurnProcessStore(
      TurnProcessStore.fileFor(endpoint.seedRepository.parent, repository.path));

  ChatMessage turnProcess(String id, String turnId) => {
        'found': processes.read(id, turnId) != null,
        'process': processes.read(id, turnId),
      };

  bool get available => _process != null && !_closing && !_transportClosed;
  int? get processId => _process?.pid;
  bool get busy =>
      liveness.status == 'inProgress' || liveness.status == 'starting';

  Future<T> _control<T>(Future<T> Function() operation) {
    final result = _controls.then((_) => operation());
    _controls =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<void> _launchWindows() async {
    final clean = endpoint.chatEnvironment(Platform.environment);
    clean['NIPAPLAY_CHAT'] = sessionId;
    if (labRoot case final root?) {
      final home = Directory('${root.path}/codex-home');
      if (!await File('${home.path}/config.toml').exists()) {
        throw StateError(
            'Prepare provider configuration inside the lab CODEX_HOME.');
      }
      clean['CODEX_HOME'] = home.path;
      clean['TEMP'] = clean['TMP'] =
          (await Directory('${root.path}/temp').create(recursive: true)).path;
    }
    if (_launch?.home case final home?) clean['CODEX_HOME'] = home.path;
    clean.addAll(_launch?.environment ?? {});
    final executable = codexExecutable ??
        Platform.environment['NIPAPLAY_CODEX_EXECUTABLE'] ??
        'codex.exe';
    if (!executable.toLowerCase().endsWith('.exe')) {
      throw ArgumentError('Windows chat requires the native Codex .exe path.');
    }
    launchEnvironment = {
      for (final key in [
        'PATH',
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'ALL_PROXY',
        'NO_PROXY',
        'CODEX_HOME',
        'TEMP',
        'TMP',
        'NIPAPLAY_CHAT'
      ])
        if (clean[key] != null) key: redactHarnessText(clean[key]!)
    };
    _process = await Process.start(
        executable,
        [
          'app-server',
          if (modelLaunch != null || probe) ...['-c', 'features.shell_snapshot=false'],
          if (_launch?.model != null) ...[
            '-c', 'model=${jsonEncode(_launch!.model)}',
            '-c', 'model_provider=${jsonEncode(_launch!.provider)}',
          ],
          '-c',
          'shell_environment_policy.set.NIPAPLAY_CHAT="$sessionId"'
        ],
        workingDirectory: repository.path,
        environment: clean,
        includeParentEnvironment: false);
  }

  Future<void> start() async {
    _launch = await modelLaunch?.call();
    await _launch?.prepare?.call();
    if (!probe && await _rolloutFile.exists()) {
      _rollouts.addAll(Map<String, String>.from(
          jsonDecode(await _rolloutFile.readAsString()) as Map));
    }
    await _startServer();
  }

  Future<void> _startServer() async {
    if (_process != null) throw StateError('Chat server already started.');
    if (Platform.isWindows) {
      await _launchWindows();
    } else {
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      final inherited = endpoint.chatEnvironment(Platform.environment);
      final login = await Process.run(
          shell, ['-l', '-c', 'exec /usr/bin/env -0'],
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
      if (_launch?.home case final home?) clean['CODEX_HOME'] = home.path;
      clean.addAll(_launch?.environment ?? {});
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
          // zsh writes here-documents under TMPPREFIX (default /tmp/zsh),
          // which a lab profile may not write; keep them in its temp.
          '${labRoot != null ? 'export CODEX_HOME="\$2" TMPDIR="\$3" TMPPREFIX="\$3/zsh"; ' : _launch?.home != null ? 'export CODEX_HOME="\$2"; ' : ''}'
          r'exec "$4" app-server '
          '${modelLaunch != null || probe ? '-c features.shell_snapshot=false ' : ''}'
          '${_launch?.model != null ? '-c "\$5" -c "\$6" ' : ''}'
          r'-c "shell_environment_policy.set.NIPAPLAY_CHAT=\"$1\""';
      _process = await Process.start(
          shell,
          [
            if (_launch?.home == null) '-l',
            '-c',
            script,
            'nipaplay-chat',
            sessionId,
            clean['CODEX_HOME'] ?? '',
            clean['TMPDIR'] ?? '',
            codexExecutable ?? 'codex',
            'model=${jsonEncode(_launch?.model)}',
            'model_provider=${jsonEncode(_launch?.provider)}',
          ],
          workingDirectory: repository.path,
          environment: _launch?.home == null ? inherited : clean,
          includeParentEnvironment: false);
    }
    _reader = _read();
    _stderr = _readErrors();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      for (final entry in threadLiveness.entries) {
        _display.add({
          'method': 'host/liveness',
          'params': {
            'threadId': entry.key,
            ...entry.value.snapshot(DateTime.now())
          }
        });
      }
    });
    await _request('initialize', {
      'clientInfo': {'name': 'nipaplay', 'title': 'NipaPlay', 'version': '0.1'},
      'capabilities': {'experimentalApi': modelLaunch != null}
    });
    _send({'method': 'initialized', 'params': {}});
    if (modelLaunch != null) {
      final configuration = await _request('config/read', {});
      final config = configuration['config'] as Map;
      String? defaultModel = _launch?.model ?? config['model'] as String?;
      if (defaultModel == null) {
        final models = await _request('model/list', {});
        defaultModel = (models['data'] as List).cast<Map>()
            .firstWhere((item) => item['isDefault'] == true)['model'] as String;
      }
      _modelDefaults = {
        'model': defaultModel,
        'modelProvider': _launch?.provider ?? config['model_provider'] ?? 'openai',
      };
    }
  }

  Future<void> _applyModel() async {
    var next = await modelLaunch?.call();
    if (next == null || next.revision == _launch?.revision && available) return;
    // A helper may still be running when the foreground is idle. Preserve it.
    while (threadLiveness.keys.any(busyFor)) {
      if (!available) break;
      await events.firstWhere((event) => event['method'] == 'turn/completed' ||
          event['method'] == 'host/error');
      if (!available) break;
    }
    next = await modelLaunch!();
    await _stopTransport();
    _launch = next;
    await next.prepare?.call();
    _transportClosed = false;
    _loaded.clear();
    await _startServer();
    // Resume the foreground with new defaults rather than rollout's old model.
    if (threadId case final id?) {
      final response = await _request('thread/resume', {..._common, 'threadId': id});
      thread = _public(Map<String, dynamic>.from(response['thread'] as Map));
      model = response['model'] as String;
      provider = response['modelProvider'] as String;
    }
    _events.add({'method': 'host/modelChanged', 'params': header});
  }

  Future<void> _stopTransport() async {
    _restarting = true;
    _clock?.cancel();
    _flush?.cancel();
    if (_process case final process?) {
      process.kill();
      final exited = await Future.any<Object>([process.exitCode,
        Future.delayed(const Duration(seconds: 3), () => 'timeout')]);
      if (exited == 'timeout') { process.kill(ProcessSignal.sigkill); await process.exitCode; }
      await _reader;
      await _stderr;
    }
    _process = null;
    _restarting = false;
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
        final wireMethod = decoded['method'] as String? ?? '';
        final wireParams = decoded['params'] as Map?;
        if (!probe && modelLaunch != null && wireMethod == 'thread/started') {
          await _rememberRollout(wireParams!['thread'] as Map);
        }
        final eventThread = wireParams?['threadId'] as String? ??
            _requestThreads[message['id']];
        if (eventThread != null) {
          livenessFor(eventThread).observe(message, DateTime.now());
          if (!probe) processes.observe(message, originFor(eventThread), DateTime.now());
        }
        if (!probe && (wireMethod == 'turn/started' || wireMethod == 'turn/completed')) {
          File('${endpoint.seedRepository.parent.path}/journal.jsonl')
              .writeAsStringSync(
                  '${jsonEncode({
                        'event': 'chat.turn_boundary',
                        'origin': originFor(eventThread!),
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
            final key =
                '${wireParams!['threadId']}:$wireMethod:${wireParams['itemId']}:'
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
            if (tail['params']['threadId'] == eventThread &&
                (wireMethod == 'turn/completed' ||
                    tail['params']['itemId'] == itemId)) {
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
          _requestThreads.remove(id);
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
      if (!_closing && !_restarting) _transportError('app-server stdout closed');
    } catch (error) {
      if (!_restarting) _transportError(redactHarnessText(error.toString()));
    } finally {
      for (final completer in _pending.values) {
        completer.completeError(StateError('app-server connection closed'));
      }
      _pending.clear();
      _requestThreads.clear();
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
        'collabAgentToolCall',
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
    final key =
        '${params['threadId']}:${params['itemId']}:${message['method']}:'
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
    _transportClosed = true;
    for (final live in threadLiveness.values) {
      live.latestError = text;
    }
    _display.add({
      'method': 'host/error',
      'params': {'message': text}
    });
    _events.add({
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
        'params': {
          'threadId': entry.key.split(':').first,
          'key': entry.key.substring(entry.key.indexOf(':') + 1),
          'delta': entry.value.toString()
        }
      });
    }
    _reasoning.clear();
  }

  void _send(ChatMessage message) =>
      _process!.stdin.writeln(jsonEncode(message));
  Future<ChatMessage> _request(String method, ChatMessage params) async {
    if (modelLaunch != null && method == 'thread/resume') {
      final id = params['threadId'] as String;
      params = {...params, ..._modelDefaults,
        if (_rollouts[id] != null) 'path': _rollouts[id]};
    }
    await endpoint.inspectChatText(jsonEncode(params));
    if (!available) {
      throw StateError('Chat server is not running');
    }
    final id = ++_nextId;
    final result = Completer<ChatMessage>();
    _pending[id] = result;
    if (params['threadId'] case final String target) {
      _requestThreads[id] = target;
    }
    _send({'id': id, 'method': method, 'params': params});
    final response = await result.future;
    if (!probe && (method == 'thread/start' || method == 'thread/resume')) {
      await _rememberRollout(response['thread'] as Map);
    }
    return response;
  }

  Future<void> _rememberRollout(Map history) async {
    final id = history['id'] as String;
    _loaded.add(id);
    if (history['path'] case final String path) {
      if (_rollouts[id] == path) return;
      _rollouts[id] = path;
      _rolloutWrites = _rolloutWrites.then((_) async {
        final staging = File('${_rolloutFile.path}.pending');
        await staging.writeAsString(jsonEncode(_rollouts), flush: true);
        await staging.rename(_rolloutFile.path);
      });
      await _rolloutWrites;
    }
  }

  ChatMessage get _common => {
        ..._modelDefaults,
        'cwd': repository.path,
        'sandbox': 'danger-full-access',
        'approvalPolicy': 'never'
      };
  Future<ChatMessage> startThread() =>
      _control(() => _select('thread/start', _common));

  /// Does not select the foreground conversation or change its durable pointer.
  Future<String> helperThread(String helperId, String title,
      {String? resumeId}) => _control(() async {
    final origin = 'harness_cli:helper:$helperId';
    final response =
        await _request(resumeId == null ? 'thread/start' : 'thread/resume', {
      ..._common,
      if (resumeId != null) 'threadId': resumeId,
      'config': {
        'shell_environment_policy.set.NIPAPLAY_CHAT': 'helper-$helperId'
      },
    });
    final history = Map<String, dynamic>.from(response['thread'] as Map);
    final id = history['id'] as String;
    threadOrigins[id] = origin;
    if ((history['turns'] as List).isEmpty) _freshThreads[id] = history;
    if (resumeId == null) {
      await _request('thread/name/set', {
        'threadId': id,
        'name': title,
      });
    }
    return id;
  });

  Future<ChatMessage> startThreadTurn(String id, String text) =>
      _control(() => _startThreadTurn(id, text));
  Future<ChatMessage> _startThreadTurn(String id, String text) async {
    if (busyFor(id)) throw StateError('Use steer for an active turn');
    await _applyModel();
    if (modelLaunch != null && !_loaded.contains(id)) {
      await _request('thread/resume', {..._common, 'threadId': id,
        if (threadOrigins[id] case final String origin)
          'config': {'shell_environment_policy.set.NIPAPLAY_CHAT':
            origin.startsWith('harness_cli:helper:')
              ? 'helper-${origin.substring('harness_cli:helper:'.length)}' : sessionId}});
    }
    final live = livenessFor(id);
    live.starting(DateTime.now());
    _freshThreads.remove(id);
    try {
      return _public(await _request(
          'turn/start', {'threadId': id, 'input': _input(text)}));
    } catch (error) {
      live.status = 'startFailed';
      live.endedAt = DateTime.now();
      rethrow;
    }
  }

  /// Select the durable main thread. Explicit new conversations use startThread.
  Future<ChatMessage> getMainSession() => _control(_mainSession);
  Future<ChatMessage> _mainSession() async {
    final id = mainThreadId ?? await sessions?.main(repository.path);
    if (id == null) return _select('thread/start', _common);
    mainThreadId = id;
    if (threadId == id) {
      return {
        'thread': _public(await readThread(id)),
        'model': model,
        'modelProvider': provider,
        ...header
      };
    }
    return _select('thread/resume', {..._common, 'threadId': id});
  }

  Future<ChatMessage> newConversation() => startThread();
  Future<ChatMessage> switchSession(String id) => resumeThread(id);
  Future<ChatMessage> listSessions({String? cursor, int limit = 30}) async {
    final result = await listThreads(cursor: cursor, limit: limit);
    final main = mainThreadId ?? await sessions?.main(repository.path);
    return {
      ...result,
      'mainThreadId': main,
      'currentThreadId': threadId,
      'data': [
        for (final item in result['data'] as List)
          {
            ...item as Map,
            'isMain': item['id'] == main,
            'isCurrent': item['id'] == threadId
          }
      ]
    };
  }

  Future<ChatMessage> resumeThread(String id) =>
      _control(() => _select('thread/resume', {..._common, 'threadId': id}));
  Future<ChatMessage> _select(String method, ChatMessage params) async {
    if (liveness.status == 'inProgress' || liveness.status == 'starting') {
      throw StateError('Interrupt the current turn before switching threads');
    }
    final selectedId = params['threadId'] as String?;
    final origin = selectedId == null ? null : threadOrigins[selectedId];
    final response = await _request(method, {
      ...params,
      if (origin != null)
        'config': {
          'shell_environment_policy.set.NIPAPLAY_CHAT':
              'helper-${origin.substring('harness_cli:helper:'.length)}'
        }
    });
    thread = _public(Map<String, dynamic>.from(response['thread'] as Map));
    threadId = thread!['id'] as String;
    if (method == 'thread/start') {
      // Codex lazily writes an empty rollout. Naming materializes it without
      // inventing a user message or opening a model turn.
      await _request('thread/name/set', {
        'threadId': threadId,
        'name': await sessions?.main(repository.path) == null
            ? 'NipaPlay 主会话'
            : 'NipaPlay 对话',
      });
    }
    if ((thread!['turns'] as List).isEmpty) {
      _freshThreads[threadId!] = thread!;
    }
    await sessions?.select(repository.path, threadId!);
    mainThreadId ??= await sessions?.main(repository.path) ?? threadId;
    model = response['model'] as String;
    provider = response['modelProvider'] as String;
    return Map<String, dynamic>.from(redactHarnessJson(response) as Map);
  }

  Future<ChatMessage> listThreads({String? cursor, int limit = 30,
      List<String>? sourceKinds}) async =>
      _public(await _request('thread/list', {
        'cwd': repository.path,
        'modelProviders': [],
        'limit': limit,
        if (sourceKinds != null) 'sourceKinds': sourceKinds,
        if (cursor != null) 'cursor': cursor
      }));
  ChatMessage _public(ChatMessage message) =>
      Map<String, dynamic>.from(redactHarnessJson(message) as Map);
  List<ChatMessage> _input(String text) => [
        {'type': 'text', 'text': text}
      ];
  Future<ChatMessage> startTurn(String text) =>
      _control(() => _startTurn(text));
  Future<ChatMessage> _startTurn(String text) async {
    if (threadId == null) await _mainSession();
    if (liveness.status == 'inProgress' || liveness.status == 'starting') {
      throw StateError('Use steer for an active turn');
    }
    return _startThreadTurn(threadId!, text);
  }

  Future<ChatMessage> steer(String text, {String? onThread}) async =>
      _public(await _request('turn/steer', {
        'threadId': onThread ?? threadId,
        'expectedTurnId': livenessFor(onThread ?? threadId!).turnId,
        'input': _input(text)
      }));

  Future<ChatMessage> readThread(String id) async {
    if (modelLaunch != null && !_loaded.contains(id) && _rollouts.containsKey(id)) {
      await _request('thread/resume', {..._common, 'threadId': id});
    }
    // Codex cannot includeTurns until a newly started thread has its first input.
    if (_freshThreads[id] case final fresh?) return fresh;
    final result =
        await _request('thread/read', {'threadId': id, 'includeTurns': true});
    final history = Map<String, dynamic>.from(result['thread'] as Map);
    for (final turn in (history['turns'] as List).cast<Map>()) {
      processes.restore(id, turn);
    }
    return history;
  }

  /// Serialize with UI selection/start. Wait while the host has an active turn.
  Future<String?> prepareFollowup(String? id) => _control(() async {
        if (busy) return null;
        if (id == null) {
          await _mainSession();
          return threadId;
        }
        final history = await readThread(id);
        if ((history['turns'] as List)
            .cast<Map>()
            .any((turn) => turn['status'] == 'inProgress')) {
          return null;
        }
        return id;
      });

  Future<ChatMessage?> startFollowup(String id, String text) =>
      _control(() async {
        if (busy) return null;
        final history = await readThread(id);
        if ((history['turns'] as List)
            .cast<Map>()
            .any((turn) => turn['status'] == 'inProgress')) {
          return null;
        }
        if (threadId != id) {
          await _select('thread/resume', {..._common, 'threadId': id});
        }
        return _startTurn(text);
      });
  Future<ChatMessage> interrupt({String? onThread}) async =>
      _public(await _request('turn/interrupt', {
        'threadId': onThread ?? threadId,
        'turnId': livenessFor(onThread ?? threadId!).turnId
      }));
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
        'mainThreadId': mainThreadId,
        'model': model,
        'provider': provider,
        'cwd': repository.path
      };

  /// An isolated, ephemeral thread for checking the computer's Codex selection.
  /// Call only on a separate probe host; no transcript, process or journal facts.
  Future<bool> checkSavedModel() async {
    if (!probe) throw StateError('Model checks require an isolated probe host');
    final response = await _request('thread/start', {..._common,
      'ephemeral': true, 'baseInstructions': 'Reply OK. Do not use tools.',
      'developerInstructions': ''});
    final id = response['thread']['id'] as String;
    final completion = events.firstWhere((event) =>
      event['method'] == 'turn/completed' && event['params']['threadId'] == id);
    await _request('turn/start', {'threadId': id,
      'input': _input('Reply OK.')});
    final event = await completion;
    return event['params']['turn']['status'] == 'completed';
  }

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
