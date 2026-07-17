import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/src/rust/api/media_metadata.dart' as rust_metadata;
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// WebDAV 搜索范围
enum WebDAVSearchScope {
  currentDirectory('current_directory', '仅当前目录', '只搜索当前显示的目录'),
  currentWithDepth('current_with_depth', '当前目录 + 子目录', '向下遍历指定层级'),
  global('global', '全局搜索', '从根目录开始搜索所有文件');

  final String value;
  final String displayName;
  final String description;
  const WebDAVSearchScope(this.value, this.displayName, this.description);

  static WebDAVSearchScope fromValue(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => WebDAVSearchScope.currentWithDepth,
    );
  }
}

/// WebDAV 搜索目标类型（支持多选）
enum WebDAVSearchTarget {
  folder('folder', '文件夹'),
  video('video', '视频文件');

  final String value;
  final String displayName;
  const WebDAVSearchTarget(this.value, this.displayName);

  static WebDAVSearchTarget fromValue(String? value) {
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => WebDAVSearchTarget.video,
    );
  }

  /// 获取默认选中的搜索目标
  static Set<WebDAVSearchTarget> get defaultTargets => {
        WebDAVSearchTarget.folder,
        WebDAVSearchTarget.video,
      };
}

/// WebDAV 搜索超时选项
enum WebDAVSearchTimeout {
  seconds10(10, '10 秒'),
  seconds30(30, '30 秒'),
  seconds60(60, '60 秒'),
  unlimited(0, '无限制');

  final int seconds;
  final String displayName;
  const WebDAVSearchTimeout(this.seconds, this.displayName);

  static WebDAVSearchTimeout fromSeconds(int? seconds) {
    return values.firstWhere(
      (e) => e.seconds == seconds,
      orElse: () => WebDAVSearchTimeout.seconds30,
    );
  }
}

/// WebDAV 文件排序预设
enum WebDAVSortPreset {
  /// 默认：文件夹在前，各自按名称 A-Z
  defaultValue('default', '默认', '文件夹在前，名称 A-Z'),

  /// 名称 A-Z（混合排序）
  nameAsc('name_asc', '名称 A-Z', '所有项目按名称升序（例：A文件夹 → B文件 → C文件夹）'),

  /// 名称 Z-A（混合排序）
  nameDesc('name_desc', '名称 Z-A', '所有项目按名称降序（例：Z文件夹 → Y文件 → X文件夹）'),

  /// 最新修改
  modifiedDesc('modified_desc', '最新修改', '最近修改的项目在前'),

  /// 最旧修改
  modifiedAsc('modified_asc', '最旧修改', '最早修改的项目在前'),

  /// 最大文件
  sizeDesc('size_desc', '最大文件', '文件大小从大到小'),

  /// 最小文件
  sizeAsc('size_asc', '最小文件', '文件大小从小到大');

  final String value;
  final String displayName;
  final String description;

  const WebDAVSortPreset(this.value, this.displayName, this.description);

  static WebDAVSortPreset fromValue(String? value) {
    return WebDAVSortPreset.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WebDAVSortPreset.defaultValue,
    );
  }
}

/// WebDAV 快捷访问设置 Provider
/// 管理 WebDAV Tab 的显示开关、默认服务器、默认目录等设置
class WebDAVQuickAccessProvider extends ChangeNotifier {
  // 存储键名
  static const String _keyShowWebDAVTab = 'show_webdav_tab';
  static const String _keyDefaultServerName = 'webdav_default_server_name';
  static const String _keyDefaultDirectory = 'webdav_default_directory';
  static const String _keyDefaultHomeTab = 'default_home_tab';
  static const String _keySortPreset = 'webdav_sort_preset';
  static const String _keyAutoEnterSeasonFolder =
      'webdav_auto_enter_season_folder';
  static const String _keySeasonFolderPattern = 'webdav_season_folder_pattern';
  static const String _keyShowPathBreadcrumb = 'webdav_show_path_breadcrumb';
  static const String _keyBgmIdQuickMatch = 'webdav_bgmid_quick_match';
  static const String _keyBgmIdMatchPattern = 'webdav_bgmid_match_pattern';
  static const String _keyTmdbIdQuickMatch = 'webdav_tmdbid_quick_match';
  static const String _keyTmdbIdMatchPattern = 'webdav_tmdbid_match_pattern';
  static const String _keyEpisodeOffset = 'webdav_episode_offset';
  static const String _legacyDefaultPageIndexKey = 'default_page_index';

