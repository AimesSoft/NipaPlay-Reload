library webdav_browser_page;

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/webdav_file_sorter.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_webdav_connection_dialog.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

part '../themes/cupertino/widgets/cupertino_webdav_browser_controls.dart';

/// WebDAV 文件浏览器页面
/// 用于快捷 Tab，提供快速浏览和播放 WebDAV 视频的功能
class WebDAVBrowserPage extends StatefulWidget {
  const WebDAVBrowserPage({super.key});

  @override
  State<WebDAVBrowserPage> createState() => _WebDAVBrowserPageState();
}

class _WebDAVBrowserPageState extends State<WebDAVBrowserPage> {
  // 静态正则表达式常量，用于提取集数（避免重复创建）
  static final _seasonEpisodeRegex = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');
  static final _chineseEpisodeRegex = RegExp(r'第(\d{1,3})[话集]');
  static final _epNumberRegex = RegExp(r'[Ee][Pp]?(\d{1,3})');
  static final _bracketNumberRegex = RegExp(r'[\[【](\d{1,3})[\]】]');
  static final _delimiterNumberRegex = RegExp(r'[-_](\d{1,3})[-_\.\[]');

  // 当前选中的服务器连接
  WebDAVConnection? _currentConnection;
  // 当前路径
  String _currentPath = '/';
  // 路径历史，用于返回
  final List<String> _pathHistory = [];
  // 当前目录内容
  List<WebDAVFile> _currentFiles = [];
  // 加载状态
  bool _isLoading = false;
  // 是否正在初始化
  bool _isInitializing = true;

  // 搜索相关状态
  bool _isSearchMode = false;
  bool _isSearching = false;
  bool _stopSearchRequested = false;
  String _searchKeyword = '';
  List<WebDAVSearchResult> _searchResults = [];
  int _searchedCount = 0;
  int _foundCount = 0;
  final TextEditingController _searchController = TextEditingController();

