import 'package:flutter/widgets.dart';

enum AccountActionRole { primary, secondary, neutral, destructive, plain }

class AccountActionViewModel {
  const AccountActionViewModel({
    required this.id,
    required this.label,
    required this.onPressed,
    this.role = AccountActionRole.secondary,
    this.isLoading = false,
  });

  final String id;
  final String label;
  final VoidCallback? onPressed;
  final AccountActionRole role;
  final bool isLoading;
}

class AccountPageViewModel {
  const AccountPageViewModel({
    required this.dandanplay,
    required this.bangumi,
  });

  static const String title = '账户';
  static const String dandanplayLabel = '弹弹play';
  static const String bangumiLabel = 'Bangumi';

  final DandanplayAccountViewModel dandanplay;
  final BangumiAccountViewModel bangumi;
}

class DandanplayAccountViewModel {
  const DandanplayAccountViewModel({
    required this.isLoggedIn,
    required this.username,
    required this.avatarUrl,
    required this.isLoading,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  static const String signedOutTitle = '登录弹弹play账号';
  static const String signedOutDescription = '登录后可同步观看记录、收藏和应用设置。';

  final bool isLoggedIn;
  final String username;
  final String? avatarUrl;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  List<AccountActionViewModel> get actions => isLoggedIn
      ? [
          AccountActionViewModel(
            id: 'logout',
            label: '退出登录',
            onPressed: onLogout,
            role: AccountActionRole.neutral,
          ),
          AccountActionViewModel(
            id: 'delete-account',
            label: isLoading ? '处理中...' : '注销账号',
            onPressed: isLoading ? null : onDeleteAccount,
            role: AccountActionRole.destructive,
            isLoading: isLoading,
          ),
        ]
      : [
          AccountActionViewModel(
            id: 'login',
            label: '立即登录',
            onPressed: onLogin,
            role: AccountActionRole.primary,
          ),
          AccountActionViewModel(
            id: 'register',
            label: '注册新账号',
            onPressed: onRegister,
            role: AccountActionRole.secondary,
          ),
        ];
}

class BangumiAccountViewModel {
  const BangumiAccountViewModel({
    required this.isAuthorized,
    required this.userInfo,
    required this.isDandanplayLoggedIn,
    required this.dandanLinkedInfo,
    required this.dandanLinkedExpireTime,
    required this.isRequestingDandanAuth,
    required this.isRefreshingDandanStatus,
    required this.isLoading,
    required this.isSyncing,
    required this.syncStatus,
    required this.lastSyncTime,
    required this.tokenController,
    required this.onRequestDandanAuth,
    required this.onOpenDandanManage,
    required this.onRefreshDandanStatus,
    required this.onSaveToken,
    required this.onClearToken,
    required this.onSync,
    required this.onFullSync,
    required this.onTestConnection,
    required this.onClearCache,
    required this.onOpenDandanHelp,
    required this.onOpenNipaplayHelp,
  });

  static const String dandanTitle = '弹弹play内置 Bangumi 绑定（仅同步进度）';
  static const String dandanDescription = '此方式不支持评论，仅用于弹弹服务器自动同步观看历史。';
  static const String tokenTitle = '访问令牌';
  static const String tokenDescription = '在 Bangumi 网站生成访问令牌后粘贴到此处。';
  static const String tokenPlaceholder = '请输入 Bangumi 访问令牌';
  static const String tokenHelpLabel = '如何获取 Bangumi 访问令牌';
  static const String actionsTitle = '同步操作';

  final bool isAuthorized;
  final Map<String, dynamic>? userInfo;
  final bool isDandanplayLoggedIn;
  final Map<String, dynamic>? dandanLinkedInfo;
  final DateTime? dandanLinkedExpireTime;
  final bool isRequestingDandanAuth;
  final bool isRefreshingDandanStatus;
  final bool isLoading;
  final bool isSyncing;
  final String syncStatus;
  final DateTime? lastSyncTime;
  final TextEditingController tokenController;
  final VoidCallback onRequestDandanAuth;
  final VoidCallback onOpenDandanManage;
  final VoidCallback onRefreshDandanStatus;
  final VoidCallback onSaveToken;
  final VoidCallback onClearToken;
  final VoidCallback onSync;
  final VoidCallback onFullSync;
  final VoidCallback onTestConnection;
  final VoidCallback onClearCache;
  final VoidCallback onOpenDandanHelp;
  final VoidCallback onOpenNipaplayHelp;

  bool get isDandanAuthorizationExpired =>
      dandanLinkedExpireTime != null &&
      dandanLinkedExpireTime!.isBefore(DateTime.now());

  String get dandanStatusText {
    if (!isDandanplayLoggedIn) return '请先登录弹弹play账号后再绑定。';
    if (dandanLinkedInfo == null) return '当前未绑定 Bangumi 账号。';
    final displayRaw = dandanLinkedInfo?['display']?.toString();
    final displayName = displayRaw != null && displayRaw.trim().isNotEmpty
        ? displayRaw.trim()
        : dandanLinkedInfo?['userName']?.toString();
    final userId = dandanLinkedInfo?['userId']?.toString();
    final label =
        displayName == null || displayName.isEmpty ? 'Bangumi用户' : displayName;
    return userId == null || userId.isEmpty
        ? '已绑定：$label'
        : '已绑定：$label（ID: $userId）';
  }

  String get connectionTitle => isAuthorized ? '已连接 Bangumi' : '尚未连接 Bangumi';

  String get connectionSubtitle {
    if (!isAuthorized) return '保存 Bangumi 访问令牌以启用观看历史同步。';
    final nickname = userInfo?['nickname'] ?? userInfo?['username'] ?? '已授权';
    return '当前账号：$nickname';
  }

  AccountActionViewModel get requestDandanAuthAction => AccountActionViewModel(
        id: 'dandan-authorize',
        label: isRequestingDandanAuth
            ? '获取授权链接中...'
            : (dandanLinkedInfo == null ? '绑定 Bangumi 账号' : '重新授权 Bangumi 账号'),
        onPressed: !isDandanplayLoggedIn || isRequestingDandanAuth
            ? null
            : onRequestDandanAuth,
        role: AccountActionRole.primary,
        isLoading: isRequestingDandanAuth,
      );

  AccountActionViewModel get manageDandanAction => AccountActionViewModel(
        id: 'dandan-manage',
        label: dandanLinkedInfo == null ? '先绑定后再管理同步设置' : '管理Bangumi同步设置',
        onPressed: !isDandanplayLoggedIn ||
                dandanLinkedInfo == null ||
                isRequestingDandanAuth
            ? null
            : onOpenDandanManage,
      );

  AccountActionViewModel get refreshDandanAction => AccountActionViewModel(
        id: 'dandan-refresh',
        label: isRefreshingDandanStatus ? '刷新中...' : '我已完成网页操作，刷新状态',
        onPressed: !isDandanplayLoggedIn || isRefreshingDandanStatus
            ? null
            : onRefreshDandanStatus,
        isLoading: isRefreshingDandanStatus,
      );

  List<AccountActionViewModel> get tokenActions => [
        AccountActionViewModel(
          id: 'save-token',
          label: '保存令牌',
          onPressed: isLoading ? null : onSaveToken,
          role: AccountActionRole.primary,
        ),
        AccountActionViewModel(
          id: 'clear-token',
          label: '删除令牌',
          onPressed: isLoading ? null : onClearToken,
        ),
      ];

  List<AccountActionViewModel> get syncActions => [
        AccountActionViewModel(
          id: 'incremental-sync',
          label: '增量同步',
          onPressed: isSyncing ? null : onSync,
          role: AccountActionRole.primary,
        ),
        AccountActionViewModel(
          id: 'full-sync',
          label: '全量同步',
          onPressed: isSyncing ? null : onFullSync,
        ),
        AccountActionViewModel(
          id: 'test-connection',
          label: '测试连接',
          onPressed: isSyncing ? null : onTestConnection,
        ),
        AccountActionViewModel(
          id: 'clear-sync-cache',
          label: '清除同步缓存',
          onPressed: isSyncing ? null : onClearCache,
          role: AccountActionRole.neutral,
        ),
      ];
}
