import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nipaplay/security/credential_vault.dart' show CredentialRef;
import 'package:nipaplay/security/secret_redactor.dart';

import '../harness_redaction.dart';

/// One line a chat runtime wrote, as read on the reader's isolate.
final class ChatLine {
  const ChatLine(this.text,
      {this.decoded, this.redacted, this.redactedText, this.error});

  /// The line as written; the host inspects it for its own token.
  final String text;

  /// The RPC object, exact: replies to the host's requests stay exact.
  final Map<String, dynamic>? decoded;

  /// The published form of [decoded]; a stream delta's text is left empty
  /// here (the host redacts it together with the tail it holds back).
  final Map<String, dynamic>? redacted;

  /// A plain-text line, redacted.
  final String? redactedText;

  /// Redacted description of why the line is not an RPC object, or of a
  /// failure reading the output; nothing after it is read.
  final String? error;
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
      {required bool rpc, Set<String> streamDeltaMethods = const {}}) {
    final lines = StreamController<ChatLine>();
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
    void finish() {
      if (!lines.isClosed) unawaited(lines.close());
      reader._release();
    }

    replies.listen((message) {
      if (message is SendPort) {
        worker = message;
        for (final item in pending) {
          message.send(item);
        }
        pending.clear();
      } else if (message is ChatLine) {
        if (!lines.isClosed) lines.add(message);
        if (message.error != null) finish();
      } else {
        finish();
      }
    });
    failures.listen((error) {
      if (!lines.isClosed) {
        lines.add(ChatLine('',
            error: redactHarnessText('chat reader failed: $error')));
      }
      finish();
    });
    reader._output = output.listen(
        (chunk) => forward(TransferableTypedData.fromList(
            [chunk is TypedData ? chunk as TypedData : Uint8List.fromList(chunk)])),
        onError: (Object error) => forward(_OutputError('$error')),
        onDone: () => forward(_end));
    unawaited(Isolate.spawn(
            _read, (replies.sendPort, rpc, streamDeltaMethods, known),
            onError: failures.sendPort, debugName: 'chat-line-reader')
        .then((isolate) {
      if (reader._released) {
        isolate.kill();
      } else {
        reader._isolate = isolate;
      }
    }, onError: (Object error) {
      if (!lines.isClosed) {
        lines.add(ChatLine('',
            error: redactHarnessText('chat reader failed: $error')));
      }
      finish();
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
    (SendPort, bool, Set<String>, Map<String, CredentialRef>) setup) {
  final (main, rpc, deltas, known) = setup;
  for (final MapEntry(key: value, value: ref) in known.entries) {
    SecretRedactor.remember(ref, value);
  }
  final port = ReceivePort();
  final input = StreamController<List<int>>();
  var stopped = false;
  void stop(ChatLine last) {
    stopped = true;
    main.send(last);
    port.close();
    Isolate.exit();
  }

  input.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
    if (stopped) return;
    final read = rpc ? _rpcLine(line, deltas) : _textLine(line);
    if (read.error != null) {
      stop(read);
    } else {
      main.send(read);
    }
  }, onError: (Object error) {
    if (!stopped) {
      stop(ChatLine('', error: redactHarnessText(error.toString())));
    }
  }, onDone: () {
    if (stopped) return;
    stopped = true;
    port.close();
    Isolate.exit(main, _end);
  });
  port.listen((message) {
    switch (message) {
      case TransferableTypedData data:
        input.add(data.materialize().asUint8List());
      case (String value, CredentialRef ref):
        SecretRedactor.remember(ref, value);
      case _OutputError error:
        input.addError(error);
      case _end:
        input.close();
    }
  });
  main.send(port.sendPort);
}

ChatLine _textLine(String line) =>
    ChatLine(line, redactedText: redactHarnessText(line));

ChatLine _rpcLine(String line, Set<String> deltas) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected RPC object');
    }
    final method = decoded['method'] as String? ?? '';
    final params = decoded['params'] as Map?;
    final delta = deltas.contains(method) && params?['delta'] is String;
    return ChatLine(line,
        decoded: decoded,
        redacted: Map<String, dynamic>.from(redactHarnessJson(delta
            ? {
                ...decoded,
                'params': {...params!, 'delta': ''}
              }
            : decoded) as Map));
  } catch (error) {
    return ChatLine(line, error: redactHarnessText(error.toString()));
  }
}
