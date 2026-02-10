import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/global_hotkey_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class BatchDanmakuMatchDialog extends StatefulWidget {
  final List<String> filePaths;
  final String? initialSearchKeyword;

  const BatchDanmakuMatchDialog({
    super.key,
    required this.filePaths,
    this.initialSearchKeyword,
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
  State<BatchDanmakuMatchDialog> createState() => _BatchDanmakuMatchDialogState();
}

class _BatchDanmakuMatchDialogState extends State<BatchDanmakuMatchDialog>
    with GlobalHotkeyManagerMixin {
  static const double _rowIndexWidth = 32;
  static const Color _accentColor = Color(0xFFFF2E55);

  final TextEditingController _searchController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _files = widget.filePaths
        .map((path) => _FileItem(path: path, displayName: p.basename(path)))
        .toList(growable: true);
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

  ButtonStyle _primaryButtonStyle() {
    return ButtonStyle(
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return _accentColor.withOpacity(0.5);
        }
        return _accentColor;
      }),
      foregroundColor: MaterialStateProperty.all(Colors.white),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      minimumSize: MaterialStateProperty.all(const Size(96, 44)),
      elevation: MaterialStateProperty.all(0),
      shadowColor: MaterialStateProperty.all(Colors.transparent),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

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
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      final baseUrl = await DandanplayService.getApiBaseUrl();
      final url = '$baseUrl$apiPath?keyword=${Uri.encodeComponent(keyword)}';

      final response = await http.get(
        WebRemoteAccessService.proxyUri(Uri.parse(url)),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId,
            timestamp,
            apiPath,
            appSecret,
          ),
          'X-Timestamp': '$timestamp',
        },
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _isSearching = false;
          _searchMessage = '搜索失败: HTTP ${response.statusCode}';
          _searchResults = [];
        });
        return;
      }

      final data = json.decode(response.body);
      final results = (data is Map<String, dynamic> && data['animes'] is List)
          ? List<Map<String, dynamic>>.from(data['animes'] as List)
          : <Map<String, dynamic>>[];

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
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      final baseUrl = await DandanplayService.getApiBaseUrl();
      final url = '$baseUrl$apiPath';

      final response = await http.get(
        WebRemoteAccessService.proxyUri(Uri.parse(url)),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId,
            timestamp,
            apiPath,
            appSecret,
          ),
          'X-Timestamp': '$timestamp',
        },
      );

      if (!mounted) return;

      setState(() {
        _isLoadingEpisodes = false;
      });

      if (response.statusCode != 200) {
        setState(() {
          _episodesMessage = '加载剧集失败: HTTP ${response.statusCode}';
        });
        return;
      }

      final data = json.decode(response.body);
      final rawEpisodes = (data is Map<String, dynamic> &&
              data['success'] == true &&
              data['bangumi'] is Map<String, dynamic>)
          ? (data['bangumi'] as Map<String, dynamic>)['episodes']
          : (data is Map<String, dynamic> ? data['episodes'] : null);

      final parsedEpisodes = <_EpisodeItem>[];
      if (rawEpisodes is List) {
        for (final entry in rawEpisodes) {
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry);
          final episodeId = _tryParsePositiveInt(map['episodeId']);
          if (episodeId == null) continue;
          parsedEpisodes.add(
            _EpisodeItem(
              episodeId: episodeId,
              episodeTitle: map['episodeTitle']?.toString().trim() ?? '未命名剧集',
              episodeNumber: _tryParsePositiveInt(map['episodeNumber']),
            ),
          );
        }
      }

      setState(() {
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

  void _toggleSelectAllEpisodes(bool selectAll) {
    if (_episodes.isEmpty) return;
    setState(() {
      if (!selectAll) {
        _selectedEpisodeIds.clear();
        return;
      }
      _selectedEpisodeIds
        ..clear()
        ..addAll(_episodes.map((e) => e.episodeId));
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

    Navigator.of(context).pop({
      'animeId': animeId,
      'animeTitle': animeTitle,
      'mappings': mappings,
    });
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
    final checkboxSide = BorderSide(color: _borderColor, width: 1);
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
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
              Checkbox(
                value: item.selected,
                onChanged: isDragging
                    ? null
                    : (value) {
                        setState(() {
                          item.selected = value ?? true;
                        });
                      },
                checkColor: Colors.white,
                activeColor: _accentColor,
                side: checkboxSide,
              ),
              Expanded(
                child: Text(
                  item.displayName,
                  style: TextStyle(color: textColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _buildRowIndexText(index, isDragging: isDragging),
              const SizedBox(width: 6),
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
    final checkboxSide = BorderSide(color: _borderColor, width: 1);
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
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
              Checkbox(
                value: checked,
                onChanged: isDragging
                    ? null
                    : (value) {
                        setState(() {
                          final v = value ?? false;
                          if (v) {
                            _selectedEpisodeIds.add(episode.episodeId);
                          } else {
                            _selectedEpisodeIds.remove(episode.episodeId);
                          }
                        });
                      },
                checkColor: Colors.white,
                activeColor: _accentColor,
                side: checkboxSide,
              ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: textColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _buildRowIndexText(index, isDragging: isDragging),
              const SizedBox(width: 6),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
                      const SizedBox(height: 4),
                      Text(
                        'ID: $animeId',
                        style: TextStyle(
                          color: _subTextColor,
                          fontSize: 12,
                        ),
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
          child: const Icon(
            Icons.playlist_add_check,
            color: _accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
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
              const SizedBox(height: 4),
              Text(
                '对齐本地文件与剧集顺序，一键完成匹配',
                style: TextStyle(
                  color: _subTextColor,
                  fontSize: 13,
                ),
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
          child: TextField(
            controller: _searchController,
            cursorColor: _accentColor,
            style: TextStyle(color: _textColor),
            decoration: InputDecoration(
              hintText: '搜索番剧（右侧先选番剧再选话数）',
              hintStyle: TextStyle(color: _mutedTextColor),
              prefixIcon: Icon(
                Icons.search,
                color: _mutedTextColor,
                size: 18,
              ),
              filled: true,
              fillColor: _panelAltColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accentColor),
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _isSearching ? null : _performSearch,
          style: _primaryButtonStyle(),
          child: _isSearching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('搜索'),
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
          const SizedBox(width: 6),
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
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(color: _subTextColor, fontSize: 13),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilesPanel() {
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
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: _panelDecoration(),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _files.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                final item = _files[index];
                return Material(
                  color: Colors.transparent,
                  elevation: 8,
                  shadowColor: Colors.black26,
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
        ),
      ],
    );
  }

  Widget _buildAnimeSearchResultsPanel() {
    final bool isError = _searchMessage.contains('出错');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('搜索结果'),
        if (_searchMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildStatusBanner(_searchMessage, isError: isError),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: _panelDecoration(),
            child: _isSearching
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_accentColor),
                    ),
                  )
                : _searchResults.isEmpty
                    ? _buildEmptyState('暂无搜索结果')
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        primary: false,
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
        ),
      ],
    );
  }

  Widget _buildEpisodesPanel() {
    final selectedEpisodesCount = _selectedEpisodesInOrder.length;
    final mismatch =
        _selectedFileCount != selectedEpisodesCount && _selectedAnime != null;
    final bool isError =
        _episodesMessage.contains('出错') || _episodesMessage.contains('失败');

    Widget panelContent;
    if (_isLoadingEpisodes) {
      panelContent = Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
        ),
      );
    } else if (_episodes.isEmpty) {
      panelContent = _buildEmptyState('暂无剧集');
    } else {
      panelContent = ReorderableListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _episodes.length,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          final episode = _episodes[index];
          return Material(
            color: Colors.transparent,
            elevation: 8,
            shadowColor: Colors.black26,
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
        const SizedBox(height: 8),
        if (_episodesMessage.isNotEmpty) ...[
          _buildStatusBanner(_episodesMessage, isError: isError),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Container(
            decoration: _panelDecoration(),
            child: panelContent,
          ),
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: TextSelectionTheme(
        data: _selectionTheme,
        child: NipaplayWindowScaffold(
          maxWidth: MediaQuery.of(context).size.width >= 1200
              ? 980
              : globals.DialogSizes.getDialogWidth(
                  MediaQuery.of(context).size.width,
                ),
          maxHeightFactor:
              (globals.isPhone && MediaQuery.of(context).size.shortestSide < 600)
                  ? 0.9
                  : 0.85,
          onClose: () => Navigator.of(context).maybePop(),
          backgroundColor: _surfaceColor,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildSearchBar(),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWideLayout = constraints.maxWidth >= 820;
                      final rightPanel = _selectedAnime == null
                          ? _buildAnimeSearchResultsPanel()
                          : _buildEpisodesPanel();

                      if (isWideLayout) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildFilesPanel()),
                            const SizedBox(width: 16),
                            Expanded(child: rightPanel),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Expanded(child: _buildFilesPanel()),
                          const SizedBox(height: 12),
                          Expanded(child: rightPanel),
                        ],
                      );
                    },
                  ),
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
                    ElevatedButton(
                      onPressed: _canConfirm ? _confirmAndClose : null,
                      style: _primaryButtonStyle(),
                      child: const Text('一键匹配'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileItem {
  final String path;
  final String displayName;
  bool selected;

  _FileItem({
    required this.path,
    required this.displayName,
    this.selected = true,
  });
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

enum _EpisodesMenuAction {
  changeAnime,
  selectAll,
  clearAll,
  selectFirstN,
}
