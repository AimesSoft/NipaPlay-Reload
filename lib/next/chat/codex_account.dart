part of 'chat_host.dart';

extension CodexAccount on ChatHost {
  void _accountNotification(String method, Object? params) {
    if (method == 'account/login/completed' &&
        params is Map &&
        params['loginId'] != null &&
        params['loginId'] == _codexLoginId) {
      _codexLoginId = null;
      _codexLoginState = params['success'] == true ? 'completed' : 'failed';
    }
    _events.add({'method': 'host/accountChanged'});
  }

  Future<ChatMessage> accountStatus({required bool readOnly}) async {
    final response = await _request('account/read', {'refreshToken': false});
    final account = response['account'] as Map?;
    final type = account?['type'];
    return {
      'status': type == null ? 'signedOut' : 'signedIn',
      'readOnly': readOnly,
      if (!readOnly && _codexLoginState != null) 'loginState': _codexLoginState,
      if (type is String) 'type': redactHarnessText(type),
      if (account?['email'] case final String email)
        'email': redactHarnessText(email),
      if (account?['planType'] case final String plan)
        'plan': redactHarnessText(plan),
      if (type == 'chatgpt' && !readOnly) ...await _accountMetrics(),
    };
  }

  Future<ChatMessage> _accountMetrics() async {
    Future<ChatMessage?> optional(String method) async {
      try {
        return await _request(method, {}).timeout(const Duration(seconds: 12));
      } catch (_) {
        return null;
      }
    }

    final (rate, usage) = await (
      optional('account/rateLimits/read'),
      optional('account/usage/read')
    ).wait;
    return codexAccountMetrics(rate, usage);
  }

  Future<UiCodexLogin> beginCodexLogin({required bool deviceCode}) =>
      _control(() async {
        await _applyModel();
        if (dsh != null || _launch?.home == null || _codexLoginId != null) {
          throw StateError('当前不能开始登录');
        }
        final reply = await _request('account/login/start', {
          'type': deviceCode ? 'chatgptDeviceCode' : 'chatgpt',
        });
        _codexLoginId = reply['loginId'] as String;
        final url = Uri.tryParse(
            (reply[deviceCode ? 'verificationUrl' : 'authUrl'] as String?) ??
                '');
        if (url == null ||
            url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            url.host != 'auth.openai.com') {
          await _cancelAccountLogin();
          throw StateError('授权地址无效');
        }
        _codexLoginState = 'pending';
        return (
          url: url,
          code: deviceCode ? reply['userCode'] as String? : null
        );
      });

  Future<void> cancelCodexLogin() => _control(_cancelAccountLogin);

  Future<void> _cancelAccountLogin() async {
    final id = _codexLoginId;
    if (id == null) return;
    final reply = await _request('account/login/cancel', {'loginId': id});
    if (reply['status'] != 'canceled' && _codexLoginId == id) {
      throw StateError('没能取消登录');
    }
    _codexLoginId = null;
    _codexLoginState = 'canceled';
    _events.add({'method': 'host/accountChanged'});
  }
}

ChatMessage codexAccountMetrics(Map? rate, Map? usage) {
  Map<String, num> numbers(Object? data, List<String> keys) => {
        if (data is Map)
          for (final key in keys)
            if (data[key] case final num number) key: number,
      };
  final byId = rate?['rateLimitsByLimitId'];
  final limits =
      byId is Map && byId.isNotEmpty ? byId.values : [rate?['rateLimits']];
  return {
    'rateLimitsAvailable': rate != null,
    'usageAvailable': usage != null,
    if (rate != null)
      'rateLimits': [
        for (final limit in limits.whereType<Map>())
          {
            if (limit['limitName'] case final String name)
              'name': redactHarnessText(name),
            for (final key in ['primary', 'secondary'])
              if (limit[key] is Map)
                key: numbers(limit[key],
                    ['usedPercent', 'windowDurationMins', 'resetsAt'])
          },
      ],
    if (usage != null)
      'usage': numbers(usage['summary'], [
        'lifetimeTokens',
        'peakDailyTokens',
        'currentStreakDays',
        'longestStreakDays',
        'longestRunningTurnSec',
      ]),
  };
}
