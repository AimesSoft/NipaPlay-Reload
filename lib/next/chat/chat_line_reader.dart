import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nipaplay/security/credential_vault.dart' show CredentialRef;
import 'package:nipaplay/security/secret_redactor.dart';

import '../harness_redaction.dart';

/// One line a chat runtime wrote, as read on the reader's isolate.
final class ChatLine {
  ChatLine(String text,
      {Map<String, dynamic>? decoded,
      Map<String, dynamic>? redacted,
      this.redactedText,
      this.exposesEndpointToken = false,
      this.error})
      : _text = text,
        _decoded = decoded,
        _redacted = redacted;

  ChatLine.encoded(TransferableTypedData decoded,
      {TransferableTypedData? redacted,
      this.redactedText,
      required bool exposeText,
      this.error})
      : _text = exposeText ? null : '',
        _encodedDecoded = decoded,
        _encodedRedacted = redacted,
        _decoded = null,
        _redacted = null,
        exposesEndpointToken = exposeText;

  String? _text;

  /// The line as written when [exposesEndpointToken] is true, or when the
  /// reader is used without endpoint-token guarding. The host inspects this
  /// only when it may contain its own token. The encoded form stays in the
  /// worker's transferable block until someone actually reads it.
  String get text {
    final cached = _text;
    if (cached != null) return cached;
    final encoded = _encodedDecoded;
    if (encoded == null) return _text = '';
    _encodedDecoded = null;
    return _text = _decodeText(encoded);
  }

  /// The RPC object, exact: replies to the host's requests stay exact.
  Map<String, dynamic>? _decoded;

  /// The published form when redaction changed [decoded]; a stream delta's
  /// text is left empty here (the host redacts it together with the tail it
  /// holds back). Null when redaction changed nothing, so the isolate does not
  /// copy an identical large catalogue object back to the host.
  Map<String, dynamic>? _redacted;

  TransferableTypedData? _encodedDecoded;
  TransferableTypedData? _encodedRedacted;

  /// A plain-text line, redacted.
  final String? redactedText;

  /// Redacted description of why the line is not an RPC object, or of a
  /// failure reading the output; nothing after it is read.
  final String? error;

  /// Whether [text] may contain the local endpoint token. Ordinary runtime
  /// output does not carry the raw line across isolates merely for a scan that
  /// cannot match.
  final bool exposesEndpointToken;

  static String _decodeText(TransferableTypedData data) =>
      utf8.decode(data.materialize().asUint8List());

  static Map<String, dynamic> _decodeJson(String raw) =>
      (jsonDecode(raw) as Map).cast<String, dynamic>();

  Map<String, dynamic>? get decoded {
    final cached = _decoded;
    if (cached != null) return cached;
    final encoded = _encodedDecoded;
    if (encoded == null) {
      final raw = _text;
      return raw == null ? null : _decoded = _decodeJson(raw);
    }
    _encodedDecoded = null;
    final raw = _decodeText(encoded);
    if (exposesEndpointToken) _text ??= raw;
    return _decoded = _decodeJson(raw);
  }

  Map<String, dynamic>? get redacted {
    final encoded = _encodedRedacted;
    if (encoded == null) return _redacted;
    _encodedRedacted = null;
    return _redacted = _decodeJson(_decodeText(encoded));
  }
}

/// Reads a chat runtime's output on a background isolate: decoding, line
/// splitting, JSON parsing and redaction grow with what the runtime writes
/// (a command's whole output, a thread read back) and are not the main
/// isolate's. The main isolate forwards the output's bytes as they arrive
/// and receives lines in the order they were written; every line is
/// delivered, up to the first one that cannot be read.
///
/// Redaction there uses the values remembered here: those known when the
/// reader starts, then each one as it is remembered, in order with the
/// output, so anything remembered before the bytes arrive is redacted.
final class ChatLineReader {
  ChatLineReader._(this._lines);

