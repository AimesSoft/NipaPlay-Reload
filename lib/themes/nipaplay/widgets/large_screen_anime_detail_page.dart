import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_home_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_input_controls.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_top_status_overlay.dart';

const double _kLargeScreenEpisodeCardWidth = 250;
const double _kLargeScreenEpisodeCardGap = 10;
const double _kLargeScreenEpisodeRailHeight = 172;

class NipaplayLargeScreenAnimeDetailPage extends StatefulWidget {
  const NipaplayLargeScreenAnimeDetailPage({
    super.key,
    required this.animeId,
    this.sharedSummary,
    this.sharedEpisodeLoader,
    this.sharedEpisodeBuilder,
    this.sharedSourceLabel,
  });

  final int animeId;
  final SharedRemoteAnimeSummary? sharedSummary;
  final Future<List<SharedRemoteEpisode>> Function()? sharedEpisodeLoader;
  final PlayableItem Function(SharedRemoteEpisode episode)? sharedEpisodeBuilder;
  final String? sharedSourceLabel;

  @override
  State<NipaplayLargeScreenAnimeDetailPage> createState() =>
      _NipaplayLargeScreenAnimeDetailPageState();
}

class _NipaplayLargeScreenAnimeDetailPageState
    extends State<NipaplayLargeScreenAnimeDetailPage> {
  final FocusNode _inputFocusNode = FocusNode(
    debugLabel: 'large_screen_anime_detail_input',
  );
  final FocusNode _closeFocusNode = FocusNode(
    debugLabel: 'large_screen_anime_detail_close',
  );
  final FocusNode _favoriteFocusNode = FocusNode(
    debugLabel: 'large_screen_anime_detail_favorite',
  );
  final FocusNode _sortFocusNode = FocusNode(
    debugLabel: 'large_screen_anime_detail_sort',
  );
  final ScrollController _episodeScrollController = ScrollController();

  List<FocusNode> _episodeFocusNodes = <FocusNode>[];

  BangumiAnime? _anime;
  bool _isLoading = true;
  String? _error;

  bool _isEpisodeListReversed = false;
  bool _isEpisodeAreaActive = false;
  int _selectedControlIndex = 0;
  int _selectedEpisodeIndex = 0;

  final Map<int, WatchHistoryItem?> _episodeHistoryMap =
      <int, WatchHistoryItem?>{};
  final Map<int, bool> _dandanplayWatchStatus = <int, bool>{};

  final Map<int, SharedRemoteEpisode> _sharedEpisodeMap =
      <int, SharedRemoteEpisode>{};
  final Map<int, PlayableItem> _sharedPlayableMap = <int, PlayableItem>{};

  bool _isLoadingSharedEpisodes = false;
  String? _sharedEpisodesError;
  bool _isFavorited = false;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocusNode.requestFocus();
    });
    _loadPageData();
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKeyEvent);
    _disposeEpisodeFocusNodes();
    _episodeScrollController.dispose();
    _inputFocusNode.dispose();
    _closeFocusNode.dispose();
    _favoriteFocusNode.dispose();
    _sortFocusNode.dispose();
    super.dispose();
  }

  List<EpisodeData> get _displayEpisodes {
    final episodes = _anime?.episodeList ?? const <EpisodeData>[];
    if (_isEpisodeListReversed) {
      return episodes.reversed.toList(growable: false);
    }
    return episodes;
  }

  List<FocusNode> get _controlFocusNodes {
    if (DandanplayService.isLoggedIn) {
      return <FocusNode>[_closeFocusNode, _favoriteFocusNode, _sortFocusNode];
    }
    return <FocusNode>[_closeFocusNode, _sortFocusNode];
  }

  int get _sortControlIndex => _controlFocusNodes.length - 1;

  int _clampInt(int value, int min, int max) {
    if (max < min) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  String _coverImageUrl(BangumiAnime anime) {
    String imageUrl = widget.sharedSummary?.imageUrl ?? anime.imageUrl;
    if (kIsWeb) {
      imageUrl = WebRemoteAccessService.imageProxyUrl(imageUrl) ?? imageUrl;
    }
    return imageUrl;
  }

  String _plainSummary(String? raw) {
    return (raw ?? '暂无简介')
        .replaceAll('<br>', ' ')
        .replaceAll('<br/>', ' ')
        .replaceAll('<br />', ' ')
        .replaceAll('```', '')
        .trim();
  }

  void _disposeEpisodeFocusNodes() {
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes = <FocusNode>[];
  }

  void _rebuildEpisodeFocusNodes({int? keepEpisodeId}) {
    _disposeEpisodeFocusNodes();
    final episodes = _displayEpisodes;
    _episodeFocusNodes = List<FocusNode>.generate(
      episodes.length,
      (index) => FocusNode(
        debugLabel: 'large_screen_anime_detail_episode_${episodes[index].id}',
      ),
      growable: false,
    );

    if (episodes.isEmpty) {
      _selectedEpisodeIndex = 0;
      _isEpisodeAreaActive = false;
      return;
    }

    if (keepEpisodeId != null) {
      final matchedIndex = episodes.indexWhere((e) => e.id == keepEpisodeId);
      if (matchedIndex >= 0) {
        _selectedEpisodeIndex = matchedIndex;
      }
    }
    _selectedEpisodeIndex = _clampInt(
      _selectedEpisodeIndex,
      0,
      episodes.length - 1,
    );
  }

  Future<void> _loadPageData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _anime = null;
      _episodeHistoryMap.clear();
      _dandanplayWatchStatus.clear();
    });

    try {
      final anime = await _fetchAnimeDetails();
      if (!mounted) return;

      setState(() {
        _anime = anime;
        _isLoading = false;
      });

      final selectedEpisodeId = _currentSelectedEpisodeId();
      _rebuildEpisodeFocusNodes(keepEpisodeId: selectedEpisodeId);

      await Future.wait<void>(<Future<void>>[
        _loadEpisodeHistories(anime),
        _loadDandanplayUserState(anime),
        _loadSharedEpisodes(),
      ]);

      if (!mounted) return;
      _selectedControlIndex = _clampInt(
        _selectedControlIndex,
        0,
        _controlFocusNodes.length - 1,
      );
      _requestCurrentSelectionFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      _requestControlFocus(0);
    }
  }

  Future<BangumiAnime> _fetchAnimeDetails() async {
    if (kIsWeb) {
      final apiUri =
          WebRemoteAccessService.apiUri('/api/bangumi/detail/${widget.animeId}');
      if (apiUri == null) {
        throw Exception('未配置远程访问地址');
      }
      final response = await http.get(apiUri);
      if (response.statusCode != 200) {
        throw Exception('详情加载失败: ${response.statusCode}');
      }
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw Exception('详情数据格式错误');
      }
      return BangumiAnime.fromJson(decoded);
    }

    return BangumiService.instance.getAnimeDetails(widget.animeId);
  }

  Future<void> _loadEpisodeHistories(BangumiAnime anime) async {
    final episodes = anime.episodeList ?? const <EpisodeData>[];
    if (episodes.isEmpty) {
      if (!mounted) return;
      setState(() {
        _episodeHistoryMap.clear();
      });
      return;
    }

    final futures = episodes.map((episode) async {
      final history = await WatchHistoryManager.getHistoryItemByEpisode(
        anime.id,
        episode.id,
      );
      return MapEntry<int, WatchHistoryItem?>(episode.id, history);
    }).toList(growable: false);

    final result = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _episodeHistoryMap
        ..clear()
        ..addEntries(result);
    });
  }

  Future<void> _loadDandanplayUserState(BangumiAnime anime) async {
    if (!DandanplayService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _dandanplayWatchStatus.clear();
        _isFavorited = false;
      });
      return;
    }

    final episodes = anime.episodeList ?? const <EpisodeData>[];
    final episodeIds = episodes
        .where((episode) => episode.id > 0)
        .map((episode) => episode.id)
        .toList(growable: false);

    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        episodeIds.isEmpty
            ? Future<Map<int, bool>>.value(<int, bool>{})
            : DandanplayService.getEpisodesWatchStatus(episodeIds),
        DandanplayService.isAnimeFavorited(anime.id),
      ]);

      if (!mounted) return;
      setState(() {
        _dandanplayWatchStatus
          ..clear()
          ..addAll((results[0] as Map<int, bool>));
        _isFavorited = results[1] as bool;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dandanplayWatchStatus.clear();
      });
    }
  }

  Future<void> _loadSharedEpisodes() async {
    if (widget.sharedEpisodeLoader == null || widget.sharedEpisodeBuilder == null) {
      return;
    }

    setState(() {
      _isLoadingSharedEpisodes = true;
      _sharedEpisodesError = null;
      _sharedEpisodeMap.clear();
      _sharedPlayableMap.clear();
    });

    try {
      final episodes = await widget.sharedEpisodeLoader!.call();
      if (!mounted) return;
      setState(() {
        for (final episode in episodes) {
          final episodeId = episode.episodeId;
          if (episodeId == null) {
            continue;
          }
          _sharedEpisodeMap[episodeId] = episode;
          _sharedPlayableMap[episodeId] = widget.sharedEpisodeBuilder!(episode);
        }
        _isLoadingSharedEpisodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sharedEpisodeMap.clear();
        _sharedPlayableMap.clear();
        _sharedEpisodesError = e.toString();
        _isLoadingSharedEpisodes = false;
      });
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, locale: const Locale('zh-Hans', 'zh')),
          duration: const Duration(milliseconds: 1800),
        ),
      );
  }

  int? _currentSelectedEpisodeId() {
    final episodes = _displayEpisodes;
    if (episodes.isEmpty) {
      return null;
    }
    final index = _clampInt(_selectedEpisodeIndex, 0, episodes.length - 1);
    return episodes[index].id;
  }

  Future<void> _toggleFavorite() async {
    final anime = _anime;
    if (anime == null) return;

    if (!DandanplayService.isLoggedIn) {
      _showMessage('请先登录弹弹play账号');
      return;
    }

    if (_isTogglingFavorite) {
      return;
    }

    setState(() {
      _isTogglingFavorite = true;
    });

    try {
      if (_isFavorited) {
        await DandanplayService.removeFavorite(anime.id);
      } else {
        await DandanplayService.addFavorite(
          animeId: anime.id,
          favoriteStatus: 'favorited',
        );
      }
      if (!mounted) return;
      setState(() {
        _isFavorited = !_isFavorited;
      });
      _showMessage(_isFavorited ? '已添加到收藏' : '已取消收藏');
    } catch (e) {
      _showMessage('收藏状态更新失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingFavorite = false;
        });
      }
    }
  }

  Future<void> _playEpisode(EpisodeData episode) async {
    final anime = _anime;
    if (anime == null) return;

    final sharedEpisode = _sharedEpisodeMap[episode.id];
    final sharedPlayable = _sharedPlayableMap[episode.id];
    final sharedPlayableAvailable =
        sharedEpisode != null && sharedPlayable != null && sharedEpisode.fileExists;

    if (sharedPlayableAvailable) {
      await PlaybackService().play(sharedPlayable);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      return;
    }

    final history = _episodeHistoryMap[episode.id];
    if (history == null || history.filePath.isEmpty) {
      _showMessage('媒体库中找不到此剧集的视频文件');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: history.filePath,
      title: anime.nameCn,
      subtitle: episode.title,
      animeId: anime.id,
      episodeId: episode.id,
      historyItem: history,
    );

    await PlaybackService().play(playableItem);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _requestControlFocus(int index) {
    final controlNodes = _controlFocusNodes;
    if (controlNodes.isEmpty) return;
    final targetIndex = _clampInt(index, 0, controlNodes.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controlNodes[targetIndex].requestFocus();
    });
  }

  void _requestEpisodeFocus(int index) {
    if (_episodeFocusNodes.isEmpty) return;
    final targetIndex = _clampInt(index, 0, _episodeFocusNodes.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _episodeFocusNodes[targetIndex].requestFocus();
    });
  }

  void _requestCurrentSelectionFocus() {
    _selectedControlIndex = _clampInt(
      _selectedControlIndex,
      0,
      _controlFocusNodes.length - 1,
    );
    if (_isEpisodeAreaActive && _episodeFocusNodes.isNotEmpty) {
      _selectedEpisodeIndex = _clampInt(
        _selectedEpisodeIndex,
        0,
        _episodeFocusNodes.length - 1,
      );
      _requestEpisodeFocus(_selectedEpisodeIndex);
      _scrollToEpisodeIndex(_selectedEpisodeIndex, animate: false);
      return;
    }
    _requestControlFocus(_selectedControlIndex);
  }

  void _scrollToEpisodeIndex(int index, {required bool animate}) {
    if (!_episodeScrollController.hasClients || _episodeFocusNodes.isEmpty) {
      return;
    }
    final targetIndex = _clampInt(index, 0, _episodeFocusNodes.length - 1);
    final targetOffset =
        targetIndex * (_kLargeScreenEpisodeCardWidth + _kLargeScreenEpisodeCardGap);

    final clamped = targetOffset.clamp(
      _episodeScrollController.position.minScrollExtent,
      _episodeScrollController.position.maxScrollExtent,
    );

    if (animate) {
      _episodeScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
      return;
    }
    _episodeScrollController.jumpTo(clamped);
  }

  void _setControlSelection(int index) {
    final max = _controlFocusNodes.length - 1;
    if (max < 0) return;
    setState(() {
      _isEpisodeAreaActive = false;
      _selectedControlIndex = _clampInt(index, 0, max);
    });
    _requestControlFocus(_selectedControlIndex);
  }

  void _setEpisodeSelection(int index, {bool animateScroll = true}) {
    if (_episodeFocusNodes.isEmpty) return;
    setState(() {
      _isEpisodeAreaActive = true;
      _selectedEpisodeIndex =
          _clampInt(index, 0, _episodeFocusNodes.length - 1);
    });
    _requestEpisodeFocus(_selectedEpisodeIndex);
    _scrollToEpisodeIndex(_selectedEpisodeIndex, animate: animateScroll);
  }

  void _moveHorizontal(int delta) {
    if (_isEpisodeAreaActive) {
      _setEpisodeSelection(_selectedEpisodeIndex + delta);
      return;
    }
    _setControlSelection(_selectedControlIndex + delta);
  }

  void _moveVertical(int delta) {
    if (_isEpisodeAreaActive) {
      if (delta < 0) {
        _setControlSelection(_selectedControlIndex);
      }
      return;
    }

    if (delta > 0 && _episodeFocusNodes.isNotEmpty) {
      _setEpisodeSelection(_selectedEpisodeIndex);
    }
  }

  void _activateControlAt(int index) {
    final hasFavorite = DandanplayService.isLoggedIn;
    if (index == 0) {
      Navigator.of(context).maybePop();
      return;
    }

    if (hasFavorite && index == 1) {
      _toggleFavorite();
      return;
    }

    _toggleEpisodeOrder();
  }

  void _activateCurrentSelection() {
    if (_isEpisodeAreaActive && _episodeFocusNodes.isNotEmpty) {
      final episodes = _displayEpisodes;
      if (episodes.isEmpty) return;
      final index = _clampInt(_selectedEpisodeIndex, 0, episodes.length - 1);
      _playEpisode(episodes[index]);
      return;
    }

    _selectedControlIndex = _clampInt(
      _selectedControlIndex,
      0,
      _controlFocusNodes.length - 1,
    );
    _activateControlAt(_selectedControlIndex);
  }

  void _toggleEpisodeOrder() {
    final selectedEpisodeId = _currentSelectedEpisodeId();
    setState(() {
      _isEpisodeListReversed = !_isEpisodeListReversed;
    });
    _rebuildEpisodeFocusNodes(keepEpisodeId: selectedEpisodeId);
    if (_isEpisodeAreaActive && _episodeFocusNodes.isNotEmpty) {
      _requestEpisodeFocus(_selectedEpisodeIndex);
      _scrollToEpisodeIndex(_selectedEpisodeIndex, animate: false);
      return;
    }
    _requestControlFocus(_sortControlIndex);
  }

  bool _isCurrentRouteActive() {
    final route = ModalRoute.of(context);
    if (route == null) {
      return true;
    }
    return route.isCurrent;
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (!mounted || !_isCurrentRouteActive()) {
      return KeyEventResult.ignored;
    }
    return _handleInputCommandEvent(event);
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    return _handleInputCommandEvent(event);
  }

  KeyEventResult _handleInputCommandEvent(KeyEvent event) {
    final command = NipaplayLargeScreenInputControls.fromKeyEvent(event);
    if (command == null) {
      return KeyEventResult.ignored;
    }

    switch (command) {
      case NipaplayLargeScreenInputCommand.toggleMenu:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateLeft:
        _moveHorizontal(-1);
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateRight:
        _moveHorizontal(1);
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateUp:
        _moveVertical(-1);
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.navigateDown:
        _moveVertical(1);
        return KeyEventResult.handled;
      case NipaplayLargeScreenInputCommand.activate:
        _activateCurrentSelection();
        return KeyEventResult.handled;
    }
  }

  Widget _buildControlButton({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required int controlIndex,
    required VoidCallback onPressed,
    bool showLoading = false,
    Color? iconColor,
  }) {
    return NipaplayLargeScreenFocusableAction(
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(8),
      onActivate: () {
        _setControlSelection(controlIndex);
        onPressed();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    iconColor ?? Colors.white,
                  ),
                ),
              )
            else
              Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              locale: const Locale('zh-Hans', 'zh'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroInfoSection(BangumiAnime anime, bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final secondary = isDarkMode ? Colors.white70 : Colors.black54;
    final muted = isDarkMode ? Colors.white60 : Colors.black54;

    final imageUrl = _coverImageUrl(anime);

    final summary = _plainSummary(
      widget.sharedSummary?.summary?.isNotEmpty == true
          ? widget.sharedSummary!.summary
          : anime.summary,
    );

    final episodes = _displayEpisodes;
    final watchedCount = episodes
        .where((episode) => _dandanplayWatchStatus[episode.id] == true)
        .length;
    final playableCount = episodes.where((episode) {
      final history = _episodeHistoryMap[episode.id];
      if (history != null && history.filePath.isNotEmpty) {
        return true;
      }
      final sharedEpisode = _sharedEpisodeMap[episode.id];
      return sharedEpisode != null && sharedEpisode.fileExists;
    }).length;

    final metaLines = <String>[
      if (anime.airDate != null && anime.airDate!.isNotEmpty)
        '首播: ${anime.airDate}',
      if (anime.typeDescription != null && anime.typeDescription!.isNotEmpty)
        '类型: ${anime.typeDescription}',
      '剧集: ${episodes.length}',
      '可播放: $playableCount',
      if (DandanplayService.isLoggedIn) '已看: $watchedCount',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImageWidget(
                    imageUrl: imageUrl,
                    width: 190,
                    height: 268,
                    fit: BoxFit.cover,
                    loadMode: CachedImageLoadMode.legacy,
                  )
                : Container(
                    width: 190,
                    height: 268,
                    color: textColor.withValues(alpha: 0.08),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: muted,
                      size: 32,
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            anime.nameCn,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            anime.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              fontSize: 13,
                            ),
                          ),
                          if (widget.sharedSourceLabel != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_outlined,
                                  size: 14,
                                  color: secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.sharedSourceLabel!,
                                  style: TextStyle(
                                    color: secondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildControlButton(
                      focusNode: _closeFocusNode,
                      icon: Icons.close_rounded,
                      label: '关闭',
                      controlIndex: 0,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 6),
                    if (DandanplayService.isLoggedIn) ...[
                      _buildControlButton(
                        focusNode: _favoriteFocusNode,
                        icon: _isFavorited
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: _isFavorited ? Colors.red : null,
                        label: _isFavorited ? '已收藏' : '收藏',
                        controlIndex: 1,
                        onPressed: _toggleFavorite,
                        showLoading: _isTogglingFavorite,
                      ),
                      const SizedBox(width: 6),
                    ],
                    _buildControlButton(
                      focusNode: _sortFocusNode,
                      icon: Icons.swap_horiz_rounded,
                      label: _isEpisodeListReversed ? '倒序' : '正序',
                      controlIndex: _sortControlIndex,
                      onPressed: _toggleEpisodeOrder,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  summary,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: metaLines
                      .map(
                        (line) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: textColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: textColor.withValues(alpha: 0.14),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            line,
                            locale: const Locale('zh-Hans', 'zh'),
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                if (anime.tags != null && anime.tags!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: anime.tags!
                        .take(12)
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: textColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: textColor.withValues(alpha: 0.12),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              tag,
                              locale: const Locale('zh-Hans', 'zh'),
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.82),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard({
    required EpisodeData episode,
    required int index,
    required bool isDarkMode,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final mutedColor = isDarkMode ? Colors.white60 : Colors.black54;

    final history = _episodeHistoryMap[episode.id];
    final isWatched = _dandanplayWatchStatus[episode.id] == true;
    final sharedEpisode = _sharedEpisodeMap[episode.id];
    final hasSharedPlayable = sharedEpisode != null && sharedEpisode.fileExists;

    String progressLabel = '';
    Color progressColor = mutedColor;
    if (history != null && history.watchProgress > 0.01) {
      progressLabel = '${(history.watchProgress * 100).toStringAsFixed(0)}%';
      progressColor = isDarkMode ? Colors.orangeAccent : const Color(0xFFB45309);
    } else if (hasSharedPlayable) {
      progressLabel = '共享媒体';
      progressColor = isDarkMode ? Colors.lightBlueAccent : const Color(0xFF1565C0);
    }

    return NipaplayLargeScreenFocusableAction(
      focusNode: _episodeFocusNodes[index],
      borderRadius: BorderRadius.circular(10),
      onActivate: () {
        _setEpisodeSelection(index);
        _playEpisode(episode);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EP ${index + 1}',
              style: TextStyle(
                color: mutedColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              episode.title,
              locale: const Locale('zh-Hans', 'zh'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  isWatched
                      ? Icons.check_circle_rounded
                      : Icons.play_circle_outline_rounded,
                  size: 16,
                  color: isWatched
                      ? (isDarkMode
                          ? Colors.greenAccent
                          : const Color(0xFF2E7D32))
                      : mutedColor,
                ),
                const SizedBox(width: 6),
                if (isWatched)
                  Text(
                    '已看',
                    locale: const Locale('zh-Hans', 'zh'),
                    style: TextStyle(
                      color: isDarkMode
                          ? Colors.greenAccent
                          : const Color(0xFF2E7D32),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    '未看',
                    locale: const Locale('zh-Hans', 'zh'),
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (progressLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                progressLabel,
                locale: const Locale('zh-Hans', 'zh'),
                style: TextStyle(
                  color: progressColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeRail(BangumiAnime anime, bool isDarkMode) {
    final episodes = _displayEpisodes;
    final mutedColor = isDarkMode ? Colors.white60 : Colors.black54;

    if (_isLoadingSharedEpisodes) {
      return const SizedBox(
        height: _kLargeScreenEpisodeRailHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_sharedEpisodesError != null) {
      return SizedBox(
        height: _kLargeScreenEpisodeRailHeight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _sharedEpisodesError!,
              style: TextStyle(color: mutedColor),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (episodes.isEmpty) {
      return SizedBox(
        height: _kLargeScreenEpisodeRailHeight,
        child: Center(
          child: Text(
            '暂无剧集信息',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(color: mutedColor),
          ),
        ),
      );
    }

    return SizedBox(
      height: _kLargeScreenEpisodeRailHeight,
      child: ListView.separated(
        controller: _episodeScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: _kLargeScreenEpisodeCardGap),
        itemBuilder: (context, index) {
          return SizedBox(
            width: _kLargeScreenEpisodeCardWidth,
            child: _buildEpisodeCard(
              episode: episodes[index],
              index: index,
              isDarkMode: isDarkMode,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadedBody(BangumiAnime anime) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color dividerColor = isDarkMode ? Colors.white12 : Colors.black12;
    final episodes = _displayEpisodes;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeroInfoSection(anime, isDarkMode),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '剧集 ${episodes.length} 集',
                        locale: const Locale('zh-Hans', 'zh'),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '↑/↓ 切换区域  ←/→ 选集  Enter 播放',
                        locale: const Locale('zh-Hans', 'zh'),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white54 : Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildEpisodeRail(anime, isDarkMode),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color surfaceColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final Color dividerColor = isDark ? Colors.white12 : Colors.black12;
    final mediaPadding = MediaQuery.of(context).padding;

    final anime = _anime;
    final coverImageUrl = anime == null ? '' : _coverImageUrl(anime);

    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildControlButton(
                      focusNode: _closeFocusNode,
                      icon: Icons.refresh_rounded,
                      label: '重试',
                      controlIndex: 0,
                      onPressed: _loadPageData,
                    ),
                  ],
                ),
              )
            : _buildLoadedBody(_anime!));

    return NipaplayLargeScreenHomeScope(
      child: Focus(
        focusNode: _inputFocusNode,
        autofocus: true,
        canRequestFocus: true,
        onKeyEvent: _handleInputKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    kNipaplayLargeScreenBottomHintHeight,
                    0,
                    kNipaplayLargeScreenBottomHintHeight + mediaPadding.bottom,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      border: Border.all(color: dividerColor, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (coverImageUrl.isNotEmpty)
                          Positioned.fill(
                            child: ImageFiltered(
                              imageFilter:
                                  ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                              child: Opacity(
                                opacity: isDark ? 0.25 : 0.35,
                                child: CachedNetworkImageWidget(
                                  imageUrl: coverImageUrl,
                                  fit: BoxFit.cover,
                                  shouldCompress: false,
                                  loadMode: CachedImageLoadMode.hybrid,
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  surfaceColor.withValues(alpha: 0.12),
                                  surfaceColor.withValues(alpha: 0.42),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(child: body),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: NipaplayLargeScreenTopStatusOverlay(
                  isDarkMode: isDark,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: NipaplayLargeScreenBottomHintOverlay(
                  isDarkMode: isDark,
                  onToggleMenu: () => Navigator.of(context).maybePop(),
                  menuLabel: '返回',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
