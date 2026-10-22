import 'dart:io';

import 'package:fvp/mdk.dart' as mdk;

/// fvp's one log handler for all of MDK in this process.
abstract interface class MdkLogHandlers {
  /// Whether fvp's log channel replaced MDK's own default log handling
  /// (any call to [set] opens it, and it stays open).
  bool get channelOpen;

  /// The handler fvp calls now.
  void Function(mdk.LogLevel, String)? get current;

  void set(void Function(mdk.LogLevel, String)? handler);
}

final class FvpLogHandlers implements MdkLogHandlers {
  const FvpLogHandlers();
  @override
  bool get channelOpen => mdk.logChannelOpen;
  @override
  void Function(mdk.LogLevel, String)? get current => mdk.currentLogHandler;
  @override
  void set(void Function(mdk.LogLevel, String)? handler) =>
      mdk.setLogHandler(handler);
}

/// MDK's log lines while Next is on. fvp has one handler for the process;
/// Next takes it and passes every line, as it came, to the handler that was
/// there, so what that handler does (fvp's Logger on Windows and Linux)
/// stays the same. Where fvp had opened no channel MDK's own default is
/// silence, which is what a passed-on line becomes; with `MDK_LOG` set MDK
/// writes its own stderr lines, which Next could only imitate, so it leaves
/// MDK alone then. Turning Next off gives the previous handler back.
final class MdkNativeLog {
  MdkNativeLog(this._handlers, {Map<String, String>? environment})
      : _environment = environment;
  static final instance = MdkNativeLog(const FvpLogHandlers());

  final MdkLogHandlers _handlers;
  final Map<String, String>? _environment;
  void Function(String level, String text)? _observer;
  void Function(mdk.LogLevel, String)? _previous;
  bool _channelWasOpen = false;
  bool _installed = false;
  String? _notAttached;

  /// Why MDK's lines are not being read, or null when they are.
  String? get notAttached => _installed ? null : _notAttached;

  bool get _mdkWritesStderr {
    final value = (_environment ?? Platform.environment)['MDK_LOG'];
    return value != null && value.isNotEmpty && value != '0';
  }

  void attach(void Function(String level, String text) observer) {
    _observer = observer;
    if (_installed) return;
    try {
      _channelWasOpen = _handlers.channelOpen;
      if (!_channelWasOpen && _mdkWritesStderr) {
        _notAttached = 'mdk_log_env';
        return;
      }
      _previous = _handlers.current;
      _handlers.set(_forward);
      _installed = true;
      _notAttached = null;
    } catch (error) {
      _notAttached = 'unavailable: $error';
    }
  }

  void detach() {
    _observer = null;
    if (!_installed) return;
    _installed = false;
    try {
      // Someone set their own since: theirs stays.
      if (_handlers.current != _forward) return;
      _handlers.set(_previous);
    } catch (_) {}
  }

  void _forward(mdk.LogLevel level, String message) {
    _previous?.call(level, message);
    final observer = _observer;
    if (observer == null) return;
    observer(level.name,
        message.endsWith('\n') ? message.substring(0, message.length - 1) : message);
  }
}