  // 搜索功能相关存储键名
  static const String _keyEnableSearch = 'webdav_enable_search';
  static const String _keySearchScope = 'webdav_search_scope';
  static const String _keySearchDepthLimit = 'webdav_search_depth_limit';
  static const String _keySearchTargets = 'webdav_search_targets';
  static const String _keySearchTimeout = 'webdav_search_timeout';
  static const String _keySearchRequestInterval =
      'webdav_search_request_interval';
  static const String _keySearchMaxResults = 'webdav_search_max_results';

  // Tab 名称常量
  static const String tabHome = AppPageIds.home;
  static const String tabVideo = AppPageIds.video;
  static const String tabMediaLibrary = AppPageIds.mediaLibrary;
  static const String tabTorrent = AppPageIds.torrent;
  static const String tabAccount = AppPageIds.account;
  static const String tabSettings = AppPageIds.settings;
  static const String tabWebDAV = AppPageIds.webdav;
  static const List<String> _allSupportedTabs = [
    tabHome,
    tabVideo,
    tabMediaLibrary,
    tabTorrent,
    tabAccount,
    tabSettings,
    tabWebDAV,
  ];

  // 状态
  bool _showWebDAVTab = false;
  String _defaultServerName = '';
  String _defaultDirectory = '/';
  String _defaultHomeTab = tabHome;
  WebDAVSortPreset _sortPreset = WebDAVSortPreset.defaultValue;
  bool _autoEnterSeasonFolder = false;
  String _seasonFolderPattern = 'Season*';
  bool _showPathBreadcrumb = true;
  bool _bgmIdQuickMatch = false; // 默认关闭，用户需明确启用
  String _bgmIdMatchPattern = 'bgm(id)?[=-](\\d+)'; // 默认正则规则
  bool _tmdbIdQuickMatch = false; // 默认关闭
  String _tmdbIdMatchPattern = 'tmdb(id)?[=-](\\d+)'; // 默认正则规则
  bool _episodeOffsetEnabled = false; // 默认关闭，实验功能
  bool _isLoaded = false;

  // 搜索功能相关状态
  bool _enableSearch = true; // 搜索功能总开关，默认开启
  WebDAVSearchScope _searchScope = WebDAVSearchScope.currentWithDepth;
  int _searchDepthLimit = 3; // 层级限制（1-10）
  Set<WebDAVSearchTarget> _searchTargets = WebDAVSearchTarget.defaultTargets;
  WebDAVSearchTimeout _searchTimeout = WebDAVSearchTimeout.seconds30;
  int _searchRequestInterval = 100; // 请求间隔（毫秒），默认100ms
  int _searchMaxResults = 500; // 最大搜索结果数，默认500

  // Getters
  bool get showWebDAVTab => _showWebDAVTab;
  String get defaultServerName => _defaultServerName;
  String get defaultDirectory => _defaultDirectory;
  String get defaultHomeTab => _defaultHomeTab;
  WebDAVSortPreset get sortPreset => _sortPreset;
  bool get autoEnterSeasonFolder => _autoEnterSeasonFolder;
  String get seasonFolderPattern => _seasonFolderPattern;
  bool get showPathBreadcrumb => _showPathBreadcrumb;
  bool get bgmIdQuickMatch => _bgmIdQuickMatch;
  String get bgmIdMatchPattern => _bgmIdMatchPattern;
  bool get tmdbIdQuickMatch => _tmdbIdQuickMatch;
  String get tmdbIdMatchPattern => _tmdbIdMatchPattern;
  bool get episodeOffsetEnabled => _episodeOffsetEnabled;
  bool get isLoaded => _isLoaded;