  /// [rpc] lines are JSON-RPC objects; otherwise lines are plain text.
  /// [streamDeltaMethods] name the stream deltas whose `params.delta` is left
  /// out of [ChatLine.redacted].
  static ChatLineReader start(Stream<List<int>> output,
      {required bool rpc,
      Set<String> streamDeltaMethods = const {},
      bool guardEndpointToken = false}) {
    final lines = StreamController<ChatLine>(sync: true);
    final reader = ChatLineReader._(lines);
    final replies = ReceivePort(), failures = ReceivePort();
    reader._ports = [replies, failures];
    final pending = <Object>[];
    SendPort? worker;
    void forward(Object message) =>
        worker == null ? pending.add(message) : worker!.send(message);
    void remember(String value, CredentialRef ref) => forward((value, ref));
    reader._remember = remember;
    SecretRedactor.addListener(remember);
    final known = SecretRedactor.remembered();
    final pendingLines = Queue<ChatLine>();
    var draining = false, workerDone = false;
    void finishIfDrained() {
      if (!workerDone || draining || pendingLines.isNotEmpty) return;
      if (!lines.isClosed) unawaited(lines.close());
      reader._release();
    }

    void drain() {
      if (draining) return;
      draining = true;
      scheduleMicrotask(() {
        if (pendingLines.isEmpty) {
          draining = false;
          finishIfDrained();
          return;
        }
        final line = pendingLines.removeFirst();
        if (!lines.isClosed) lines.add(line);
        if (line.error != null) {
          workerDone = true;
          pendingLines.clear();
        }
        draining = false;
        if (pendingLines.isNotEmpty) {
          drain();
        } else {
          finishIfDrained();
        }
      });
    }

    void accept(ChatLine line) {
      if (lines.isClosed || workerDone) return;
      pendingLines.add(line);
      drain();
    }

    replies.listen((message) {
      if (message is SendPort) {
        worker = message;
        for (final item in pending) {
          message.send(item);
        }
        pending.clear();
      } else if (message is ChatLine) {
        accept(message);
      } else if (message is List) {
        for (final line in message) {
          if (line is ChatLine) accept(line);
        }
      } else {
        workerDone = true;
        finishIfDrained();
      }
    });
    failures.listen((error) {
      accept(
          ChatLine('', error: redactHarnessText('chat reader failed: $error')));
      workerDone = true;
      finishIfDrained();
    });
    reader._output = output.listen(
        (chunk) => forward(TransferableTypedData.fromList([
              chunk is TypedData
                  ? chunk as TypedData
                  : Uint8List.fromList(chunk)
            ])),
        onError: (Object error) => forward(_OutputError('$error')),
        onDone: () => forward(_end));
    unawaited(Isolate.spawn(
            _read,
            (
              replies.sendPort,
              rpc,
              streamDeltaMethods,
              known,
              guardEndpointToken
            ),
            onError: failures.sendPort,
            debugName: 'chat-line-reader')
        .then((isolate) {
      if (reader._released) {
        isolate.kill();
      } else {
        reader._isolate = isolate;
      }
    }, onError: (Object error) {
      accept(
          ChatLine('', error: redactHarnessText('chat reader failed: $error')));
      workerDone = true;
      finishIfDrained();
    }));
    return reader;
  }

  final StreamController<ChatLine> _lines;
  StreamSubscription<List<int>>? _output;
  List<ReceivePort> _ports = const [];
  Isolate? _isolate;
  void Function(String, CredentialRef)? _remember;
  bool _released = false;

  /// Lines in written order; done when the output ends or after an error.
  Stream<ChatLine> get lines => _lines.stream;

  void _release() {
    if (_released) return;
    _released = true;
    if (_remember case final remember?) SecretRedactor.removeListener(remember);
    for (final port in _ports) {
      port.close();
    }
    _isolate?.kill();
  }

  /// Stops reading (the output is no longer consumed) and ends the worker.
  Future<void> close() async {
    _release();
    await _output?.cancel();
    if (!_lines.isClosed) await _lines.close();
  }
}