  // UI 更新节流
  DateTime? _lastUIUpdate;
  static const int _uiUpdateThrottleMs = 100;
  bool _maxResultsReached = false;

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  @override
  void dispose() {
    _stopSearchRequested = true;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializePage() async {
    // 初始化 WebDAV 服务
    await WebDAVService.instance.initialize();

    if (!mounted) return;

    // 加载快捷设置
    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
    await provider.loadSettings();

    if (!mounted) return;

    // 设置默认服务器
    if (provider.hasValidDefaultServer) {
      _currentConnection = provider.defaultConnection;
      _currentPath = provider.defaultDirectory;
    } else if (WebDAVService.instance.connections.isNotEmpty) {
      // 如果没有设置默认服务器，使用第一个可用的连接
      _currentConnection = WebDAVService.instance.connections.first;
      _currentPath = '/';
    }

    setState(() {
      _isInitializing = false;
    });

    // 加载目录内容
    if (_currentConnection != null) {
      await _loadDirectory();
    }
  }

  Future<void> _loadDirectory({bool isRecursive = false}) async {
    if (_currentConnection == null) return;
    // 只在非递归调用时检查 _isLoading，避免重入
    if (!isRecursive && _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final files = await WebDAVService.instance.listDirectory(
        _currentConnection!,
        _currentPath,
      );

      // 应用排序预设
      final provider =
          Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
      WebDAVFileSorter.sort(files, provider.sortPreset);

      // 检查是否需要自动进入 Season 文件夹
      if (provider.autoEnterSeasonFolder) {
        final folderNames =
            files.where((f) => f.isDirectory).map((f) => f.name).toList();
        final matchFolder = provider.findMatchingSeasonFolder(folderNames);

        if (matchFolder != null && mounted) {
          // 找到匹配的文件夹，自动进入
          final matchPath = _currentPath.endsWith('/')
              ? '$_currentPath$matchFolder'
              : '$_currentPath/$matchFolder';
          setState(() {
            _currentPath = matchPath;
          });
          // 递归加载（标记为递归调用）
          await _loadDirectory(isRecursive: true);
          return;
        }
      }

      if (mounted) {
        setState(() {
          _currentFiles = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        BlurSnackBar.show(context, '加载目录失败: $e');
      }
    }
  }

  void _navigateToDirectory(String path) {
    if (_currentPath != '/') {
      _pathHistory.add(_currentPath);
    }
    setState(() {
      _currentPath = path;
    });
    _loadDirectory();
  }

  void _navigateBack() {
    if (_pathHistory.isNotEmpty) {
      setState(() {
        _currentPath = _pathHistory.removeLast();
      });
      _loadDirectory();
    } else if (_currentPath != '/') {
      // 返回上一级目录（而不是直接跳到根目录）
      final segments =
          _currentPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        final parentPath = segments.isEmpty ? '/' : '/' + segments.join('/');
        setState(() {
          _currentPath = parentPath;
        });
        _loadDirectory();
      }
    }
  }

  /// 是否可以返回上一级
  bool get _canNavigateBack => _currentPath != '/';

  void _playVideo(WebDAVFile file) async {
    if (_currentConnection == null) return;

    final videoUrl = WebDAVService.instance.getFileUrl(
      _currentConnection!,
      file.path,
    );

    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
    int? quickMatchEpisodeId;
    int? quickMatchAnimeId;
    String? quickMatchAnimeTitle;

    if (provider.bgmIdQuickMatch) {
      // 使用用户自定义正则从完整 URL 中匹配 bgmid
      try {
        final regex = RegExp(provider.bgmIdMatchPattern);
        final bgmidMatch = regex.firstMatch(videoUrl);

        if (bgmidMatch != null && bgmidMatch.groupCount >= 1) {
          // 取最后一个捕获组的数字（兼容不同正则格式）
          final lastGroup = bgmidMatch.group(bgmidMatch.groupCount);
          final bgmid = int.tryParse(lastGroup ?? '');

          if (bgmid != null) {
            final result = await DandanplayService.getBangumiByBgmId(bgmid);

            if (result != null && result['bangumi'] != null) {
              final bangumi = result['bangumi'] as Map<String, dynamic>;
              final episodes = bangumi['episodes'] as List<dynamic>?;

              quickMatchAnimeId = bangumi['animeId'] as int?;
              quickMatchAnimeTitle = bangumi['animeTitle'] as String?;

              final episodeNumber = _extractEpisodeNumber(file.name);

              if (episodes != null && episodeNumber != null) {
                for (final ep in episodes) {
                  final epNum =
                      int.tryParse(ep['episodeNumber']?.toString() ?? '');
                  if (epNum == episodeNumber) {
                    quickMatchEpisodeId = ep['episodeId'] as int?;
                    break;
                  }
                }
              }

              debugPrint(
                  '[WebDAV] 快速匹配结果: bgmid=$bgmid, episodeNumber=$episodeNumber, episodeId=$quickMatchEpisodeId');
            }
          }
        }
      } catch (e) {
        // 正则无效或匹配失败，静默回退原有流程
        debugPrint('[WebDAV] 快速匹配失败（使用规则: ${provider.bgmIdMatchPattern}）: $e');
      }
    }

    // ========== tmdbId 快速匹配（bgmid 未匹配成功时尝试） ==========
    if (quickMatchEpisodeId == null && provider.tmdbIdQuickMatch) {
      try {
        final tmdbRegex = RegExp(provider.tmdbIdMatchPattern);
        final tmdbMatch = tmdbRegex.firstMatch(videoUrl);

        if (tmdbMatch != null && tmdbMatch.groupCount >= 1) {
          final lastGroup = tmdbMatch.group(tmdbMatch.groupCount);
          final tmdbId = int.tryParse(lastGroup ?? '');

          if (tmdbId != null) {
            final seasonNumber = _extractSeasonNumber(file.name);
            final result = await DandanplayService.getBangumiByTmdbId(tmdbId,
                seasonNumber: seasonNumber);

            if (result != null && result['bangumi'] != null) {
              final bangumi = result['bangumi'] as Map<String, dynamic>;
              final episodes = bangumi['episodes'] as List<dynamic>?;

              quickMatchAnimeId = bangumi['animeId'] as int?;
              quickMatchAnimeTitle = bangumi['animeTitle'] as String?;

              final episodeNumber = _extractEpisodeNumber(file.name);
              int targetNumber = episodeNumber ?? 0;

              if (episodes != null && episodeNumber != null) {
                // 剧集漂移修正（实验功能）
                if (provider.episodeOffsetEnabled) {
                  final mainEps = episodes.where((ep) {
                    final eid = ep['episodeId']?.toString() ?? '';
                    return eid.length >= 4 && eid[eid.length - 4] == '0';
                  }).toList();

                  if (mainEps.isNotEmpty) {
                    int minNum = 99999;
                    for (final ep in mainEps) {
                      final n =
                          int.tryParse(ep['episodeNumber']?.toString() ?? '');
                      if (n != null && n > 0 && n < minNum) {
                        minNum = n;
                      }
                    }
                    if (minNum != 99999) {
                      final offset = minNum - 1;
                      targetNumber = episodeNumber + offset;
                      debugPrint(
                          '[WebDAV] 剧集偏移: min=$minNum, offset=$offset, target=$targetNumber');
                    }
                  }
                }

                for (final ep in episodes) {
                  final epNum =
                      int.tryParse(ep['episodeNumber']?.toString() ?? '');
                  if (epNum == targetNumber) {
                    quickMatchEpisodeId = ep['episodeId'] as int?;
                    break;
                  }
                }
              }

              debugPrint(
                  '[WebDAV] tmdbId 快速匹配结果: tmdbId=$tmdbId, episodeNumber=$episodeNumber, targetNumber=$targetNumber, episodeId=$quickMatchEpisodeId');
            }
          }
        }
      } catch (e) {
        debugPrint(
            '[WebDAV] tmdbId 快速匹配失败（使用规则: ${provider.tmdbIdMatchPattern}）: $e');
      }
    }

    // 创建观看历史项用于播放
    final historyItem = WatchHistoryItem(
      animeName:
          quickMatchAnimeTitle ?? file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      episodeTitle: file.name,
      filePath: videoUrl,
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
      episodeId: quickMatchEpisodeId,
      animeId: quickMatchAnimeId,
    );

    // 使用 PlaybackService 播放视频
    final playableItem = PlayableItem(
      videoPath: videoUrl,
      title:
          quickMatchAnimeTitle ?? file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      subtitle: file.name,
      historyItem: historyItem,
    );

    PlaybackService().play(playableItem);
  }

  /// 从文件名中提取集数
  /// 支持多种格式：S01E12、第12集、EP12、[12]、_12_ 等
  int? _extractEpisodeNumber(String fileName) {
    // 尝试匹配 S01E12 格式
    final seasonEpisodeMatch = _seasonEpisodeRegex.firstMatch(fileName);
    if (seasonEpisodeMatch != null) {
      return int.tryParse(seasonEpisodeMatch.group(2)!);
    }

    // 尝试匹配 第N集/第N话 格式
    final chineseMatch = _chineseEpisodeRegex.firstMatch(fileName);
    if (chineseMatch != null) {
      return int.tryParse(chineseMatch.group(1)!);
    }

    // 尝试匹配 EP12 / E12 格式
    final epMatch = _epNumberRegex.firstMatch(fileName);
    if (epMatch != null) {
      return int.tryParse(epMatch.group(1)!);
    }

    // 尝试匹配 [12] 或 【12】 格式
    final bracketMatch = _bracketNumberRegex.firstMatch(fileName);
    if (bracketMatch != null) {
      return int.tryParse(bracketMatch.group(1)!);
    }

    // 尝试匹配 -12- 或 _12_ 格式（在分隔符之间的数字）
    final delimiterMatch = _delimiterNumberRegex.firstMatch(fileName);
    if (delimiterMatch != null) {
      return int.tryParse(delimiterMatch.group(1)!);
    }

    return null;
  }

  /// 从文件名中提取 Season 数字 (S01 → 1, S2 → 2)
  int? _extractSeasonNumber(String fileName) {
    final match = _seasonEpisodeRegex.firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  Future<void> _showServerSelector() async {
    final connections = WebDAVService.instance.connections;
    if (connections.isEmpty) {
      BlurSnackBar.show(context, '没有配置任何 WebDAV 服务器');
      return;
    }

    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      await _showCupertinoServerActions();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ServerSelectorSheet(
        connections: connections,
        currentConnection: _currentConnection,
        onSelected: (connection) {
          setState(() {
            _currentConnection = connection;
            _currentPath = '/';
            _pathHistory.clear();
          });
          _loadDirectory();
        },
      ),
    );
  }

  /// 显示添加 WebDAV 服务器对话框
  Future<void> _showAddServerDialog() async {
    final connectionsBefore = WebDAVService.instance.connections.length;

    final result = AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone
        ? await CupertinoWebDAVConnectionDialog.show(context)
        : await WebDAVConnectionDialog.show(context);

    if (result == true && mounted) {
      // 添加成功
      final connectionsAfter = WebDAVService.instance.connections;

      if (connectionsAfter.isNotEmpty) {
        // 获取新添加的服务器（最后一个）
        final newConnection = connectionsAfter.last;

        // 如果添加前没有服务器，添加后只有一个服务器，则自动设置为默认服务器
        if (connectionsBefore == 0 && connectionsAfter.length == 1) {
          final provider =
              Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
          await provider.setDefaultServerName(newConnection.name);
          BlurSnackBar.show(
              context, '已将 ${newConnection.name} 设置为默认 WebDAV 服务器');
        }

        // 自动选择新添加的服务器并加载目录
        setState(() {
          _currentConnection = newConnection;
          _currentPath = '/';
          _pathHistory.clear();
        });
        await _loadDirectory();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return _buildCupertinoWebDavPage();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);
    final cardColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final accentColor = AppAccentColors.current;
    final useLargeScreen = NipaplayLargeScreenModeScope.isActiveOf(context);

    if (_isInitializing) {
      if (useLargeScreen) {
        return const NipaplayLargeScreenPageScaffold(
          title: 'WebDAV',
          subtitle: '正在连接远程文件库',
          icon: Icons.cloud_queue_rounded,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: AppAccentColors.current),
        ),
      );
    }

    // 没有配置任何 WebDAV 服务器
    if (_currentConnection == null) {
      if (useLargeScreen) {
        return NipaplayLargeScreenPageScaffold(
          title: 'WebDAV',
          subtitle: '远程文件浏览器',
          icon: Icons.cloud_off_rounded,
          child: NipaplayLargeScreenEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '没有配置 WebDAV 服务器',
            subtitle: '添加服务器后即可浏览远程目录并直接播放视频。',
            action: NipaplayLargeScreenActionButton(
              icon: Icons.add_rounded,
              label: '添加服务器',
              onPressed: _showAddServerDialog,
              autofocus: true,
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: secondaryTextColor,
              ),
              SizedBox(height: 16),
              Text(
                '没有配置 WebDAV 服务器',
                style: TextStyle(
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '请先在设置中添加 WebDAV 服务器',
                style: TextStyle(
                  fontSize: 14,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showAddServerDialog(),
                icon: Icon(Icons.add),
                label: const Text('添加服务器'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (useLargeScreen) {
      return PopScope(
        canPop: !_canNavigateBack,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _canNavigateBack) {
            _navigateBack();
          }
        },
        child: _buildLargeScreenWebDavPage(
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
          accentColor: accentColor,
        ),
      );
    }

    return PopScope(
      canPop: !_canNavigateBack, // 如果可以返回上一级，则阻止系统返回
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _canNavigateBack) {
          _navigateBack();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            // 顶部导航栏
            _buildNavigationBar(
              context: context,
              cardColor: cardColor,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
            // 文件列表或搜索结果
            Expanded(
              child: _isSearchMode
                  ? _buildSearchResults(
                      cardColor: cardColor,
                      textColor: textColor,
                      secondaryTextColor: secondaryTextColor,
                      accentColor: accentColor,
                    )
                  : _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                              color: AppAccentColors.current),
                        )
                      : _currentFiles.isEmpty
                          ? Center(
                              child: Text(
                                '当前目录为空',
                                style: TextStyle(color: secondaryTextColor),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _currentFiles.length,
                              itemBuilder: (context, index) {
                                final file = _currentFiles[index];
                                return _buildFileItem(
                                  file: file,
                                  cardColor: cardColor,
                                  textColor: textColor,
                                  secondaryTextColor: secondaryTextColor,
                                  accentColor: accentColor,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeScreenWebDavPage({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final provider = Provider.of<WebDAVQuickAccessProvider>(context);
    final subtitle = [
      _currentConnection?.name ?? '未选择服务器',
      if (_currentPath.trim().isNotEmpty) _currentPath,
    ].join(' / ');

    return NipaplayLargeScreenPageScaffold(
      title: 'WebDAV',
      subtitle: subtitle,
      icon: Icons.cloud_queue_rounded,
      actions: [
        if (_canNavigateBack)
          NipaplayLargeScreenActionButton(
            icon: Icons.arrow_back_rounded,
            label: '上一级',
            onPressed: _navigateBack,
          ),
        NipaplayLargeScreenActionButton(
          icon: Icons.dns_rounded,
          label: '服务器',
          onPressed: _showServerSelector,
        ),
        if (provider.enableSearch)
          NipaplayLargeScreenActionButton(
            icon: _isSearchMode ? Icons.close_rounded : Icons.search_rounded,
            label: _isSearchMode ? '退出搜索' : '搜索',
            onPressed: () {
              setState(() {
                if (_isSearchMode) {
                  _isSearchMode = false;
                  _stopSearchRequested = true;
                  _searchResults = [];
                  _searchController.clear();
                  _searchKeyword = '';
                } else {
                  _isSearchMode = true;
                }
              });
            },
          ),
        NipaplayLargeScreenActionButton(
          icon: Icons.add_rounded,
          label: '添加服务器',
          onPressed: _showAddServerDialog,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isSearchMode) ...[
            _buildLargeScreenSearchBar(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
            const SizedBox(height: 18),
          ] else if (provider.showPathBreadcrumb) ...[
            _buildLargeScreenBreadcrumb(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
            const SizedBox(height: 18),
          ],
          Expanded(
            child: _isSearchMode
                ? _buildLargeScreenSearchResults(
                    textColor: textColor,
                    secondaryTextColor: secondaryTextColor,
                    accentColor: accentColor,
                  )
                : _buildLargeScreenFileGrid(
                    textColor: textColor,
                    secondaryTextColor: secondaryTextColor,
                    accentColor: accentColor,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenSearchBar({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: true);
    return NipaplayLargeScreenPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: NipaplayLargeScreenTextInput(
              controller: _searchController,
              hintText: '搜索当前目录下的视频或文件夹',
              onChanged: (value) {
                setState(() {
                  _searchKeyword = value;
                });
              },
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _startSearch();
                }
              },
              suffix: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon:
                          Icon(Icons.clear_rounded, color: secondaryTextColor),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchKeyword = '';
                          _searchResults = [];
                        });
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          NipaplayLargeScreenActionButton(
            icon: _isSearching
                ? Icons.hourglass_top_rounded
                : Icons.search_rounded,
            label: _isSearching ? '搜索中' : '开始搜索',
            onPressed: _isSearching || _searchController.text.trim().isEmpty
                ? null
                : _startSearch,
            autofocus: true,
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              '${provider.searchScope.displayName} ${provider.searchDepthLimit}层 / ${provider.searchTargets.map((t) => t.displayName).join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenBreadcrumb({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final segments =
        _currentPath.split('/').where((segment) => segment.isNotEmpty).toList();
    final chips = <Widget>[
      _LargeScreenPathChip(
        label: '根目录',
        selected: segments.isEmpty,
        onPressed: () => _navigateToPath('/'),
      ),
    ];
    for (var index = 0; index < segments.length; index++) {
      final path = '/' + segments.sublist(0, index + 1).join('/');
      chips.add(_LargeScreenPathChip(
        label: segments[index],
        selected: index == segments.length - 1,
        onPressed:
            index == segments.length - 1 ? null : () => _navigateToPath(path),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips) ...[
            chip,
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildLargeScreenFileGrid({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppAccentColors.current),
      );
    }
    if (_currentFiles.isEmpty) {
      return const NipaplayLargeScreenEmptyState(
        icon: Icons.folder_open_rounded,
        title: '当前目录为空',
        subtitle: '可以返回上一级目录，或切换服务器继续浏览。',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 170,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: _currentFiles.length,
      itemBuilder: (context, index) {
        final file = _currentFiles[index];
        return _buildLargeScreenFileCard(
          file: file,
          textColor: textColor,
          secondaryTextColor: secondaryTextColor,
          accentColor: accentColor,
          autofocus: index == 0,
        );
      },
    );
  }

  Widget _buildLargeScreenFileCard({
    required WebDAVFile file,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
    required bool autofocus,
  }) {
    final isDirectory = file.isDirectory;
    String? seasonEpisode;
    if (!isDirectory) {
      final match = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})').firstMatch(file.name);
      if (match != null) {
        seasonEpisode = 'S${match.group(1)}E${match.group(2)}';
      }
    }

    final videoUrl = _currentConnection != null
        ? WebDAVService.instance.getFileUrl(_currentConnection!, file.path)
        : null;
    final historyProvider =
        Provider.of<WatchHistoryProvider>(context, listen: false);
    WatchHistoryItem? historyItem;
    if (videoUrl != null) {
      for (final item in historyProvider.history) {
        if (item.filePath == videoUrl) {
          historyItem = item;
          break;
        }
      }
    }
    final hasProgress = historyItem != null &&
        historyItem.duration > 0 &&
        historyItem.watchProgress > 0.01 &&
        historyItem.watchProgress < 0.95;

    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: isDirectory
          ? () => _navigateToDirectory(file.path)
          : () => _playVideo(file),
      borderRadius: BorderRadius.circular(8),
      focusScale: 1.035,
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: Colors.white.withValues(alpha: 0.08),
        idleBackgroundLight: Colors.white.withValues(alpha: 0.78),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDirectory
                    ? Icons.folder_rounded
                    : Icons.movie_creation_outlined,
                color: isDirectory ? Colors.amberAccent : accentColor,
                size: 34,
              ),
              const Spacer(),
              Icon(
                isDirectory
                    ? Icons.chevron_right_rounded
                    : Icons.play_arrow_rounded,
                color: textColor.withValues(alpha: 0.76),
                size: 28,
              ),
            ],
          ),
          const Spacer(),
          Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  isDirectory
                      ? '文件夹'
                      : (file.size != null && file.size! > 0
                          ? _formatFileSize(file.size!)
                          : '视频文件'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (seasonEpisode != null)
                Text(
                  seasonEpisode,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: historyItem.watchProgress,
                minHeight: 4,
                color: accentColor,
                backgroundColor: textColor.withValues(alpha: 0.14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLargeScreenSearchResults({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    if (_isSearching) {
      return Column(
        children: [
          NipaplayLargeScreenPanel(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '搜索中... 已扫描 $_searchedCount 个目录，找到 $_foundCount 个结果',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                NipaplayLargeScreenActionButton(
                  icon: Icons.stop_rounded,
                  label: '停止',
                  compact: true,
                  onPressed: () {
                    setState(() {
                      _stopSearchRequested = true;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _searchResults.isEmpty
                ? NipaplayLargeScreenEmptyState(
                    icon: Icons.search_rounded,
                    title: '正在搜索',
                    subtitle: '找到的结果会立即出现在这里。',
                  )
                : _buildLargeScreenSearchResultGrid(
                    textColor: textColor,
                    secondaryTextColor: secondaryTextColor,
                    accentColor: accentColor,
                  ),
          ),
        ],
      );
    }
    if (_searchResults.isEmpty) {
      return NipaplayLargeScreenEmptyState(
        icon: _searchKeyword.isEmpty
            ? Icons.search_rounded
            : Icons.search_off_rounded,
        title: _searchKeyword.isEmpty ? '输入关键词搜索文件' : '未找到匹配的文件',
        subtitle: _searchKeyword.isEmpty
            ? '支持按文件名、目录名和视频扩展名搜索。'
            : '关键词：$_searchKeyword',
      );
    }
    return _buildLargeScreenSearchResultGrid(
      textColor: textColor,
      secondaryTextColor: secondaryTextColor,
      accentColor: accentColor,
    );
  }

  Widget _buildLargeScreenSearchResultGrid({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return NipaplayLargeScreenFocusableAction(
          autofocus: index == 0,
          onActivate: result.file.isDirectory
              ? () {
                  final parentPath = result.file.path;
                  _navigateToPathFromSearch(parentPath);
                }
              : () => _playSearchResult(result),
          borderRadius: BorderRadius.circular(8),
          focusScale: 1.035,
          padding: const EdgeInsets.all(18),
          style: NipaplayLargeScreenFocusableStyle(
            idleBackgroundDark: Colors.white.withValues(alpha: 0.08),
            idleBackgroundLight: Colors.white.withValues(alpha: 0.78),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.file.isDirectory
                    ? Icons.folder_rounded
                    : Icons.movie_creation_outlined,
                color:
                    result.file.isDirectory ? Colors.amberAccent : accentColor,
                size: 34,
              ),
              const Spacer(),
              Text(
                result.file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                result.relativePath.isEmpty ? '/' : result.relativePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationBar({
    required BuildContext context,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        color: cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务器选择和返回按钮
          Row(
            children: [
              // 返回按钮
              if (_currentPath != '/' || _pathHistory.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.arrow_back),
                  color: textColor,
                  onPressed: _navigateBack,
                ),
              // 服务器选择
              Expanded(
                child: InkWell(
                  onTap: _showServerSelector,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: secondaryTextColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_outlined,
                          size: 20,
                          color: accentColor,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentConnection?.name ?? '选择服务器',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 20,
                          color: secondaryTextColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 搜索按钮（根据设置显示）
              if (Provider.of<WebDAVQuickAccessProvider>(context, listen: true)
                  .enableSearch)
                IconButton(
                  icon: Icon(
                    _isSearchMode ? Icons.close : Icons.search,
                    color: _isSearchMode ? accentColor : textColor,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isSearchMode) {
                        // 退出搜索模式
                        _isSearchMode = false;
                        _stopSearchRequested = true;
                        _searchResults = [];
                        _searchController.clear();
                        _searchKeyword = '';
                      } else {
                        // 进入搜索模式
                        _isSearchMode = true;
                      }
                    });
                  },
                ),
            ],
          ),
          // 搜索输入框（搜索模式下显示）
          if (_isSearchMode) ...[
            SizedBox(height: 12),
            _buildSearchInput(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
          ],
          // 路径面包屑导航（根据设置显示）
          if (Provider.of<WebDAVQuickAccessProvider>(context)
              .showPathBreadcrumb) ...[
            SizedBox(height: 12),
            _buildPathBreadcrumb(
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPathBreadcrumb({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    // 将路径分割成片段
    final segments =
        _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final hasSegments = segments.isNotEmpty;

    return SizedBox(
      height: 32,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // 根目录
            InkWell(
              onTap: () => _navigateToPath('/'),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '根目录',
                  style: TextStyle(
                    color: !hasSegments ? accentColor : secondaryTextColor,
                    fontSize: 13,
                    fontWeight:
                        !hasSegments ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
            // 路径片段
            ...List.generate(segments.length, (index) {
              final segment = segments[index];
              final isLast = index == segments.length - 1;
              final path = '/' + segments.sublist(0, index + 1).join('/');

              return Row(
                children: [
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: secondaryTextColor,
                  ),
                  InkWell(
                    onTap: isLast ? null : () => _navigateToPath(path),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Text(
                        segment,
                        style: TextStyle(
                          color: isLast ? accentColor : secondaryTextColor,
                          fontSize: 13,
                          fontWeight:
                              isLast ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _navigateToPath(String path) {
    // 清空历史记录，直接跳转到指定路径
    setState(() {
      _pathHistory.clear();
      _currentPath = path;
    });
    _loadDirectory();
  }

  Widget _buildFileItem({
    required WebDAVFile file,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final isDirectory = file.isDirectory;

    // 提取 SxxExx 季集信息
    String? seasonEpisode;
    if (!isDirectory) {
      final match = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,2})').firstMatch(file.name);
      if (match != null) {
        seasonEpisode = 'S${match.group(1)}E${match.group(2)}';
      }
    }

    // 查找播放历史
    final videoUrl = _currentConnection != null
        ? WebDAVService.instance.getFileUrl(_currentConnection!, file.path)
        : null;
    final historyProvider =
        Provider.of<WatchHistoryProvider>(context, listen: false);
    WatchHistoryItem? historyItem;
    if (videoUrl != null) {
      try {
        historyItem = historyProvider.history.firstWhere(
          (item) => item.filePath == videoUrl,
        );
      } catch (_) {
        historyItem = null;
      }
    }
    final hasProgress = historyItem != null &&
        historyItem.duration > 0 &&
        historyItem.watchProgress > 0.01 &&
        historyItem.watchProgress < 0.95;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: secondaryTextColor.withOpacity(0.1),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isDirectory
            ? () => _navigateToDirectory(file.path)
            : () => _playVideo(file),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isDirectory ? Icons.folder_outlined : Icons.video_file_outlined,
                color: isDirectory ? Colors.amber : accentColor,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文件名 - 最多显示两行
                    Text(
                      file.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    // 文件大小和播放进度
                    Row(
                      children: [
                        if (!isDirectory &&
                            file.size != null &&
                            file.size! > 0) ...[
                          Text(
                            _formatFileSize(file.size!),
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                          if (seasonEpisode != null) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                seasonEpisode,
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          if (hasProgress) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${(historyItem.watchProgress * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ] else if (!isDirectory && seasonEpisode != null) ...[
                          Text(
                            seasonEpisode,
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else if (isDirectory) ...[
                          Text(
                            '文件夹',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 播放进度条
                    if (hasProgress) ...[
                      SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: historyItem.watchProgress,
                          backgroundColor: secondaryTextColor.withOpacity(0.2),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(accentColor),
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8),
              if (!isDirectory)
                IconButton(
                  icon: Icon(Icons.play_circle_outline),
                  color: accentColor,
                  onPressed: () => _playVideo(file),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: secondaryTextColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 搜索功能相关方法 ====================

  Widget _buildSearchInput({
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 搜索输入框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: '搜索文件...',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: secondaryTextColor.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: secondaryTextColor.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: secondaryTextColor),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchKeyword = '';
                              _searchResults = [];
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchKeyword = value;
                  });
                },
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _startSearch();
                  }
                },
              ),
            ),
            SizedBox(width: 8),
            // 搜索按钮
            ElevatedButton(
              onPressed: _isSearching || _searchController.text.isEmpty
                  ? null
                  : _startSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(_isSearching ? '搜索中' : '搜索'),
            ),
          ],
        ),
        SizedBox(height: 8),
        // 当前设置摘要
        Text(
          '${provider.searchScope.displayName}(${provider.searchDepthLimit}层) | ${provider.searchTargets.map((t) => t.displayName).join(',')} | 间隔${provider.searchRequestInterval}ms',
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults({
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    // 搜索进度显示
    if (_isSearching) {
      return Column(
        children: [
          // 进度指示器
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '搜索中... 已扫描 $_searchedCount 个目录，找到 $_foundCount 个结果',
                        style: TextStyle(color: textColor, fontSize: 14),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _stopSearchRequested = true;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('停止'),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(
                  backgroundColor: secondaryTextColor.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ],
            ),
          ),
          // 已找到的结果
          Expanded(
            child: _searchResults.isEmpty
                ? Center(
                    child: Text(
                      '正在搜索...',
                      style: TextStyle(color: secondaryTextColor),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      return _buildSearchResultItem(
                        result: result,
                        cardColor: cardColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                        accentColor: accentColor,
                      );
                    },
                  ),
          ),
        ],
      );
    }

    // 搜索完成后的结果列表
    if (_searchResults.isEmpty) {
      if (_searchKeyword.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64, color: secondaryTextColor),
              SizedBox(height: 16),
              Text(
                '输入关键词搜索文件',
                style: TextStyle(color: secondaryTextColor, fontSize: 16),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: secondaryTextColor),
            SizedBox(height: 16),
            Text(
              '未找到匹配的文件',
              style: TextStyle(color: secondaryTextColor, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              '关键词: $_searchKeyword',
              style: TextStyle(
                  color: secondaryTextColor.withOpacity(0.7), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 结果统计
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: accentColor, size: 20),
              SizedBox(width: 8),
              Text(
                '找到 ${_searchResults.length} 个结果',
                style:
                    TextStyle(color: accentColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        // 结果列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _searchResults.length,
            itemBuilder: (context, index) {
              final result = _searchResults[index];
              return _buildSearchResultItem(
                result: result,
                cardColor: cardColor,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
                accentColor: accentColor,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultItem({
    required WebDAVSearchResult result,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color accentColor,
  }) {
    final isDirectory = result.file.isDirectory;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: secondaryTextColor.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件名
            Row(
              children: [
                Icon(
                  isDirectory
                      ? Icons.folder_outlined
                      : Icons.video_file_outlined,
                  color: isDirectory ? Colors.amber : accentColor,
                  size: 24,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.file.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            // 路径
            Text(
              result.relativePath.isEmpty ? '/' : result.relativePath,
              style: TextStyle(
                color: secondaryTextColor,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 8),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 跳转到目录按钮
                TextButton.icon(
                  icon: Icon(Icons.folder_open,
                      size: 18, color: secondaryTextColor),
                  label:
                      Text('跳转', style: TextStyle(color: secondaryTextColor)),
                  onPressed: () {
                    // 获取父目录路径
                    final parentPath = isDirectory
                        ? result.file.path
                        : result.file.path.substring(
                            0, result.file.path.lastIndexOf('/') + 1);
                    _navigateToPathFromSearch(parentPath);
                  },
                ),
                SizedBox(width: 8),
                // 播放按钮（仅文件）
                if (!isDirectory)
                  ElevatedButton.icon(
                    icon: Icon(Icons.play_arrow, size: 18),
                    label: const Text('播放'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _playSearchResult(result),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startSearch() async {
    if (_currentConnection == null || _searchController.text.isEmpty) return;
    if (_isSearching) return; // 防止 onSubmitted 重复触发

    final provider =
        Provider.of<WebDAVQuickAccessProvider>(context, listen: false);
    final keyword = _searchController.text.trim();
    final maxResults = provider.searchMaxResults;

    setState(() {
      _isSearching = true;
      _stopSearchRequested = false;
      _searchKeyword = keyword;
      _searchResults = [];
      _searchedCount = 0;
      _foundCount = 0;
      _maxResultsReached = false;
      _lastUIUpdate = null;
    });

    try {
      final searchTargets = provider.searchTargets.map((t) => t.value).toSet();

      await WebDAVService.instance.searchFiles(
        connection: _currentConnection!,
        keyword: keyword,
        startPath: _currentPath,
        scope: provider.searchScope.value,
        depthLimit: provider.searchDepthLimit,
        searchTargets: searchTargets,
        timeoutSeconds: provider.searchTimeout.seconds,
        requestIntervalMs: provider.searchRequestInterval,
        onProgress: (searched, found) {
          if (mounted && !_stopSearchRequested && !_maxResultsReached) {
            // 节流 UI 更新
            final now = DateTime.now();
            if (_lastUIUpdate == null ||
                now.difference(_lastUIUpdate!).inMilliseconds >=
                    _uiUpdateThrottleMs) {
              _lastUIUpdate = now;
              setState(() {
                _searchedCount = searched;
                _foundCount = found;
              });
            }
          }
        },
        onResultFound: (result) {
          if (mounted && !_stopSearchRequested && !_maxResultsReached) {
            if (_searchResults.length < maxResults) {
              _searchResults.add(result);
              // 后检查：刚达到上限时立即标记停止，不依赖下一轮回调
              if (_searchResults.length >= maxResults) {
                _maxResultsReached = true;
                setState(() {
                  _isSearching = false;
                });
                return;
              }
              // 节流 UI 更新
              final now = DateTime.now();
              if (_lastUIUpdate == null ||
                  now.difference(_lastUIUpdate!).inMilliseconds >=
                      _uiUpdateThrottleMs) {
                _lastUIUpdate = now;
                setState(() {});
              }
            }
          }
        },
        onStopRequested: () => _stopSearchRequested || _maxResultsReached,
      );

      if (mounted && !_maxResultsReached) {
        setState(() {
          _isSearching = false;
        });
      }

      // 显示达到上限提示
      if (mounted && _maxResultsReached) {
        BlurSnackBar.show(context, '已达到最大结果数 ($maxResults)，搜索已停止');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        BlurSnackBar.show(context, '搜索失败: $e');
      }
    }
  }

  void _navigateToPathFromSearch(String path) {
    setState(() {
      _isSearchMode = false;
      _searchResults = [];
      _searchController.clear();
      _searchKeyword = '';
      _currentPath = path;
      _pathHistory.clear();
    });
    _loadDirectory();
  }

  void _playSearchResult(WebDAVSearchResult result) async {
    if (_currentConnection == null) return;

    final videoUrl = WebDAVService.instance.getFileUrl(
      _currentConnection!,
      result.file.path,
    );

    final historyItem = WatchHistoryItem(
      animeName: result.file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      episodeTitle: result.file.name,
      filePath: videoUrl,
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
    );

    final playableItem = PlayableItem(
      videoPath: videoUrl,
      title: result.file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
      subtitle: result.file.name,
      historyItem: historyItem,
    );

    PlaybackService().play(playableItem);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 服务器选择底部弹窗
class _ServerSelectorSheet extends StatelessWidget {
  final List<WebDAVConnection> connections;
  final WebDAVConnection? currentConnection;
  final ValueChanged<WebDAVConnection> onSelected;

  const _ServerSelectorSheet({
    required this.connections,
    this.currentConnection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final accentColor = AppAccentColors.current;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: secondaryTextColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '选择 WebDAV 服务器',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            const Divider(height: 1),
            ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final connection = connections[index];
                final isSelected = connection.name == currentConnection?.name;

                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.cloud : Icons.cloud_outlined,
                    color: isSelected ? accentColor : secondaryTextColor,
                  ),
                  title: Text(
                    connection.name,
                    style: TextStyle(
                      color: textColor,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    connection.url,
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: accentColor)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(connection);
                  },
                );
              },
            ),
            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}

class _LargeScreenPathChip extends StatelessWidget {
  const _LargeScreenPathChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF161922);
    return NipaplayLargeScreenFocusableAction(
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? AppAccentColors.current.withValues(alpha: 0.26)
            : Colors.white.withValues(alpha: 0.08),
        idleBackgroundLight: selected
            ? AppAccentColors.current.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.78),
        contentColorDark: selected ? Colors.white : textColor,
        contentColorLight: selected ? Colors.black87 : textColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!selected) ...[
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: textColor.withValues(alpha: 0.50),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