  // 搜索功能相关 Getters
  bool get enableSearch => _enableSearch;
  WebDAVSearchScope get searchScope => _searchScope;
  int get searchDepthLimit => _searchDepthLimit;
  Set<WebDAVSearchTarget> get searchTargets => _searchTargets;
  WebDAVSearchTimeout get searchTimeout => _searchTimeout;
  int get searchRequestInterval => _searchRequestInterval;
  int get searchMaxResults => _searchMaxResults;

  /// 获取有效的默认 Tab（处理 WebDAV 关闭时的回落）
  String get effectiveDefaultHomeTab {
    if (_defaultHomeTab == tabWebDAV && !_showWebDAVTab) {
      return tabHome;
    }

    if (_defaultHomeTab == tabTorrent &&
        !globals.isDownloaderSupportedPlatform) {
      return tabHome;
    }

    if (_isPhoneOnlyTab(_defaultHomeTab) ||
        !_allSupportedTabs.contains(_defaultHomeTab)) {
      return tabHome;
    }

    return _defaultHomeTab;
  }

  /// 桌面和平板布局可用的默认主页选项
  List<String> get desktopTabletAvailableTabs {
    final tabs = <String>[
      tabHome,
      tabVideo,
      if (_showWebDAVTab) tabWebDAV,
      tabMediaLibrary,
      if (globals.isDownloaderSupportedPlatform) tabTorrent,
      tabAccount,
    ];
    return tabs;
  }

  /// 手机布局可用的默认主页选项
  List<String> get phoneAvailableTabs {
    // 手机与桌面消费同一组主页面定义。设置是应用动作，不是主页面。
    return desktopTabletAvailableTabs;
  }

  /// 获取所有可用的 Tab 选项（根据 WebDAV 是否开启）
  List<String> get availableTabs {
    return desktopTabletAvailableTabs;
  }

  /// 获取 Tab 的显示名称
  static String getTabDisplayName(String tabName) {
    switch (tabName) {
      case tabHome:
        return '首页';
      case tabVideo:
        return '视频播放';
      case tabMediaLibrary:
        return '媒体库';
      case tabTorrent:
        return '下载器';
      case tabAccount:
        return '我的';
      case tabSettings:
        return '设置';
      case tabWebDAV:
        return 'WebDAV';
      default:
        return tabName;
    }
  }

  /// 获取默认服务器连接对象
  WebDAVConnection? get defaultConnection {
    if (_defaultServerName.isEmpty) return null;
    return WebDAVService.instance.getConnection(_defaultServerName);
  }

  /// 获取所有可用的 WebDAV 连接
  List<WebDAVConnection> get availableConnections =>
      WebDAVService.instance.connections;

  /// 从 SharedPreferences 加载设置
  Future<void> loadSettings() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _showWebDAVTab = prefs.getBool(_keyShowWebDAVTab) ?? false;
      _defaultServerName = prefs.getString(_keyDefaultServerName) ?? '';
      _defaultDirectory = prefs.getString(_keyDefaultDirectory) ?? '/';
      final storedDefaultHomeTab = prefs.getString(_keyDefaultHomeTab);
      if (storedDefaultHomeTab != null && storedDefaultHomeTab.isNotEmpty) {
        _defaultHomeTab = storedDefaultHomeTab;
      } else {
        _defaultHomeTab = _migrateLegacyDefaultPageIndex(prefs);
      }
      _sortPreset = WebDAVSortPreset.fromValue(prefs.getString(_keySortPreset));
      _autoEnterSeasonFolder =
          prefs.getBool(_keyAutoEnterSeasonFolder) ?? false;
      _seasonFolderPattern =
          prefs.getString(_keySeasonFolderPattern) ?? 'Season*';
      _showPathBreadcrumb = prefs.getBool(_keyShowPathBreadcrumb) ?? true;
      _bgmIdQuickMatch = prefs.getBool(_keyBgmIdQuickMatch) ?? false;
      _bgmIdMatchPattern =
          prefs.getString(_keyBgmIdMatchPattern) ?? 'bgm(id)?[=-](\\d+)';
      _tmdbIdQuickMatch = prefs.getBool(_keyTmdbIdQuickMatch) ?? false;
      _tmdbIdMatchPattern =
          prefs.getString(_keyTmdbIdMatchPattern) ?? 'tmdb(id)?[=-](\\d+)';
      _episodeOffsetEnabled = prefs.getBool(_keyEpisodeOffset) ?? false;

