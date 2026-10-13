import 'dart:async';

import 'package:flutter/foundation.dart';

/// A login NipaPlay is waiting for: the agent asked for one and the user
/// has to type the secret in NipaPlay's own window, never in the chat.
final class LoginRequest {
  LoginRequest._(this.platform, this._show);

  /// Where to log in, as the user knows it: “弹弹play”, “Bangumi”, a
  /// media server's name.
  final String platform;
  final Future<Object?> Function() _show;
  final _result = Completer<Object?>();

  /// The window is open.
  bool opening = false;
}

/// Logins waiting for the user. While the Next shell is showing, a login the
/// agent starts waits here as a card until the user opens the window; when
/// it is not showing (a video plays in Classic's player) the window opens at
/// once, as it always did.
class LoginRequests extends ChangeNotifier {
  final pending = <LoginRequest>[];

  /// The shell is on screen to show the card.
  bool Function() showing = () => false;

  /// A new card arrived (the shell makes sure it can be seen).
  VoidCallback? onRequest;

  /// Platforms the person just asked to log in to from the interface (the
  /// settings page): their window opens at once, without a card.
  final _asked = <String>{};

  /// The next login for [platform] is the person's own: open its window
  /// directly. Forgotten after a minute if none comes.
  void expect(String platform) {
    _asked.add(platform);
    Timer(const Duration(minutes: 1), () => _asked.remove(platform));
  }

  /// Routes one login. [show] opens NipaPlay's own window and returns what
  /// the user entered; [stopped] completes when the login was cancelled.
  Future<T?> request<T>(
      String platform, Future<T?> Function() show, Future<void> stopped) {
    if (!showing() || _asked.remove(platform)) return show();
    final request = LoginRequest._(platform, show);
    pending.add(request);
    notifyListeners();
    onRequest?.call();
    stopped.then((_) {
      if (!request.opening) _finish(request, null);
    });
    return request._result.future.then((value) => value as T?);
  }

  /// “打开登录窗口”.
  Future<void> open(LoginRequest request) async {
    if (request.opening || request._result.isCompleted) return;
    request.opening = true;
    notifyListeners();
    try {
      _finish(request, await request._show());
    } catch (error, stack) {
      pending.remove(request);
      notifyListeners();
      request._result.completeError(error, stack);
    }
  }

  void _finish(LoginRequest request, Object? value) {
    if (request._result.isCompleted) return;
    pending.remove(request);
    notifyListeners();
    request._result.complete(value);
  }

  /// The shell is going away: whatever still waits gets its window now.
  @override
  void dispose() {
    for (final request in pending) {
      if (request.opening) continue;
      request.opening = true;
      request._show().then(request._result.complete,
          onError: request._result.completeError);
    }
    pending.clear();
    super.dispose();
  }
}
