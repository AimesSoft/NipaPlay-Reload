import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/loading_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/loading_placeholder.dart';
import '../providers/watch_history_provider.dart';
import '../providers/appearance_settings_provider.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_tab.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/history_all_modal.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_server_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/dandanplay_remote_library_view.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings_page.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

// Custom ScrollBehavior for NoScrollbarBehavior is removed as NestedScrollView handles scrolling differently.

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin<AnimePage> {
  final bool _loadingVideo = false;
  final List<String> _loadingMessages = ['正在初始化播放器...'];
  VideoPlayerState? _videoPlayerState;
  final ScrollController _mainPageScrollController =
      ScrollController(); // Used for NestedScrollView
  final ScrollController _watchHistoryListScrollController = ScrollController();

  // 仅保留当前标签页索引用于初始化_MediaLibraryTabs
  final int _currentTabIndex = 0;

  final int _mediaLibraryVersion = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false);
    _setupThumbnailUpdateListener();
  }

  void _setupThumbnailUpdateListener() {
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.addThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {
      //debugPrint('设置缩略图更新监听器时出错: $e');
    }
  }

  void _onThumbnailUpdated() {
    if (!mounted) return;
    // 不再清理所有图片缓存，避免影响番剧卡片的封面显示
    // 只触发UI重建来显示新的缩略图
    setState(() {
      // 触发UI重建，让新的缩略图能够显示
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (_videoPlayerState != null) {
        _videoPlayerState!.removeThumbnailUpdateListener(_onThumbnailUpdated);
      }
    } catch (e) {}
    _mainPageScrollController.dispose();
    _watchHistoryListScrollController.dispose();
    super.dispose();
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    debugPrint('[AnimePage] _onWatchHistoryItemTap: Received item: $item');

    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') ||
        item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');

    bool fileExists = false;
    String filePath = item.filePath;
    PlaybackSession? playbackSession;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            playbackSession = await jellyfinService.createPlaybackSession(
              itemId: jellyfinId,
              startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
            );
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Jellyfin播放会话失败: $e');
          return;
        }
      }

      if (isEmbyProtocol) {
        try {
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            playbackSession = await embyService.createPlaybackSession(
              itemId: embyId,
              startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
            );
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Emby播放会话失败: $e');
          return;
        }
      }
    } else {
      if (kIsWeb) {
        fileExists = true;
      } else {
        final videoFile = File(item.filePath);
        fileExists = videoFile.existsSync();
        if (!fileExists && Platform.isIOS) {
          String altPath = filePath.startsWith('/private')
              ? filePath.replaceFirst('/private', '')
              : '/private$filePath';

          final File altFile = File(altPath);
          if (altFile.existsSync()) {
            filePath = altPath;
            item = item.copyWith(filePath: filePath);
            fileExists = true;
          }
        }
      }
    }

    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      playbackSession: playbackSession,
    );

    await PlaybackService().play(playableItem);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        return Builder(
          builder: (context) {
            final scanService = Provider.of<ScanService>(context);

            // 移除DefaultTabController，直接使用Stack
            return Stack(
              children: [
                NestedScrollView(
                  controller: _mainPageScrollController,
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[];
                  },
                  body: Builder(
                    builder: (context) {
                      return _MediaLibraryTabs(
                        initialIndex: _currentTabIndex,
                        onPlayEpisode: _onWatchHistoryItemTap,
                        mediaLibraryVersion: _mediaLibraryVersion,
                      );
                    },
                  ),
                ),
                if (_loadingVideo)
                  Positioned.fill(
                    child: LoadingOverlay(
                      messages: _loadingMessages,
                      animeTitle: null,
                      episodeTitle: null,
                      fileName: null,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// 在文件末尾添加新的类用于管理媒体库标签页
class _MediaLibraryTabs extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<WatchHistoryItem> onPlayEpisode;
  final int mediaLibraryVersion;

  const _MediaLibraryTabs({
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  });

  @override
  State<_MediaLibraryTabs> createState() => _MediaLibraryTabsState();
}

class _MediaLibraryTabsState extends State<_MediaLibraryTabs>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;
  bool _isJellyfinConnected = false;
  bool _isEmbyConnected = false;
  bool _hasSharedRemoteHosts = false;
  bool _isDandanConnected = false;
  bool _hasWebDAVConnections = false;
  bool _hasSMBConnections = false;
  bool _hasWebDAVLibrary = false;
  bool _hasSMBLibrary = false;
  bool _localConnectionsReady = false;
  String? _remoteManagementHostId;

  // 添加变量追踪“添加媒体服务器”入口的悬停状态
  bool _isAddEntryHovered = false;
  bool _isRemoteAccessHovered = false;

  bool get _showLocalTabs => !kIsWeb;
  bool get _showSharedRemoteTabs => _hasSharedRemoteHosts || kIsWeb;

  // 动态计算标签页数量
  int get _tabCount {
    int count = _showLocalTabs ? 2 : 0; // 基础标签: 本地媒体库, 本地库管理
    if (_hasWebDAVLibrary) count++;
    if (_hasWebDAVConnections) count++;
    if (_hasSMBLibrary) count++;
    if (_hasSMBConnections) count++;
    if (_showSharedRemoteTabs) count += 2; // 共享媒体库, 共享库管理
    if (_isDandanConnected) count++;
    if (_isJellyfinConnected) count++;
    if (_isEmbyConnected) count++;
    return count;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _checkConnectionStates();
    _tabController = TabController(
        length: _tabCount, vsync: this, initialIndex: _currentIndex);
    _tabController.addListener(_handleTabChange);

    // 监听子标签切换通知
    _setupSubTabListener();
    if (!kIsWeb) {
      _initLocalConnectionStates();
    }

    // 立即检查是否有待处理的子标签切换请求
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingSubTabChange();
    });

    print('_MediaLibraryTabs创建TabController：动态长度${_tabController.length}');
  }

  void _checkConnectionStates() {
    final jellyfinProvider =
        Provider.of<JellyfinProvider>(context, listen: false);
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    final sharedProvider =
        Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
    final dandanProvider =
        Provider.of<DandanplayRemoteProvider>(context, listen: false);
    _isJellyfinConnected = jellyfinProvider.isConnected;
    _isEmbyConnected = embyProvider.isConnected;
    _hasSharedRemoteHosts = sharedProvider.hasReachableActiveHost;
    _isDandanConnected = dandanProvider.isConnected;
    print(
        '_MediaLibraryTabs: 连接状态检查 - Jellyfin: $_isJellyfinConnected, Emby: $_isEmbyConnected, Dandan: $_isDandanConnected');
  }

  Future<void> _initLocalConnectionStates() async {
    await Future.wait([
      WebDAVService.instance.initialize(),
      SMBService.instance.initialize(),
    ]);

    if (!mounted) return;
    _localConnectionsReady = true;
    _refreshLocalConnectionStates();
  }

  void _refreshLocalConnectionStates() {
    if (kIsWeb) {
      return;
    }
    final hasWebdav = WebDAVService.instance.connections.isNotEmpty;
    final hasSmb = SMBService.instance.connections.isNotEmpty;

    if (hasWebdav == _hasWebDAVConnections && hasSmb == _hasSMBConnections) {
      return;
    }

    _updateTabController(
      _isJellyfinConnected,
      _isEmbyConnected,
      _hasSharedRemoteHosts,
      _isDandanConnected,
      hasWebdav,
      hasSmb,
      _hasWebDAVLibrary,
      _hasSMBLibrary,
    );
  }

  void _maybeBootstrapRemoteManagement(SharedRemoteLibraryProvider provider) {
    if (!kIsWeb) return;
    final hostId = provider.activeHostId;
    if (hostId == null || hostId.isEmpty) return;
    if (_remoteManagementHostId == hostId) return;
    _remoteManagementHostId = hostId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.refreshManagement();
    });
  }

  bool _hasLibraryItemsForSource(
    WatchHistoryProvider provider,
    MediaLibrarySourceType sourceType,
  ) {
    if (!provider.isLoaded) return false;
    return provider.history.any((item) {
      if (item.animeId == null) return false;
      if (item.filePath.startsWith('jellyfin://') ||
          item.filePath.startsWith('emby://')) {
        return false;
      }
      if (item.filePath.contains('/api/media/local/share/')) {
        return false;
      }
      if (item.isDandanplayRemote) {
        return false;
      }
      switch (sourceType) {
        case MediaLibrarySourceType.webdav:
          return MediaSourceUtils.isWebDavPath(item.filePath);
        case MediaLibrarySourceType.smb:
          return MediaSourceUtils.isSmbPath(item.filePath);
        case MediaLibrarySourceType.local:
        default:
          return false;
      }
    });
  }

  TabChangeNotifier? _tabChangeNotifierRef;

  void _setupSubTabListener() {
    try {
      _tabChangeNotifierRef =
          Provider.of<TabChangeNotifier>(context, listen: false);
      _tabChangeNotifierRef?.addListener(_onSubTabChangeRequested);
      debugPrint('[_MediaLibraryTabs] 已设置子标签切换监听器');
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 设置子标签切换监听器失败: $e');
    }
  }

  void _onSubTabChangeRequested() {
    try {
      final subTabIndex = _tabChangeNotifierRef?.targetMediaLibrarySubTabIndex;

      if (subTabIndex != null && subTabIndex != _currentIndex) {
        debugPrint('[_MediaLibraryTabs] 接收到子标签切换请求: $subTabIndex');

        // 确保索引在有效范围内
        if (subTabIndex >= 0 && subTabIndex < _tabCount) {
          _tabController.animateTo(subTabIndex);
          debugPrint('[_MediaLibraryTabs] 已切换到子标签: $subTabIndex');

          // 清除切换请求
          _tabChangeNotifierRef?.clearSubTabIndex();
        } else {
          debugPrint(
              '[_MediaLibraryTabs] 子标签索引超出范围: $subTabIndex (最大: ${_tabCount - 1})');
        }
      }
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 处理子标签切换请求失败: $e');
    }
  }

  void _checkPendingSubTabChange() {
    try {
      final subTabIndex = _tabChangeNotifierRef?.targetMediaLibrarySubTabIndex;

      if (subTabIndex != null && subTabIndex != _currentIndex) {
        debugPrint('[_MediaLibraryTabs] 发现待处理的子标签切换请求: $subTabIndex');

        // 确保索引在有效范围内
        if (subTabIndex >= 0 && subTabIndex < _tabCount) {
          _tabController.animateTo(subTabIndex);
          debugPrint('[_MediaLibraryTabs] 执行待处理的子标签切换: $subTabIndex');

          // 清除切换请求
          _tabChangeNotifierRef?.clearSubTabIndex();
        } else {
          debugPrint(
              '[_MediaLibraryTabs] 待处理子标签索引超出范围: $subTabIndex (最大: ${_tabCount - 1})');
        }
      } else {
        debugPrint('[_MediaLibraryTabs] 无待处理的子标签切换请求');
      }
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 检查待处理子标签切换请求失败: $e');
    }
  }

  @override
  void dispose() {
    //debugPrint('[CPU-泄漏排查] _MediaLibraryTabsState dispose 被调用');
    _tabController.removeListener(_handleTabChange);

    // 移除子标签切换监听器，使用缓存的引用避免访问已销毁的context
    try {
      _tabChangeNotifierRef?.removeListener(_onSubTabChangeRequested);
      _tabChangeNotifierRef = null;
      debugPrint('[_MediaLibraryTabs] 已移除子标签切换监听器');
    } catch (e) {
      debugPrint('[_MediaLibraryTabs] 移除子标签切换监听器失败: $e');
    }

    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    //debugPrint('[CPU-泄漏排查] TabController索引变化: ${_tabController.index}，indexIsChanging: ${_tabController.indexIsChanging}');
    if (!_tabController.indexIsChanging) return;

    if (_currentIndex != _tabController.index) {
      setState(() {
        _currentIndex = _tabController.index;
      });
    }
  }

  Future<void> _showServerSelectionDialog() async {
    final result = await MediaServerSelectionSheet.show(context);

    if (!mounted || result == null) {
      return;
    }

    switch (result) {
      case 'local_folder':
        await _addLocalFolder();
        break;
      case 'jellyfin':
        await _showJellyfinServerDialog();
        break;
      case 'emby':
        await _showEmbyServerDialog();
        break;
      case 'webdav':
        await _showWebDAVConnectionDialog();
        break;
      case 'smb':
        await _showSMBConnectionDialog();
        break;
      case 'nipaplay':
        await _showNipaplayServerDialog();
        break;
      case 'dandanplay':
        await _showDandanplayServerDialog();
        break;
    }
  }

  Future<void> _addLocalFolder() async {
    if (kIsWeb) {
      if (mounted) {
        BlurSnackBar.show(context, 'Web 端暂不支持添加本地文件夹');
      }
      return;
    }

    final scanService = Provider.of<ScanService>(context, listen: false);
    if (scanService.isScanning) {
      if (mounted) {
        BlurSnackBar.show(context, '已有扫描任务在进行中，请稍后。');
      }
      return;
    }

    final selectedDirectory = await FilePickerService().pickDirectory();
    if (selectedDirectory == null || selectedDirectory.trim().isEmpty) {
      return;
    }

    await scanService.startDirectoryScan(
      selectedDirectory,
      skipPreviouslyMatchedUnwatched: false,
    );

    if (!mounted) return;
    BlurSnackBar.show(context, '已开始扫描：${path.basename(selectedDirectory)}');
  }

  Future<void> _showJellyfinServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.jellyfin);
  }

  Future<void> _showEmbyServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.emby);
  }

  Future<void> _showWebDAVConnectionDialog() async {
    if (kIsWeb) {
      final provider =
          Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
      final result = await WebDAVConnectionDialog.show(
        context,
        onSave: (connection) async {
          await provider.addWebDAVConnection(connection);
          if (provider.managementErrorMessage != null) {
            throw provider.managementErrorMessage!;
          }
          return true;
        },
        onTest: (connection) =>
            provider.testWebDAVConnection(connection: connection),
      );
      if (result == true && mounted) {
        await provider.refreshManagement(userInitiated: true);
      }
      return;
    }

    if (!_localConnectionsReady) {
      await _initLocalConnectionStates();
    }

    final result = await WebDAVConnectionDialog.show(context);
    if (result == true && mounted) {
      _refreshLocalConnectionStates();
    }
  }

  Future<void> _showSMBConnectionDialog() async {
    if (kIsWeb) {
      final provider =
          Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
      final result = await SMBConnectionDialog.show(
        context,
        onSave: (connection) async {
          await provider.addSMBConnection(connection);
          return provider.managementErrorMessage == null;
        },
      );
      if (result == true && mounted) {
        await provider.refreshManagement(userInitiated: true);
      }
      return;
    }

    if (!_localConnectionsReady) {
      await _initLocalConnectionStates();
    }

    final result = await SMBConnectionDialog.show(context);
    if (result == true && mounted) {
      _refreshLocalConnectionStates();
    }
  }

  Future<void> _showNipaplayServerDialog() async {
    await SharedRemoteHostSelectionSheet.show(context);
  }

  Future<void> _showDandanplayServerDialog() async {
    final provider =
        Provider.of<DandanplayRemoteProvider>(context, listen: false);
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    final hasExisting = provider.serverUrl?.isNotEmpty == true;

    final result = await BlurLoginDialog.show(
      context,
      title: hasExisting ? '更新弹弹play远程连接' : '连接弹弹play远程服务',
      loginButtonText: hasExisting ? '保存' : '连接',
      fields: [
        LoginField(
          key: 'baseUrl',
          label: '远程服务地址',
          hint: '例如 http://192.168.1.2:23333',
          initialValue: provider.serverUrl ?? '',
        ),
        LoginField(
          key: 'token',
          label: 'API密钥 (可选)',
          hint: provider.tokenRequired ? '服务器已启用 API 验证' : '若服务器开启验证请填写',
          isPassword: true,
          required: false,
        ),
      ],
      onLogin: (values) async {
        final baseUrl = values['baseUrl'] ?? '';
        final token = values['token'];
        if (baseUrl.isEmpty) {
          return const LoginResult(success: false, message: '请输入远程服务地址');
        }
        try {
          await provider.connect(baseUrl, token: token);
          return const LoginResult(
            success: true,
            message: '已连接至弹弹play远程服务',
          );
        } catch (e) {
          return LoginResult(success: false, message: e.toString());
        }
      },
    );

    if (result == true && mounted) {
      BlurSnackBar.show(context, '弹弹play远程服务配置已更新');
    }
  }

  void _openRemoteAccessSettings() {
    SettingsPage.showWindow(
      context,
      initialEntryId: SettingsPage.entryRemoteAccess,
    );
  }

  Widget _buildRemoteAccessEntry({
    required Color iconColor,
    required Color textColor,
  }) {
    const Color hoverColor = Color(0xFFFF2E55);
    final Color displayColor = _isRemoteAccessHovered ? hoverColor : textColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isRemoteAccessHovered = true),
        onExit: (_) => setState(() => _isRemoteAccessHovered = false),
        child: GestureDetector(
          onTap: _openRemoteAccessSettings,
          child: AnimatedScale(
            scale: _isRemoteAccessHovered ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link, size: 18, color: displayColor),
                const SizedBox(width: 6),
                Text(
                  '远程访问',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: displayColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMediaServerEntry({
    required Color iconColor,
    required Color textColor,
  }) {
    const Color hoverColor = Color(0xFFFF2E55);
    final Color displayColor = _isAddEntryHovered ? hoverColor : textColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isAddEntryHovered = true),
        onExit: (_) => setState(() => _isAddEntryHovered = false),
        child: GestureDetector(
          onTap: _showServerSelectionDialog,
          child: AnimatedScale(
            scale: _isAddEntryHovered ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_outlined, size: 18, color: displayColor),
                const SizedBox(width: 6),
                Text(
                  '添加媒体',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    color: displayColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final enableAnimation = appearanceSettings.enablePageAnimation;

    return Consumer5<
        JellyfinProvider,
        EmbyProvider,
        SharedRemoteLibraryProvider,
        DandanplayRemoteProvider,
        WatchHistoryProvider>(
      builder: (context, jellyfinProvider, embyProvider, sharedProvider,
          dandanProvider, watchHistoryProvider, child) {
        _maybeBootstrapRemoteManagement(sharedProvider);
        final currentJellyfinConnectionState = jellyfinProvider.isConnected;
        final currentEmbyConnectionState = embyProvider.isConnected;
        final currentSharedState = sharedProvider.hasReachableActiveHost;
        final currentDandanState = dandanProvider.isConnected;
        final currentHasWebdav = kIsWeb
            ? sharedProvider.webdavConnections.isNotEmpty
            : (_localConnectionsReady
                ? WebDAVService.instance.connections.isNotEmpty
                : _hasWebDAVConnections);
        final currentHasSmb = kIsWeb
            ? sharedProvider.smbConnections.isNotEmpty
            : (_localConnectionsReady
                ? SMBService.instance.connections.isNotEmpty
                : _hasSMBConnections);
        final currentHasWebdavLibrary = watchHistoryProvider.isLoaded
            ? _hasLibraryItemsForSource(
                watchHistoryProvider,
                MediaLibrarySourceType.webdav,
              )
            : _hasWebDAVLibrary;
        final currentHasSmbLibrary = watchHistoryProvider.isLoaded
            ? _hasLibraryItemsForSource(
                watchHistoryProvider,
                MediaLibrarySourceType.smb,
              )
            : _hasSMBLibrary;

        // 检查连接状态是否改变
        if (_isJellyfinConnected != currentJellyfinConnectionState ||
            _isEmbyConnected != currentEmbyConnectionState ||
            _hasSharedRemoteHosts != currentSharedState ||
            _isDandanConnected != currentDandanState ||
            _hasWebDAVConnections != currentHasWebdav ||
            _hasSMBConnections != currentHasSmb ||
            _hasWebDAVLibrary != currentHasWebdavLibrary ||
            _hasSMBLibrary != currentHasSmbLibrary) {
          print(
              '_MediaLibraryTabs: 连接状态发生变化 - Jellyfin: $_isJellyfinConnected -> $currentJellyfinConnectionState, Emby: $_isEmbyConnected -> $currentEmbyConnectionState, Shared: $_hasSharedRemoteHosts -> $currentSharedState, Dandan: $_isDandanConnected -> $currentDandanState');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _updateTabController(
                currentJellyfinConnectionState,
                currentEmbyConnectionState,
                currentSharedState,
                currentDandanState,
                currentHasWebdav,
                currentHasSmb,
                currentHasWebdavLibrary,
                currentHasSmbLibrary,
              );
            }
          });
        }

        // 动态生成标签页内容
        final List<Widget> pageChildren = [];

        if (_showLocalTabs) {
          pageChildren.addAll([
            RepaintBoundary(
              child: MediaLibraryPage(
                key: ValueKey(
                    'mediaLibrary_local_${widget.mediaLibraryVersion}'),
                onPlayEpisode: widget.onPlayEpisode,
                onSourcesUpdated: _refreshLocalConnectionStates,
                sourceType: MediaLibrarySourceType.local,
              ),
            ),
            RepaintBoundary(
              child: LibraryManagementTab(
                key: const ValueKey('library_management_local'),
                onPlayEpisode: widget.onPlayEpisode,
                section: LibraryManagementSection.local,
              ),
            ),
          ]);
        }

        if (_hasWebDAVLibrary) {
          pageChildren.add(
            RepaintBoundary(
              child: MediaLibraryPage(
                key: ValueKey(
                    'mediaLibrary_webdav_${widget.mediaLibraryVersion}'),
                onPlayEpisode: widget.onPlayEpisode,
                sourceType: MediaLibrarySourceType.webdav,
              ),
            ),
          );
        }

        if (_hasWebDAVConnections) {
          pageChildren.add(
            RepaintBoundary(
              child: LibraryManagementTab(
                key: const ValueKey('library_management_webdav'),
                onPlayEpisode: widget.onPlayEpisode,
                section: LibraryManagementSection.webdav,
              ),
            ),
          );
        }

        if (_hasSMBLibrary) {
          pageChildren.add(
            RepaintBoundary(
              child: MediaLibraryPage(
                key: ValueKey('mediaLibrary_smb_${widget.mediaLibraryVersion}'),
                onPlayEpisode: widget.onPlayEpisode,
                sourceType: MediaLibrarySourceType.smb,
              ),
            ),
          );
        }

        if (_hasSMBConnections) {
          pageChildren.add(
            RepaintBoundary(
              child: LibraryManagementTab(
                key: const ValueKey('library_management_smb'),
                onPlayEpisode: widget.onPlayEpisode,
                section: LibraryManagementSection.smb,
              ),
            ),
          );
        }

        if (_showSharedRemoteTabs) {
          // 共享媒体库
          pageChildren.add(
            RepaintBoundary(
              child: SharedRemoteLibraryView(
                key: const ValueKey('shared_media_library'),
                onPlayEpisode: widget.onPlayEpisode,
                mode: SharedRemoteViewMode.mediaLibrary,
              ),
            ),
          );
          // 共享库管理
          pageChildren.add(
            RepaintBoundary(
              child: SharedRemoteLibraryView(
                key: const ValueKey('shared_library_management'),
                onPlayEpisode: widget.onPlayEpisode,
                mode: SharedRemoteViewMode.libraryManagement,
              ),
            ),
          );
        }

        if (_isDandanConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: DandanplayRemoteLibraryView(
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }

        if (_isJellyfinConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: NetworkMediaLibraryView(
                serverType: NetworkMediaServerType.jellyfin,
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }

        if (_isEmbyConnected) {
          pageChildren.add(
            RepaintBoundary(
              child: NetworkMediaLibraryView(
                serverType: NetworkMediaServerType.emby,
                onPlayEpisode: widget.onPlayEpisode,
              ),
            ),
          );
        }

        // 动态生成标签
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        const Color activeColor = Color(0xFFFF2E55);
        final unselectedLabelColor =
            isDarkMode ? Colors.white60 : Colors.black54;

        final List<Widget> tabs = [];

        if (_showLocalTabs) {
          tabs.addAll([
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "本地媒体库",
                fontSize: 18,
                icon: Icon(Icons.tv_outlined, size: 18),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "本地库管理",
                fontSize: 18,
                icon: Icon(Icons.folder_open_outlined, size: 18),
              ),
            ),
          ]);
        }

        if (_hasWebDAVLibrary) {
          tabs.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "WebDAV媒体库",
                fontSize: 18,
                icon: Icon(Icons.cloud_outlined, size: 18),
              ),
            ),
          );
        }

        if (_hasWebDAVConnections) {
          tabs.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "WebDAV库管理",
                fontSize: 18,
                icon: Icon(Icons.cloud_outlined, size: 18),
              ),
            ),
          );
        }

        if (_hasSMBLibrary) {
          tabs.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "SMB媒体库",
                fontSize: 18,
                icon: Icon(Icons.lan_outlined, size: 18),
              ),
            ),
          );
        }

        if (_hasSMBConnections) {
          tabs.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: "SMB库管理",
                fontSize: 18,
                icon: Icon(Icons.lan_outlined, size: 18),
              ),
            ),
          );
        }

        if (_showSharedRemoteTabs) {
          // 共享媒体库
          tabs.add(const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: HoverZoomTab(
              text: "共享媒体库",
              fontSize: 18,
              icon: Image(
                image: AssetImage('assets/nipaplay.png'),
                width: 18,
                height: 18,
              ),
            ),
          ));
          // 共享库管理
          tabs.add(const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: HoverZoomTab(
              text: "共享库管理",
              fontSize: 18,
              icon: Icon(Icons.settings_suggest_outlined, size: 18),
            ),
          ));
        }

        if (_isDandanConnected) {
          tabs.add(const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0),
            child: HoverZoomTab(
              text: "弹弹play",
              fontSize: 18,
              icon: Image(
                image: AssetImage('assets/dandanplay.png'),
                width: 18,
                height: 18,
              ),
            ),
          ));
        }

        if (_isJellyfinConnected) {
          tabs.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: HoverZoomTab(
              text: "Jellyfin",
              fontSize: 18,
              icon: SvgPicture.asset(
                'assets/jellyfin.svg',
                width: 18,
                height: 18,
              ),
            ),
          ));
        }

        if (_isEmbyConnected) {
          tabs.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: HoverZoomTab(
              text: "Emby",
              fontSize: 18,
              icon: SvgPicture.asset(
                'assets/emby.svg',
                width: 18,
                height: 18,
              ),
            ),
          ));
        }

        // 验证标签数量与内容数量是否匹配
        if (tabs.length != pageChildren.length || tabs.length != _tabCount) {
          print(
              '警告：标签数量(${tabs.length})、内容数量(${pageChildren.length})与预期数量($_tabCount)不匹配');
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // 检查可用高度，如果太小则使用最小安全布局
            final availableHeight = constraints.maxHeight;
            final isHeightConstrained = availableHeight < 100; // 小于100像素视为高度受限

            if (isHeightConstrained) {
              // 高度受限时，使用简化布局避免溢出
              return SizedBox(
                height: availableHeight,
                child: const Center(
                  child: Text(
                    '布局空间不足',
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              );
            }

            return Column(
              children: [
                // TabBar - 使用Flexible包装以防溢出
                Flexible(
                  flex: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12.0, right: 32.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              tabs: tabs,
                              labelColor: activeColor,
                              unselectedLabelColor: unselectedLabelColor,
                              labelPadding: const EdgeInsets.only(bottom: 12.0),
                              indicatorPadding: EdgeInsets.zero,
                              indicator: const _CustomTabIndicator(
                                indicatorHeight: 3.0,
                                indicatorColor: activeColor,
                                radius: 30.0,
                              ),
                              tabAlignment: TabAlignment.start,
                              splashFactory: NoSplash.splashFactory,
                              overlayColor:
                                  WidgetStateProperty.all(Colors.transparent),
                              // 移除灰色滑轨
                              dividerColor: Colors.transparent,
                              dividerHeight: 3.0,
                              indicatorSize: TabBarIndicatorSize.label,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!globals.isPhone) ...[
                          _buildRemoteAccessEntry(
                            iconColor: activeColor,
                            textColor: unselectedLabelColor,
                          ),
                          const SizedBox(width: 12),
                        ],
                        _buildAddMediaServerEntry(
                          iconColor: activeColor,
                          textColor: unselectedLabelColor,
                        ),
                      ],
                    ),
                  ),
                ),
                // 内容区域 - 确保占用剩余所有空间
                Expanded(
                  child: SwitchableView(
                    enableAnimation:
                        false, // 🔥 CPU优化：强制禁用媒体库内部动画，避免TabBarView同时渲染所有页面
                    currentIndex: _currentIndex,
                    controller: _tabController,
                    physics: enableAnimation
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      if (_currentIndex != index) {
                        setState(() {
                          _currentIndex = index;
                        });
                        _tabController.animateTo(index);
                        print('页面变更到: $index (启用动画: $enableAnimation)');
                      }
                    },
                    children: pageChildren,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateTabController(
    bool isJellyfinConnected,
    bool isEmbyConnected,
    bool hasSharedHosts,
    bool isDandanConnected,
    bool hasWebdavConnections,
    bool hasSmbConnections,
    bool hasWebdavLibrary,
    bool hasSmbLibrary,
  ) {
    if (_isJellyfinConnected == isJellyfinConnected &&
        _isEmbyConnected == isEmbyConnected &&
        _hasSharedRemoteHosts == hasSharedHosts &&
        _isDandanConnected == isDandanConnected &&
        _hasWebDAVConnections == hasWebdavConnections &&
        _hasSMBConnections == hasSmbConnections &&
        _hasWebDAVLibrary == hasWebdavLibrary &&
        _hasSMBLibrary == hasSmbLibrary) {
      return;
    }

    final oldIndex = _currentIndex;
    _isJellyfinConnected = isJellyfinConnected;
    _isEmbyConnected = isEmbyConnected;
    _hasSharedRemoteHosts = hasSharedHosts;
    _isDandanConnected = isDandanConnected;
    _hasWebDAVConnections = hasWebdavConnections;
    _hasSMBConnections = hasSmbConnections;
    _hasWebDAVLibrary = hasWebdavLibrary;
    _hasSMBLibrary = hasSmbLibrary;

    // 创建新的TabController
    final newController = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: oldIndex >= _tabCount ? 0 : oldIndex);

    // 移除旧监听器并释放资源
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();

    // 更新到新的控制器
    _tabController = newController;
    _tabController.addListener(_handleTabChange);

    // 调整当前索引
    if (_currentIndex >= _tabCount) {
      _currentIndex = 0;
    }

    setState(() {
      // 触发重建以使用新的TabController
    });

    print('TabController已更新：新长度=$_tabCount, 当前索引=$_currentIndex');
  }
}