      // 加载搜索功能相关设置
      _enableSearch = prefs.getBool(_keyEnableSearch) ?? true;
      _searchScope =
          WebDAVSearchScope.fromValue(prefs.getString(_keySearchScope));
      _searchDepthLimit = prefs.getInt(_keySearchDepthLimit) ?? 3;
      // 加载搜索目标（多选）
      final storedTargets = prefs.getStringList(_keySearchTargets);
      if (storedTargets != null && storedTargets.isNotEmpty) {
        _searchTargets =
            storedTargets.map((v) => WebDAVSearchTarget.fromValue(v)).toSet();
      } else {
        _searchTargets = WebDAVSearchTarget.defaultTargets;
      }
      _searchTimeout =
          WebDAVSearchTimeout.fromSeconds(prefs.getInt(_keySearchTimeout));
      _searchRequestInterval = prefs.getInt(_keySearchRequestInterval) ?? 100;
      _searchMaxResults = prefs.getInt(_keySearchMaxResults) ?? 500;

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('加载 WebDAV 快捷设置失败: $e');
    }
  }

  /// 设置是否显示 WebDAV Tab
  Future<void> setShowWebDAVTab(bool value) async {
    if (_showWebDAVTab == value) return;

    _showWebDAVTab = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowWebDAVTab, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 WebDAV Tab 显示设置失败: $e');
    }
  }

  /// 设置默认主页 Tab
  Future<void> setDefaultHomeTab(String tabName) async {
    if (!_allSupportedTabs.contains(tabName)) {
      return;
    }
    if (tabName == tabTorrent && !globals.isDownloaderSupportedPlatform) {
      return;
    }
    if (_defaultHomeTab == tabName) return;

    _defaultHomeTab = tabName;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultHomeTab, tabName);
      notifyListeners();
    } catch (e) {
      debugPrint('保存默认主页 Tab 设置失败: $e');
    }
  }

  String _migrateLegacyDefaultPageIndex(SharedPreferences prefs) {
    final legacyIndex = prefs.getInt(_legacyDefaultPageIndexKey);
    switch (legacyIndex) {
      case 1:
        return tabVideo;
      case 2:
        return tabMediaLibrary;
      case 3:
        return tabAccount;
      case 0:
      default:
        return tabHome;
    }
  }

  bool _isPhoneOnlyTab(String tabName) {
    return tabName == tabSettings;
  }

  /// 设置排序预设
  Future<void> setSortPreset(WebDAVSortPreset preset) async {
    if (_sortPreset == preset) return;

    _sortPreset = preset;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySortPreset, preset.value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存排序设置失败: $e');
    }
  }

  /// 设置默认服务器名称
  Future<void> setDefaultServerName(String serverName) async {
    if (_defaultServerName == serverName) return;

    _defaultServerName = serverName;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultServerName, serverName);
      notifyListeners();
    } catch (e) {
      debugPrint('保存默认服务器设置失败: $e');
    }
  }

  /// 设置默认目录
  Future<void> setDefaultDirectory(String directory) async {
    if (_defaultDirectory == directory) return;

    // 确保目录以 / 开头
    if (!directory.startsWith('/')) {
      directory = '/$directory';
    }

    _defaultDirectory = directory;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultDirectory, directory);
      notifyListeners();
    } catch (e) {
      debugPrint('保存默认目录设置失败: $e');
    }
  }

  /// 验证当前设置是否有效（有可用的默认服务器）
  bool get hasValidDefaultServer {
    if (_defaultServerName.isEmpty) return false;
    return defaultConnection != null;
  }

  /// 设置是否自动进入 Season 文件夹
  Future<void> setAutoEnterSeasonFolder(bool value) async {
    if (_autoEnterSeasonFolder == value) return;

    _autoEnterSeasonFolder = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoEnterSeasonFolder, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存自动进入 Season 文件夹设置失败: $e');
    }
  }

  /// 设置 Season 文件夹匹配模式
  Future<void> setSeasonFolderPattern(String pattern) async {
    if (_seasonFolderPattern == pattern) return;

    _seasonFolderPattern = pattern;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySeasonFolderPattern, pattern);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 Season 文件夹匹配模式失败: $e');
    }
  }

  /// 设置是否显示路径面包屑导航
  Future<void> setShowPathBreadcrumb(bool value) async {
    if (_showPathBreadcrumb == value) return;

    _showPathBreadcrumb = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowPathBreadcrumb, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存路径面包屑显示设置失败: $e');
    }
  }

  /// 设置是否启用 bgmid 快速匹配
  Future<void> setBgmIdQuickMatch(bool value) async {
    if (_bgmIdQuickMatch == value) return;

    _bgmIdQuickMatch = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBgmIdQuickMatch, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 bgmid 快速匹配设置失败: $e');
    }
  }

  /// 设置 bgmid 匹配正则表达式
  /// 用户自定义正则规则，必须包含捕获组提取数字
  Future<void> setBgmIdMatchPattern(String pattern) async {
    if (_bgmIdMatchPattern == pattern) return;

    try {
      RegExp(pattern);
    } catch (e) {
      debugPrint('无效的正则表达式: $pattern, 错误: $e');
      return;
    }

    // 统计未转义的左括号来验证至少有 1 个捕获组
    int groupCount = 0;
    for (int i = 0; i < pattern.length; i++) {
      if (pattern[i] == '(' && (i == 0 || pattern[i - 1] != '\\')) {
        groupCount++;
      }
    }
    if (groupCount < 1) {
      debugPrint('正则表达式缺少捕获组: $pattern（需要用括号捕获数字，如 bgmid=(\\d+)）');
      return;
    }

    _bgmIdMatchPattern = pattern;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBgmIdMatchPattern, pattern);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 bgmid 匹配规则失败: $e');
    }
  }

  /// 设置是否启用 tmdbId 快速匹配
  Future<void> setTmdbIdQuickMatch(bool value) async {
    if (_tmdbIdQuickMatch == value) return;

    _tmdbIdQuickMatch = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyTmdbIdQuickMatch, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 tmdbId 快速匹配设置失败: $e');
    }
  }

  /// 设置 tmdbId 匹配正则表达式
  Future<void> setTmdbIdMatchPattern(String pattern) async {
    if (_tmdbIdMatchPattern == pattern) return;

    try {
      RegExp(pattern);
    } catch (e) {
      debugPrint('无效的正则表达式: $pattern, 错误: $e');
      return;
    }

    int groupCount = 0;
    for (int i = 0; i < pattern.length; i++) {
      if (pattern[i] == '(' && (i == 0 || pattern[i - 1] != '\\')) {
        groupCount++;
      }
    }
    if (groupCount < 1) {
      debugPrint('正则表达式缺少捕获组: $pattern（需要用括号捕获数字，如 tmdbid=(\\d+)）');
      return;
    }

    _tmdbIdMatchPattern = pattern;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTmdbIdMatchPattern, pattern);
      notifyListeners();
    } catch (e) {
      debugPrint('保存 tmdbId 匹配规则失败: $e');
    }
  }

  /// 设置是否启用剧集偏移（实验功能）
  Future<void> setEpisodeOffsetEnabled(bool value) async {
    if (_episodeOffsetEnabled == value) return;

    _episodeOffsetEnabled = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEpisodeOffset, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存剧集偏移设置失败: $e');
    }
  }

  // ==================== 搜索功能相关 Setter ====================

  /// 设置是否启用搜索功能
  Future<void> setEnableSearch(bool value) async {
    if (_enableSearch == value) return;

    _enableSearch = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnableSearch, value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索功能开关设置失败: $e');
    }
  }

  /// 设置搜索范围
  Future<void> setSearchScope(WebDAVSearchScope scope) async {
    if (_searchScope == scope) return;

    _searchScope = scope;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySearchScope, scope.value);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索范围设置失败: $e');
    }
  }

  /// 设置搜索层级限制
  Future<void> setSearchDepthLimit(int limit) async {
    if (_searchDepthLimit == limit) return;

    // 确保在有效范围内
    limit = limit.clamp(1, 10);
    _searchDepthLimit = limit;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySearchDepthLimit, limit);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索层级限制设置失败: $e');
    }
  }

  /// 设置搜索目标类型
  Future<void> setSearchTargets(Set<WebDAVSearchTarget> targets) async {
    if (_searchTargets == targets) return;

    _searchTargets = targets;

    try {
      final prefs = await SharedPreferences.getInstance();
      final targetValues = targets.map((t) => t.value).toList();
      await prefs.setStringList(_keySearchTargets, targetValues);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索目标类型设置失败: $e');
    }
  }

  /// 切换单个搜索目标类型
  Future<void> toggleSearchTarget(WebDAVSearchTarget target) async {
    final newTargets = Set<WebDAVSearchTarget>.from(_searchTargets);
    if (newTargets.contains(target)) {
      // 至少保留一个选项
      if (newTargets.length > 1) {
        newTargets.remove(target);
      }
    } else {
      newTargets.add(target);
    }
    await setSearchTargets(newTargets);
  }

  /// 设置搜索超时时间
  Future<void> setSearchTimeout(WebDAVSearchTimeout timeout) async {
    if (_searchTimeout == timeout) return;

    _searchTimeout = timeout;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySearchTimeout, timeout.seconds);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索超时设置失败: $e');
    }
  }

  /// 设置搜索请求间隔（毫秒）
  Future<void> setSearchRequestInterval(int intervalMs) async {
    if (_searchRequestInterval == intervalMs) return;

    // 确保在有效范围内（0-5000ms）
    intervalMs = intervalMs.clamp(0, 5000);
    _searchRequestInterval = intervalMs;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySearchRequestInterval, intervalMs);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索请求间隔设置失败: $e');
    }
  }

  /// 设置搜索最大结果数
  Future<void> setSearchMaxResults(int maxResults) async {
    if (_searchMaxResults == maxResults) return;

    // 确保在有效范围内（50-2000）
    maxResults = maxResults.clamp(50, 2000);
    _searchMaxResults = maxResults;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySearchMaxResults, maxResults);
      notifyListeners();
    } catch (e) {
      debugPrint('保存搜索最大结果数设置失败: $e');
    }
  }

  /// 检查文件夹名称是否匹配模式（支持通配符 * 和 ?）
  bool matchesSeasonPattern(String folderName) {
    if (_seasonFolderPattern.isEmpty) return false;

    // 将通配符模式转换为正则表达式
    String pattern = _seasonFolderPattern
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    pattern = '^$pattern\$';

    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(folderName);
    } catch (e) {
      debugPrint('匹配模式解析失败: $e');
      return false;
    }
  }

  /// 在文件夹列表中查找匹配的 Season 文件夹
  String? findMatchingSeasonFolder(List<String> folderNames) {
    if (!_autoEnterSeasonFolder || _seasonFolderPattern.isEmpty) {
      return null;
    }

    final matchingFolders =
        folderNames.where((name) => matchesSeasonPattern(name)).toList();

    // 如果只有一个匹配项，返回它
    if (matchingFolders.length == 1) {
      return matchingFolders.first;
    }

    // 如果有多个匹配项，按自然排序返回第一个
    if (matchingFolders.isNotEmpty) {
      matchingFolders.sort((a, b) => _naturalCompare(a, b));
      return matchingFolders.first;
    }

    return null;
  }

  /// 自然排序比较（处理数字）
  static int _naturalCompare(String a, String b) {
    if (RustLib.instance.initialized) {
      try {
        return rust_metadata.naturalCompareCaseSensitive(a: a, b: b);
      } catch (_) {
        // 使用下方 Dart/Web fallback。
      }
    }
    final regex = RegExp(r'(\d+)|(\D+)');
    final aMatches = regex.allMatches(a).toList();
    final bMatches = regex.allMatches(b).toList();

    for (int i = 0; i < aMatches.length && i < bMatches.length; i++) {
      final aPart = aMatches[i].group(0)!;
      final bPart = bMatches[i].group(0)!;

      final aNum = int.tryParse(aPart);
      final bNum = int.tryParse(bPart);

      if (aNum != null && bNum != null) {
        final cmp = aNum.compareTo(bNum);
        if (cmp != 0) return cmp;
      } else {
        final cmp = aPart.compareTo(bPart);
        if (cmp != 0) return cmp;
      }
    }

    return aMatches.length.compareTo(bMatches.length);
  }

  /// 重置所有设置
  Future<void> resetSettings() async {
    _showWebDAVTab = false;
    _defaultServerName = '';
    _defaultDirectory = '/';
    _defaultHomeTab = tabHome;
    _sortPreset = WebDAVSortPreset.defaultValue;
    _autoEnterSeasonFolder = false;
    _seasonFolderPattern = 'Season*';
    _showPathBreadcrumb = true;
    _bgmIdQuickMatch = false;
    _bgmIdMatchPattern = 'bgm(id)?[=-](\\d+)';
    _tmdbIdQuickMatch = false;
    _tmdbIdMatchPattern = 'tmdb(id)?[=-](\\d+)';
    _episodeOffsetEnabled = false;

    // 重置搜索功能相关设置
    _enableSearch = true;
    _searchScope = WebDAVSearchScope.currentWithDepth;
    _searchDepthLimit = 3;
    _searchTargets = WebDAVSearchTarget.defaultTargets;
    _searchTimeout = WebDAVSearchTimeout.seconds30;
    _searchRequestInterval = 100;
    _searchMaxResults = 500;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyShowWebDAVTab);
      await prefs.remove(_keyDefaultServerName);
      await prefs.remove(_keyDefaultDirectory);
      await prefs.remove(_keyDefaultHomeTab);
      await prefs.remove(_keySortPreset);
      await prefs.remove(_keyAutoEnterSeasonFolder);
      await prefs.remove(_keySeasonFolderPattern);
      await prefs.remove(_keyShowPathBreadcrumb);
      await prefs.remove(_keyBgmIdQuickMatch);
      await prefs.remove(_keyBgmIdMatchPattern);
      await prefs.remove(_keyTmdbIdQuickMatch);
      await prefs.remove(_keyTmdbIdMatchPattern);
      await prefs.remove(_keyEpisodeOffset);
      // 清除搜索功能相关设置
      await prefs.remove(_keyEnableSearch);
      await prefs.remove(_keySearchScope);
      await prefs.remove(_keySearchDepthLimit);
      await prefs.remove(_keySearchTargets);
      await prefs.remove(_keySearchTimeout);
      await prefs.remove(_keySearchRequestInterval);
      await prefs.remove(_keySearchMaxResults);
      notifyListeners();
    } catch (e) {
      debugPrint('重置 WebDAV 快捷设置失败: $e');
    }
  }
}
