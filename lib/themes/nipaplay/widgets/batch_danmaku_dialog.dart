import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/global_hotkey_manager.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:path/path.dart' as p;

class BatchDanmakuMatchDialog extends StatefulWidget {
  final List<String> filePaths;
  final String? initialSearchKeyword;

  const BatchDanmakuMatchDialog({
    super.key,
    required this.filePaths,
    this.initialSearchKeyword,
  });

  @override
  State<BatchDanmakuMatchDialog> createState() => _BatchDanmakuMatchDialogState();
}

class _BatchDanmakuMatchDialogState extends State<BatchDanmakuMatchDialog>
    with GlobalHotkeyManagerMixin {
  static const double _panelHeaderHeight = 32;
  static const double _listDividerWidth = 0.8;
  static const double _rowIndexWidth = 32;

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
        _searchMessage = results.isEmpty ? '没有找到匹配的动画' : '找到 ${results.length} 个结果';
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

  BorderSide _listDividerSide({required bool isDragging}) {
    return BorderSide(
      color:
          isDragging ? Colors.black.withOpacity(0.15) : Colors.white.withOpacity(0.25),
      width: _listDividerWidth,
    );
  }

  BoxDecoration _listContainerDecoration() {
    final side = _listDividerSide(isDragging: false);
    return BoxDecoration(
      border: Border(
        top: side,
        bottom: side,
      ),
    );
  }

  Widget _buildRowIndexText(int index, {required bool isDragging}) {
    final textColor =
        isDragging ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.75);
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
    final textColor = isDragging ? Colors.black : Colors.white;
    final iconColor = isDragging ? Colors.black54 : Colors.white.withOpacity(0.7);
    final checkboxSide = BorderSide(
      color: isDragging ? Colors.black54 : Colors.white.withOpacity(0.6),
      width: 1,
    );
    final dividerSide = _listDividerSide(isDragging: isDragging);

    return Container(
      key: ValueKey(item.path),
      decoration: BoxDecoration(
        color: isDragging ? Colors.white : Colors.transparent,
        border: showBottomDivider ? Border(bottom: dividerSide) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Checkbox(
          value: item.selected,
          onChanged: isDragging
              ? null
              : (value) {
                  setState(() {
                    item.selected = value ?? true;
                  });
                },
          checkColor: isDragging ? Colors.white : Colors.white,
          activeColor: isDragging ? Colors.black : Colors.white.withOpacity(0.25),
          side: checkboxSide,
        ),
        title: Text(
          item.displayName,
          style: TextStyle(color: textColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              enabled: !isDragging,
              child: Icon(Icons.drag_handle, color: iconColor),
            ),
            const SizedBox(width: 6),
            _buildRowIndexText(index, isDragging: isDragging),
          ],
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

    final textColor = isDragging ? Colors.black : Colors.white;
    final iconColor = isDragging ? Colors.black54 : Colors.white.withOpacity(0.7);
    final checkboxSide = BorderSide(
      color: isDragging ? Colors.black54 : Colors.white.withOpacity(0.6),
      width: 1,
    );
    final dividerSide = _listDividerSide(isDragging: isDragging);

    return Container(
      key: ValueKey(episode.episodeId),
      decoration: BoxDecoration(
        color: isDragging ? Colors.white : Colors.transparent,
        border: showBottomDivider ? Border(bottom: dividerSide) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Checkbox(
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
          checkColor: isDragging ? Colors.white : Colors.white,
          activeColor: isDragging ? Colors.black : Colors.white.withOpacity(0.25),
          side: checkboxSide,
        ),
        title: Text(
          label,
          style: TextStyle(color: textColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              enabled: !isDragging,
              child: Icon(Icons.drag_handle, color: iconColor),
            ),
            const SizedBox(width: 6),
            _buildRowIndexText(index, isDragging: isDragging),
          ],
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
    final dividerSide = _listDividerSide(isDragging: false);

    return Container(
      decoration: BoxDecoration(
        border: showBottomDivider ? Border(bottom: dividerSide) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: animeId.isNotEmpty
            ? Text('ID: $animeId',
                style: TextStyle(color: Colors.white.withOpacity(0.7)))
            : null,
        trailing: _buildRowIndexText(index, isDragging: false),
        onTap: () => _selectAnime(anime),
      ),
    );
  }

  Widget _buildTitleBar(bool isRealPhone) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            '批量匹配弹幕',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: isRealPhone ? 16 : 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white70),
          tooltip: '关闭',
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
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '搜索番剧（右侧先选番剧再选话数）',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              isDense: true,
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _isSearching ? null : _performSearch,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.2),
            foregroundColor: Colors.white,
          ),
          child: _isSearching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('搜索'),
        ),
      ],
    );
  }

  Widget _buildFilesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _panelHeaderHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  '左侧：本地文件（可拖拽排序）',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '已选 $_selectedFileCount/${_files.length}',
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: _listContainerDecoration(),
            child: ReorderableListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _files.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                final item = _files[index];
                return Material(
                  color: Colors.transparent,
                  elevation: 8,
                  shadowColor: Colors.black26,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          height: _panelHeaderHeight,
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              '右侧：搜索结果（点击选择番剧）',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: _listContainerDecoration(),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              primary: false,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final anime = _searchResults[index];
                final showBottomDivider = index != _searchResults.length - 1;
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
    final animeTitle = _selectedAnime?['animeTitle']?.toString() ?? '';
    final selectedEpisodesCount = _selectedEpisodesInOrder.length;
    final mismatch =
        _selectedFileCount != selectedEpisodesCount && _selectedAnime != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _panelHeaderHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '右侧：$animeTitle',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '已选 $selectedEpisodesCount/${_episodes.length}',
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<_EpisodesMenuAction>(
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  switch (action) {
                    case _EpisodesMenuAction.changeAnime:
                      setState(() {
                        _selectedAnime = null;
                        _episodes.clear();
                        _selectedEpisodeIds.clear();
                        _episodesMessage = '';
                      });
                      return;
                    case _EpisodesMenuAction.selectAll:
                      _toggleSelectAllEpisodes(true);
                      return;
                    case _EpisodesMenuAction.clearAll:
                      _toggleSelectAllEpisodes(false);
                      return;
                    case _EpisodesMenuAction.selectFirstN:
                      _autoSelectEpisodesToMatchFileCount();
                      return;
                  }
                },
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<_EpisodesMenuAction>>[
                    const PopupMenuItem(
                      value: _EpisodesMenuAction.changeAnime,
                      child: Text('更换番剧'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _EpisodesMenuAction.selectAll,
                      child: Text('全选'),
                    ),
                    const PopupMenuItem(
                      value: _EpisodesMenuAction.clearAll,
                      child: Text('清空'),
                    ),
                  ];
                  if (_selectedFileCount > 0) {
                    items.add(
                      PopupMenuItem(
                        value: _EpisodesMenuAction.selectFirstN,
                        child: Text('选前$_selectedFileCount话'),
                      ),
                    );
                  }
                  return items;
                },
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (_isLoadingEpisodes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_episodesMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _episodesMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.8)),
            ),
          ),
        if (!_isLoadingEpisodes)
          Expanded(
            child: Container(
              decoration: _listContainerDecoration(),
              child: ReorderableListView.builder(
                padding: EdgeInsets.zero,
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
              ),
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
    final window = WidgetsBinding.instance.window;
    final size = window.physicalSize / window.devicePixelRatio;
    final shortestSide = size.width < size.height ? size.width : size.height;
    final bool isRealPhone = isPhone && shortestSide < 600;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.translucent,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.of(context).size.width * 0.92,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                      offset: const Offset(1, 1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildTitleBar(isRealPhone),
                    const SizedBox(height: 12),
                    _buildSearchBar(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildFilesPanel()),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _selectedAnime == null
                                ? _buildAnimeSearchResultsPanel()
                                : _buildEpisodesPanel(),
                          ),
                        ],
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
                            style: TextStyle(color: Colors.white.withOpacity(0.8)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _canConfirm ? _confirmAndClose : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.25),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('一键匹配'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