// 鼠标拖动滚动包装器
class _MouseDragScrollWrapper extends StatefulWidget {
  final ScrollController scrollController;
  final Widget child;

  const _MouseDragScrollWrapper({
    required this.scrollController,
    required this.child,
  });

  @override
  State<_MouseDragScrollWrapper> createState() =>
      _MouseDragScrollWrapperState();
}

class _MouseDragScrollWrapperState extends State<_MouseDragScrollWrapper> {
  bool _isDragging = false;
  double _lastPanPosition = 0.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // 只响应鼠标左键
        if (event.buttons == 1) {
          _isDragging = true;
          _lastPanPosition = event.position.dx;
        }
      },
      onPointerMove: (PointerMoveEvent event) {
        if (_isDragging && widget.scrollController.hasClients) {
          final double delta = _lastPanPosition - event.position.dx;
          _lastPanPosition = event.position.dx;
          widget.scrollController.jumpTo(
            (widget.scrollController.offset + delta).clamp(
              0.0,
              widget.scrollController.position.maxScrollExtent,
            ),
          );
        }
      },
      onPointerUp: (PointerUpEvent event) {
        _isDragging = false;
      },
      onPointerCancel: (PointerCancelEvent event) {
        _isDragging = false;
      },
      child: widget.child,
    );
  }
}

// 自定义Tab指示器
class _CustomTabIndicator extends Decoration {
  final double indicatorHeight;
  final Color indicatorColor;
  final double radius;

  const _CustomTabIndicator({
    required this.indicatorHeight,
    required this.indicatorColor,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _CustomPainter(this, onChanged);
  }
}

class _CustomPainter extends BoxPainter {
  final _CustomTabIndicator decoration;

  _CustomPainter(this.decoration, VoidCallback? onChanged) : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    // 将指示器绘制在TabBar的底部
    final Rect rect = Offset(
          offset.dx,
          (configuration.size!.height - decoration.indicatorHeight),
        ) &
        Size(configuration.size!.width, decoration.indicatorHeight);
    final Paint paint = Paint();
    paint.color = decoration.indicatorColor;
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}
