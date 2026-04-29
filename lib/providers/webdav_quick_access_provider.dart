import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/services/webdav_service.dart';

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
  static const String _keyAutoEnterSeasonFolder = 'webdav_auto_enter_season_folder';
  static const String _keySeasonFolderPattern = 'webdav_season_folder_pattern';
  static const String _keyShowPathBreadcrumb = 'webdav_show_path_breadcrumb';

  // Tab 名称常量
  static const String tabHome = 'home';
  static const String tabVideo = 'video';
  static const String tabMediaLibrary = 'media_library';
  static const String tabAccount = 'account';
  static const String tabSettings = 'settings';
  static const String tabWebDAV = 'webdav';

  // 状态
  bool _showWebDAVTab = false;
  String _defaultServerName = '';
  String _defaultDirectory = '/';
  String _defaultHomeTab = tabHome;
  WebDAVSortPreset _sortPreset = WebDAVSortPreset.defaultValue;
  bool _autoEnterSeasonFolder = false;
  String _seasonFolderPattern = 'Season*';
  bool _showPathBreadcrumb = true;
  bool _isLoaded = false;

  // Getters
  bool get showWebDAVTab => _showWebDAVTab;
  String get defaultServerName => _defaultServerName;
  String get defaultDirectory => _defaultDirectory;
  String get defaultHomeTab => _defaultHomeTab;
  WebDAVSortPreset get sortPreset => _sortPreset;
  bool get autoEnterSeasonFolder => _autoEnterSeasonFolder;
  String get seasonFolderPattern => _seasonFolderPattern;
  bool get showPathBreadcrumb => _showPathBreadcrumb;
  bool get isLoaded => _isLoaded;

  /// 获取有效的默认 Tab（处理 WebDAV 关闭时的回落）
  String get effectiveDefaultHomeTab {
    if (_defaultHomeTab == tabWebDAV && !_showWebDAVTab) {
      return tabHome; // WebDAV 关闭时回落到首页
    }
    return _defaultHomeTab;
  }

  /// 获取所有可用的 Tab 选项（根据 WebDAV 是否开启）
  List<String> get availableTabs {
    if (_showWebDAVTab) {
      return [tabHome, tabVideo, tabWebDAV, tabMediaLibrary, tabAccount, tabSettings];
    }
    return [tabHome, tabVideo, tabMediaLibrary, tabAccount, tabSettings];
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
      _defaultHomeTab = prefs.getString(_keyDefaultHomeTab) ?? tabHome;
      _sortPreset = WebDAVSortPreset.fromValue(prefs.getString(_keySortPreset));
      _autoEnterSeasonFolder = prefs.getBool(_keyAutoEnterSeasonFolder) ?? false;
      _seasonFolderPattern = prefs.getString(_keySeasonFolderPattern) ?? 'Season*';
      _showPathBreadcrumb = prefs.getBool(_keyShowPathBreadcrumb) ?? true;

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

    final matchingFolders = folderNames
        .where((name) => matchesSeasonPattern(name))
        .toList();

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
      notifyListeners();
    } catch (e) {
      debugPrint('重置 WebDAV 快捷设置失败: $e');
    }
  }
}
