import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/global_hotkey_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/chinese_converter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';

class BatchDanmakuMatchDialog extends StatefulWidget {
  final List<String> filePaths;
  final String? initialSearchKeyword;
  final bool embedded;

  const BatchDanmakuMatchDialog({
    super.key,
    required this.filePaths,
    this.initialSearchKeyword,
    this.embedded = false,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<String> filePaths,
    String? initialSearchKeyword,
  }) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoBottomSheet.show<Map<String, dynamic>>(
        context: context,
        title: '批量匹配弹幕',
        floatingTitle: true,
        child: BatchDanmakuMatchDialog(
          filePaths: filePaths,
          initialSearchKeyword: initialSearchKeyword,
          embedded: true,
        ),
      );
    }

    return NipaplayWindow.show<Map<String, dynamic>>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: BatchDanmakuMatchDialog(
        filePaths: filePaths,
        initialSearchKeyword: initialSearchKeyword,
      ),
    );
  }

  @override
  State<BatchDanmakuMatchDialog> createState() =>
      _BatchDanmakuMatchDialogState();
}

class _BatchDanmakuMatchDialogState extends State<BatchDanmakuMatchDialog>
    with GlobalHotkeyManagerMixin {
  static const double _rowIndexWidth = 32;
  static Color get _accentColor => AppAccentColors.current;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isSearching = false;
  String _searchMessage = '';
  List<Map<String, dynamic>> _searchResults = [];

  Map<String, dynamic>? _selectedAnime;

  bool _isLoadingEpisodes = false;
  String _episodesMessage = '';
  final List<_EpisodeItem> _episodes = [];
  final Set<int> _selectedEpisodeIds = {};

  late final List<_FileItem> _files;

  @override
  String get hotkeyDisableReason => 'batch_danmaku_dialog';

  /// 从路径或 URL 得到显示名：URL 取 pathSegments 最后一段，本地路径用 basename。
  /// 特殊处理 SMB 代理 URL（形如 http://127.0.0.1:PORT/smb/stream?conn=...&path=/foo/bar.mkv），
  /// 真实文件名在查询参数 path 里，pathSegments.last 只会得到 "stream"。
  static String _displayNameFromPath(String path) {
    if (path.contains('://')) {
      final uri = Uri.tryParse(path);
      if (uri != null) {
        // SMB 代理：从查询参数 path 取真实文件名
        final smbPath = uri.queryParameters['path'];
        if (smbPath != null && smbPath.isNotEmpty) {
          final lastSlash = smbPath.lastIndexOf('/');
          final tail =
              lastSlash >= 0 ? smbPath.substring(lastSlash + 1) : smbPath;
          if (tail.isNotEmpty) return tail;
        }
        // 一般 HTTP URL：取 pathSegments 最后一段
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final last = segments.last;
          if (last.isNotEmpty) return last;
        }
      }
      return path;
    }
    return p.basename(path);
  }

  @override
  void initState() {
    super.initState();
    _files = widget.filePaths
        .map(
          (path) =>
              _FileItem(path: path, displayName: _displayNameFromPath(path)),
        )
        .toList(growable: true);

    // 默认自动排序文件
    _sortFilesByEpisodeNumber();

    if (widget.initialSearchKeyword?.trim().isNotEmpty == true) {
      _searchController.text = widget.initialSearchKeyword!.trim();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      disableHotkeys();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    disposeHotkeys();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int get _selectedFileCount => _files.where((e) => e.selected).length;

  List<_FileItem> get _selectedFilesInOrder =>
      _files.where((e) => e.selected).toList(growable: false);

  List<_EpisodeItem> get _selectedEpisodesInOrder => _episodes
      .where((e) => _selectedEpisodeIds.contains(e.episodeId))
      .toList(growable: false);

  bool get _canConfirm =>
      _selectedAnime != null &&
      _selectedFileCount > 0 &&
      _selectedFileCount == _selectedEpisodesInOrder.length;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _subTextColor => _textColor.withOpacity(0.7);
  Color get _mutedTextColor => _textColor.withOpacity(0.5);
  Color get _borderColor => _textColor.withOpacity(_isDarkMode ? 0.12 : 0.2);
  Color get _surfaceColor =>
      _isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
  Color get _panelColor =>
      _isDarkMode ? const Color(0xFF262626) : const Color(0xFFE8E8E8);
  Color get _panelAltColor =>
      _isDarkMode ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);

  TextSelectionThemeData get _selectionTheme => TextSelectionThemeData(
        cursorColor: _accentColor,
        selectionColor: _accentColor.withOpacity(0.3),
        selectionHandleColor: _accentColor,
      );

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searchMessage = '请输入搜索关键词';
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _searchResults = [];
    });

    try {
      if (!mounted) return;

      final results =
          await DanmakuMatchingService.instance.searchAnime(keyword);
      if (!mounted) return;

      // 对搜索结果进行简繁转换
      final isTraditional =
          await ChineseConverter.isTraditionalChineseEnvironment(context);
      if (isTraditional) {
        // 对每个搜索结果进行转换
        for (var anime in results) {
          if (anime['animeTitle'] != null) {
            anime['animeTitle'] =
                ChineseConverter.convert(anime['animeTitle'].toString());
          }
        }
      }

      setState(() {
        _isSearching = false;
        _searchResults = results;
        _searchMessage = results.isEmpty ? '没有找到匹配的动画' : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
        _searchResults = [];
      });
    }
  }

  Future<void> _selectAnime(Map<String, dynamic> anime) async {
    final animeId = _tryParsePositiveInt(anime['animeId']);
    final animeTitle = anime['animeTitle']?.toString().trim() ?? '';
    if (animeId == null || animeTitle.isEmpty) {
      setState(() {
        _episodesMessage = '动画信息不完整，无法加载剧集';
        _episodes.clear();
        _selectedEpisodeIds.clear();
        _selectedAnime = null;
      });
      return;
    }

    setState(() {
      _selectedAnime = anime;
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _episodes.clear();
      _selectedEpisodeIds.clear();
    });

    try {
      final rawEpisodes =
          await DanmakuMatchingService.instance.getAnimeEpisodes(animeId);
      if (!mounted) return;

      final parsedEpisodes = <_EpisodeItem>[];
      // 检查是否需要繁体中文
      final isTraditional =
          await ChineseConverter.isTraditionalChineseEnvironment(context);
      for (final map in rawEpisodes) {
        final episodeId = _tryParsePositiveInt(map['episodeId']);
        if (episodeId == null) continue;
        var episodeTitle = map['episodeTitle']?.toString().trim() ?? '未命名剧集';
        // 对剧集标题进行简繁转换
        if (isTraditional) {
          episodeTitle = ChineseConverter.convert(episodeTitle);
        }
        parsedEpisodes.add(
          _EpisodeItem(
            episodeId: episodeId,
            episodeTitle: episodeTitle,
            episodeNumber: _tryParsePositiveInt(map['episodeNumber']),
          ),
        );
      }

      setState(() {
        _isLoadingEpisodes = false;
        _episodes
          ..clear()
          ..addAll(parsedEpisodes);
        _episodesMessage = parsedEpisodes.isEmpty ? '该动画暂无剧集信息' : '';
      });

      _autoSelectEpisodesToMatchFileCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '加载剧集时出错: $e';
      });
    }
  }

  void _autoSelectEpisodesToMatchFileCount() {
    if (_episodes.isEmpty) return;
    final target = _selectedFileCount;
    if (target <= 0) return;

    setState(() {
      _selectedEpisodeIds.clear();
      for (final episode in _episodes.take(target)) {
        _selectedEpisodeIds.add(episode.episodeId);
      }
    });
  }

  void _sortFilesByEpisodeNumber() {
    setState(() {
      _files.sort((a, b) {
        // 先按sortKey排序，sortKey为null的排在最后
        if (a.sortKey != null && b.sortKey != null) {
          return a.sortKey!.compareTo(b.sortKey!);
        }
        if (a.sortKey != null) return -1;
        if (b.sortKey != null) return 1;
        // 如果都没有sortKey，按文件名排序
        return a.displayName.compareTo(b.displayName);
      });
    });
  }

  void _confirmAndClose() {
    if (!_canConfirm) return;

    final animeId = _tryParsePositiveInt(_selectedAnime!['animeId']);
    final animeTitle = _selectedAnime!['animeTitle']?.toString() ?? '';
    if (animeId == null) return;

    final selectedFiles = _selectedFilesInOrder;
    final selectedEpisodes = _selectedEpisodesInOrder;
    if (selectedFiles.length != selectedEpisodes.length) return;

    final mappings = <Map<String, dynamic>>[];
    for (int i = 0; i < selectedFiles.length; i++) {
      mappings.add({
        'filePath': selectedFiles[i].path,
        'fileName': selectedFiles[i].displayName,
        'episodeId': selectedEpisodes[i].episodeId,
        'episodeTitle': selectedEpisodes[i].episodeTitle,
        'episodeNumber': selectedEpisodes[i].episodeNumber,
      });
    }

    Navigator.of(
      context,
    ).pop({'animeId': animeId, 'animeTitle': animeTitle, 'mappings': mappings});
  }

  static int? _tryParsePositiveInt(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is double) {
      final v = value.toInt();
      return v > 0 ? v : null;
    }
    if (value is String) {
      final v = int.tryParse(value);
      return (v != null && v > 0) ? v : null;
    }
    return null;
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: _panelColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _borderColor),
    );
  }

  Widget _buildRowIndexText(int index, {required bool isDragging}) {
    final textColor = _mutedTextColor;
    return SizedBox(
      width: _rowIndexWidth,
      child: Text(
        '${index + 1}',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildFileListItem(
    _FileItem item,
    int index, {
    required bool isDragging,
    required bool showBottomDivider,
  }) {
    final textColor = _textColor;
    final iconColor = _mutedTextColor;
    final backgroundColor = isDragging ? _surfaceColor : _panelAltColor;
    final borderColor =
        isDragging ? _accentColor.withOpacity(0.35) : _borderColor;

    return Container(
      key: ValueKey(item.path),
      margin: EdgeInsets.only(bottom: showBottomDivider ? 8 : 0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDragging
            ? null
            : () {
                setState(() {
                  item.selected = !item.selected;
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              AdaptiveMediaCheckbox(
                value: item.selected,
                onChanged: isDragging
                    ? null
                    : (value) {
                        setState(() {
                          item.selected = value;
                        });
                      },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: TextStyle(color: textColor, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.episodeNumber != null) ...[
                      SizedBox(height: 2),
                      Text(
                        '剧集: ${item.episodeNumber}',
                        style: TextStyle(color: _subTextColor, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 6),
              _buildRowIndexText(index, isDragging: isDragging),
              SizedBox(width: 6),
              ReorderableDragStartListener(
                index: index,
                enabled: !isDragging,
                child: Icon(Icons.drag_handle, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeListItem(
    _EpisodeItem episode,
    int index, {
    required bool isDragging,
    required bool showBottomDivider,
  }) {
    final checked = _selectedEpisodeIds.contains(episode.episodeId);
    final label = episode.episodeNumber != null
        ? '第${episode.episodeNumber}话  ${episode.episodeTitle}'
        : episode.episodeTitle;

    final textColor = _textColor;
    final iconColor = _mutedTextColor;
    final backgroundColor = isDragging ? _surfaceColor : _panelAltColor;
    final borderColor =
        isDragging ? _accentColor.withOpacity(0.35) : _borderColor;

    return Container(
      key: ValueKey(episode.episodeId),
      margin: EdgeInsets.only(bottom: showBottomDivider ? 8 : 0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDragging
            ? null
            : () {
                setState(() {
                  if (checked) {
                    _selectedEpisodeIds.remove(episode.episodeId);
                  } else {
                    _selectedEpisodeIds.add(episode.episodeId);
                  }
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              AdaptiveMediaCheckbox(
                value: checked,
                onChanged: isDragging
                    ? null
                    : (value) {
                        setState(() {
                          if (value) {
                            _selectedEpisodeIds.add(episode.episodeId);
                          } else {
                            _selectedEpisodeIds.remove(episode.episodeId);
                          }
                        });
                      },
              ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: textColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 6),
              _buildRowIndexText(index, isDragging: isDragging),
              SizedBox(width: 6),
              ReorderableDragStartListener(
                index: index,
                enabled: !isDragging,
                child: Icon(Icons.drag_handle, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultItem(
    Map<String, dynamic> anime,
    int index, {
    required bool showBottomDivider,
  }) {
    final title = anime['animeTitle']?.toString() ?? '未知动画';
    final animeId = anime['animeId']?.toString() ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectAnime(anime),
        child: Container(
          margin: EdgeInsets.only(bottom: showBottomDivider ? 8 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _panelAltColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (animeId.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        'ID: $animeId',
                        style: TextStyle(color: _subTextColor, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              _buildRowIndexText(index, isDragging: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.playlist_add_check,
            color: _accentColor,
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '批量匹配弹幕',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '对齐本地文件与剧集顺序，一键完成匹配',
                style: TextStyle(color: _subTextColor, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: AdaptiveMediaSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            placeholder: '搜索番剧（右侧先选番剧再选话数）',
            onChanged: (_) {},
            onSubmitted: (_) => _performSearch(),
          ),
        ),
        SizedBox(width: 12),
        AdaptiveMediaActionButton(
          onPressed: _isSearching ? null : _performSearch,
          label: _isSearching ? '搜索中' : '搜索',
          desktopIcon: Icons.search_rounded,
          phoneIcon: cupertino.CupertinoIcons.search,
          emphasis: AdaptiveMediaActionEmphasis.primary,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildStatusBanner(String message, {bool isError = false}) {
    final backgroundColor = isError
        ? Colors.red.withOpacity(_isDarkMode ? 0.2 : 0.12)
        : _accentColor.withOpacity(_isDarkMode ? 0.18 : 0.12);
    final borderColor = isError
        ? Colors.redAccent.withOpacity(0.4)
        : _accentColor.withOpacity(0.35);
    final iconColor = isError ? Colors.redAccent : _accentColor;
    final textColor = isError ? Colors.redAccent : _textColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: iconColor,
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: _mutedTextColor, size: 32),
          SizedBox(height: 8),
          Text(title, style: TextStyle(color: _subTextColor, fontSize: 13)),
          if (subtitle != null) ...[
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesPanel(BuildContext context) {
    final windowHeight = MediaQuery.of(context).size.height;
    final panelHeight = windowHeight * 0.4; // 占窗口高度的40%

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          '待匹配文件',
          trailing: Text(
            '已选 $_selectedFileCount/${_files.length}',
            style: TextStyle(color: _subTextColor, fontSize: 12),
          ),
        ),
        SizedBox(height: 8),
        Container(
          height: panelHeight,
          decoration: _panelDecoration(),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            itemCount: _files.length,
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) {
              final item = _files[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildFileListItem(
                    item,
                    index,
                    isDragging: true,
                    showBottomDivider: false,
                  ),
                ),
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _files.removeAt(oldIndex);
                _files.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final item = _files[index];
              final showBottomDivider = index != _files.length - 1;
              return _buildFileListItem(
                item,
                index,
                isDragging: false,
                showBottomDivider: showBottomDivider,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeSearchResultsPanel(BuildContext context) {
    final windowHeight = MediaQuery.of(context).size.height;
    final panelHeight = windowHeight * 0.4; // 占窗口高度的40%

    final bool isError = _searchMessage.contains('出错');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('搜索结果'),
        if (_searchMessage.isNotEmpty) ...[
          SizedBox(height: 8),
          _buildStatusBanner(_searchMessage, isError: isError),
        ],
        SizedBox(height: 8),
        Container(
          height: panelHeight,
          decoration: _panelDecoration(),
          child: _isSearching
              ? Center(
                  child: AdaptiveMediaActivityIndicator(
                    size: 18,
                    color: _accentColor,
                  ),
                )
              : _searchResults.isEmpty
                  ? _buildEmptyState('暂无搜索结果')
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final anime = _searchResults[index];
                        final showBottomDivider =
                            index != _searchResults.length - 1;
                        return _buildSearchResultItem(
                          anime,
                          index,
                          showBottomDivider: showBottomDivider,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEpisodesPanel(BuildContext context) {
    final windowHeight = MediaQuery.of(context).size.height;
    final panelHeight = windowHeight * 0.4; // 占窗口高度的40%

    final selectedEpisodesCount = _selectedEpisodesInOrder.length;
    final mismatch =
        _selectedFileCount != selectedEpisodesCount && _selectedAnime != null;
    final bool isError =
        _episodesMessage.contains('出错') || _episodesMessage.contains('失败');

    Widget panelContent;
    if (_isLoadingEpisodes) {
      panelContent = Center(
        child: AdaptiveMediaActivityIndicator(
          size: 18,
          color: _accentColor,
        ),
      );
    } else if (_episodes.isEmpty) {
      panelContent = _buildEmptyState('暂无剧集');
    } else {
      panelContent = ReorderableListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        itemCount: _episodes.length,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          final episode = _episodes[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _buildEpisodeListItem(
                episode,
                index,
                isDragging: true,
                showBottomDivider: false,
              ),
            ),
          );
        },
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _episodes.removeAt(oldIndex);
            _episodes.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) {
          final episode = _episodes[index];
          final showBottomDivider = index != _episodes.length - 1;
          return _buildEpisodeListItem(
            episode,
            index,
            isDragging: false,
            showBottomDivider: showBottomDivider,
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          '剧集列表',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已选 $selectedEpisodesCount/${_episodes.length}',
                style: TextStyle(color: _subTextColor, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        if (_episodesMessage.isNotEmpty) ...[
          _buildStatusBanner(_episodesMessage, isError: isError),
          SizedBox(height: 8),
        ],
        Container(
          height: panelHeight,
          decoration: _panelDecoration(),
          child: panelContent,
        ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '需要：左侧已选文件数 == 右侧已选话数',
              style: TextStyle(color: Colors.redAccent.withOpacity(0.9)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final sheetScope = CupertinoBottomSheetScope.maybeOf(context);
    final topPadding = widget.embedded && sheetScope != null
        ? sheetScope.contentTopInset / 1.3 + sheetScope.contentTopSpacing + 8
        : 16.0;
    final content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24 + keyboardHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.embedded) ...[
            _buildHeader(),
            const SizedBox(height: 16),
          ],
          _buildSearchBar(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWideLayout = constraints.maxWidth >= 820;
              final rightPanel = _selectedAnime == null
                  ? _buildAnimeSearchResultsPanel(context)
                  : _buildEpisodesPanel(context);

              if (isWideLayout) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildFilesPanel(context)),
                    const SizedBox(width: 16),
                    Expanded(child: rightPanel),
                  ],
                );
              }

              return Column(
                children: [
                  _buildFilesPanel(context),
                  const SizedBox(height: 12),
                  rightPanel,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedAnime == null
                      ? (_searchMessage.isNotEmpty
                          ? _searchMessage
                          : '先在右侧搜索并选择番剧')
                      : '对齐顺序后点击“一键匹配”',
                  style: TextStyle(color: _subTextColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AdaptiveMediaActionButton(
                onPressed: _canConfirm ? _confirmAndClose : null,
                label: '一键匹配',
                desktopIcon: Icons.done_all_rounded,
                phoneIcon: cupertino.CupertinoIcons.check_mark_circled,
                emphasis: AdaptiveMediaActionEmphasis.primary,
              ),
            ],
          ),
        ],
      ),
    );
    final body = Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: TextSelectionTheme(data: _selectionTheme, child: content),
    );
    if (widget.embedded) return body;
    return NipaplayWindowScaffold(
      maxWidth: MediaQuery.of(context).size.width >= 1200
          ? 980
          : globals.DialogSizes.getDialogWidth(
              MediaQuery.of(context).size.width,
            ),
      maxHeightFactor: 0.9,
      onClose: () => Navigator.of(context).maybePop(),
      backgroundColor: _surfaceColor,
      child: body,
    );
  }
}

class _FileItem {
  final String path;
  final String displayName;
  bool selected = true;
  final String? episodeNumber;
  final int? sortKey;

  _FileItem({
    required this.path,
    required this.displayName,
  })  : episodeNumber = _extractEpisodeNumber(displayName),
        sortKey = _generateSortKey(_extractEpisodeNumber(displayName));

  static String? _extractEpisodeNumber(String fileName) {
    // 匹配常见的剧集格式：[01], 01, E01, EP01, 第01话, 第1话, SP/SP1, OVA/OVA01, OAD/OAD01, Special, Lite等
    final patterns = [
      // 特殊格式：[SP01], SP01, OVA/OVA01, OAD/OAD01, Special, Lite
      RegExp(r'\[(SP\d*|OVA\d*|OAD\d*|Special|Lite)\]', caseSensitive: false),
      RegExp(r'[\s_\-\.](SP\d*|OVA\d*|OAD\d*|Special|Lite)[\s_\-\.\]]',
          caseSensitive: false),
      // 标准数字格式：[01], 01, 1
      RegExp(r'\[(\d{1,3})\]'),
      RegExp(r'[\s_\-\.](\d{1,3})[\s_\-\.\]]'),
      // 带前缀格式：E01, EP01, e01, ep01
      RegExp(r'[\s_\-\.]([Ee][Pp]?)(\d{1,3})[\s_\-\.\]]'),
      // 中文格式：第01话, 第1话
      RegExp(r'第(\d{1,3})话'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fileName);
      if (match != null) {
        // 对于带前缀的格式，只返回数字部分
        if (match.groupCount > 1 && match.group(2) != null) {
          return match.group(2);
        }
        return match.group(1);
      }
    }
    return null;
  }

  static int? _generateSortKey(String? episodeNumber) {
    if (episodeNumber == null) return null;

    // 处理特殊剧集号
    if (episodeNumber.toLowerCase().startsWith('sp')) {
      final numPart = episodeNumber.substring(2);
      final num = int.tryParse(numPart) ?? 0;
      return 1000 + num; // SP剧集排在普通剧集之后
    }
    if (episodeNumber.toLowerCase().startsWith('ova')) {
      final numPart = episodeNumber.substring(3);
      final num = int.tryParse(numPart) ?? 0;
      return 2000 + num; // OVA排在SP之后
    }
    if (episodeNumber.toLowerCase().startsWith('oad')) {
      final numPart = episodeNumber.substring(3);
      final num = int.tryParse(numPart) ?? 0;
      return 3000 + num; // OAD排在OVA之后
    }
    if (episodeNumber.toLowerCase() == 'lite') {
      return 4000; // Lite排在OAD之后
    }
    if (episodeNumber.toLowerCase() == 'special') {
      return 5000; // Special排在Lite之后
    }
    // 处理普通数字剧集号
    final num = int.tryParse(episodeNumber);
    return num;
  }
}

class _EpisodeItem {
  final int episodeId;
  final String episodeTitle;
  final int? episodeNumber;

  _EpisodeItem({
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber,
  });
}
