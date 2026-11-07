import 'dart:async';
import 'dart:convert';
import '../../security/credential_vault.dart';
import '../system/credential_changes.dart';
import '../system/foreground.dart';

/// 只在凭据提交、到期前一次性截止点或回前台时检查登录。
final class MeshCredentialWatch {
  MeshCredentialWatch(this.check,
      {Stream<CredentialRef>? changes,
      this.networkEvents,
      DateTime Function()? now})
      : changes = changes ?? CredentialChanges.changes,
        now = now ?? DateTime.now;
  final void Function() check;
  final Stream<CredentialRef> changes;
  final Stream<void>? networkEvents;
  final DateTime Function() now;
  StreamSubscription<CredentialRef>? _credentials;
  StreamSubscription<bool>? _foreground;
  StreamSubscription<void>? _network;
  Timer? _expiry, _retry;
  DateTime? _retryDeadline;
  DateTime? _deadline, _delivered;
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    _credentials = changes.listen((ref) {
      if (ref == const CredentialRef('preferences', 'dandanplay_token')) {
        check();
      }
    });
    _foreground = NextForeground.changes.listen((active) {
      final deadline = _deadline;
      if (active && deadline != null && !deadline.isAfter(now().toUtc())) {
        // 回前台的读取已经覆盖后台错过的截止点，避免同一恢复事件重复读取。
        _delivered = deadline;
      }
      _schedule();
      retryAt(_retryDeadline);
      _watchNetwork();
      if (active) check();
    });
    _watchNetwork();
  }

  void _watchNetwork() {
    _network?.cancel();
    _network = null;
    if (_started && NextForeground.active) {
      _network = networkEvents?.listen((_) => check(),
          onError: (Object _, StackTrace __) {});
    }
  }

  /// 仅对尚未加入的失败尝试保留前台单次重试，不定期读取健康会话的凭据。
  void retryAt(DateTime? deadline) {
    _retry?.cancel();
    _retry = null;
    _retryDeadline = deadline;
    if (!_started || !NextForeground.active || deadline == null) return;
    final remaining = deadline.difference(now());
    _retry = Timer(remaining.isNegative ? Duration.zero : remaining, check);
  }

  void observed(String? token) {
    if (!_started) return;
    final deadline = _expiration(token);
    if (deadline != _deadline) {
      _delivered = null;
    }
    _deadline = deadline;
    _schedule();
  }

  static DateTime? _expiration(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num || !exp.isFinite) return null;
      return DateTime.fromMillisecondsSinceEpoch((exp * 1000).round(),
              isUtc: true)
          .subtract(const Duration(minutes: 1));
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  void _schedule() {
    _expiry?.cancel();
    _expiry = null;
    final deadline = _deadline;
    if (!_started ||
        !NextForeground.active ||
        deadline == null ||
        _delivered == deadline) {
      return;
    }
    final remaining = deadline.difference(now().toUtc());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!_started || !NextForeground.active) return;
      _delivered = deadline;
      check();
    });
  }

  bool get pending => _expiry?.isActive == true;
  Future<void> close() async {
    _started = false;
    _expiry?.cancel();
    _retry?.cancel();
    await _credentials?.cancel();
    await _foreground?.cancel();
    await _network?.cancel();
    _credentials = null;
    _foreground = null;
  }
}