const _end = 'end';

final class _OutputError {
  const _OutputError(this.text);
  final String text;
  @override
  String toString() => text;
}

void _read(
    (SendPort, bool, Set<String>, Map<String, CredentialRef>, bool) setup) {
  final (main, rpc, deltas, known, guardEndpointToken) = setup;
  final endpointTokens = <String>{};
  for (final MapEntry(key: value, value: ref) in known.entries) {
    SecretRedactor.remember(ref, value);
    if (_isEndpointToken(ref)) endpointTokens.add(value);
  }
  final port = ReceivePort();
  final input = StreamController<List<int>>();
  final lines = <ChatLine>[];
  var stopped = false, flushScheduled = false;
  void flush() {
    flushScheduled = false;
    if (lines.isEmpty) return;
    main.send(List<ChatLine>.of(lines));
    lines.clear();
  }

  void scheduleFlush() {
    if (flushScheduled) return;
    flushScheduled = true;
    scheduleMicrotask(flush);
  }

  void stop(ChatLine last) {
    stopped = true;
    flush();
    main.send(last);
    port.close();
    Isolate.exit();
  }

  input.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
    if (stopped) return;
    final exposed =
        guardEndpointToken && _hasEndpointToken(line, endpointTokens);
    final read = rpc
        ? _rpcLine(line, deltas, exposeText: !guardEndpointToken || exposed)
        : _textLine(line, exposeText: !guardEndpointToken || exposed);
    if (read.error != null) {
      stop(read);
    } else {
      lines.add(read);
      if (lines.length == 32) {
        flush();
      } else {
        scheduleFlush();
      }
    }
  }, onError: (Object error) {
    if (!stopped) {
      stop(ChatLine('', error: redactHarnessText(error.toString())));
    }
  }, onDone: () {
    if (stopped) return;
    stopped = true;
    flush();
    port.close();
    Isolate.exit(main, _end);
  });
  port.listen((message) {
    switch (message) {
      case TransferableTypedData data:
        input.add(data.materialize().asUint8List());
      case (String value, CredentialRef ref):
        SecretRedactor.remember(ref, value);
        if (_isEndpointToken(ref)) endpointTokens.add(value);
      case _OutputError error:
        input.addError(error);
      case _end:
        input.close();
    }
  });
  main.send(port.sendPort);
}

bool _isEndpointToken(CredentialRef ref) =>
    ref.namespace == 'agent' && ref.key == 'token';

bool _hasEndpointToken(String text, Set<String> tokens) {
  for (final token in tokens) {
    if (text.contains(token) ||
        text.contains(Uri.encodeComponent(token)) ||
        text.contains(Uri.encodeQueryComponent(token))) {
      return true;
    }
  }
  return false;
}

ChatLine _textLine(String line, {required bool exposeText}) =>
    ChatLine(exposeText ? line : '',
        redactedText: redactHarnessText(line),
        exposesEndpointToken: exposeText && line.isNotEmpty);

ChatLine _rpcLine(String line, Set<String> deltas, {required bool exposeText}) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected RPC object');
    }
    final method = decoded['method'] as String? ?? '';
    final params = decoded['params'] as Map?;
    final delta = deltas.contains(method) && params?['delta'] is String;
    final redacted = Map<String, dynamic>.from(redactHarnessJson(delta
        ? {
            ...decoded,
            'params': {...params!, 'delta': ''}
          }
        : decoded) as Map);
    return ChatLine.encoded(_packJson(line),
        redacted: _sameJson(decoded, redacted) ? null : _packJson(redacted),
        exposeText: exposeText);
  } catch (error) {
    return ChatLine(line, error: redactHarnessText(error.toString()));
  }
}

TransferableTypedData _packJson(Object json) => TransferableTypedData.fromList(
    [utf8.encode(json is String ? json : jsonEncode(json))]);

bool _sameJson(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_sameJson(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!_sameJson(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}
