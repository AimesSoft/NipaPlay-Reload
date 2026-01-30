import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/global_hotkey_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 手动弹幕匹配对话框
///
/// 显示搜索动画和选择剧集的界面
class ManualDanmakuMatchDialog extends StatefulWidget {
  final String? initialVideoTitle;

  const ManualDanmakuMatchDialog({super.key, this.initialVideoTitle});

  @override
  State<ManualDanmakuMatchDialog> createState() =>
      _ManualDanmakuMatchDialogState();
}

class _ManualDanmakuMatchDialogState extends State<ManualDanmakuMatchDialog>
    with GlobalHotkeyManagerMixin {
  static const Color _accentColor = Color(0xFFFF2E55);

  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  bool _showEpisodesView = false;
  bool _isLoadingEpisodes = false;

  String _searchMessage = '';
  String _episodesMessage = '';

  List<Map<String, dynamic>> _currentMatches = [];
  List<Map<String, dynamic>> _currentEpisodes = [];

  Map<String, dynamic>? _selectedAnime;
  Map<String, dynamic>? _selectedEpisode;

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

  ButtonStyle _textButtonStyle({Color? baseColor}) {
    final resolvedBase = baseColor ?? _textColor;
    return ButtonStyle(
      foregroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.disabled)) {
          return _mutedTextColor;
        }
        if (states.contains(MaterialState.hovered)) {
          return _accentColor;
        }
        return resolvedBase;
      }),
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      padding: MaterialStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

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

  // 实现GlobalHotkeyManagerMixin要求的方法
  @override
  String get hotkeyDisableReason => 'manual_danmaku_dialog';

  @override
  void initState() {
    super.initState();
    debugPrint('=== ManualDanmakuMatchDialog 初始化 ===');
    if (widget.initialVideoTitle != null) {
      _searchController.text = widget.initialVideoTitle!;
    }
    // 禁用全局热键
    WidgetsBinding.instance.addPostFrameCallback((_) {
      disableHotkeys();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    // 启用全局热键
    disposeHotkeys();
    super.dispose();
  }

  /// 执行搜索
  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searchMessage = '请输入搜索关键词';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _currentMatches.clear();
    });

    try {
      final results = await _searchAnime(keyword);
      setState(() {
        _isSearching = false;
        _currentMatches = results;
        if (results.isEmpty) {
          _searchMessage = '没有找到匹配的动画';
        } else {
          _searchMessage = '找到 ${results.length} 个结果';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
        _currentMatches.clear();
      });
    }
  }

  /// 搜索动画
  Future<List<Map<String, dynamic>>> _searchAnime(String keyword) async {
    if (keyword.trim().isEmpty) {
      return [];
    }

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
              DandanplayService.appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['animes'] != null && data['animes'] is List) {
          return List<Map<String, dynamic>>.from(data['animes']);
        }
      }

      return [];
    } catch (e) {
      debugPrint('搜索动画时出错: $e');
      rethrow;
    }
  }

  /// 加载动画剧集
  Future<void> _loadAnimeEpisodes(Map<String, dynamic> anime) async {
    if (anime['animeId'] == null) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画ID为空。';
      });
      return;
    }

    if (anime['animeTitle'] == null || anime['animeTitle'].toString().isEmpty) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画标题为空。';
      });
      return;
    }

    setState(() {
      _selectedAnime = anime;
      _showEpisodesView = true;
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _currentEpisodes.clear();
      _selectedEpisode = null;
    });

    try {
      // 确保animeId是整数类型
      final animeId = anime['animeId'] is int
          ? anime['animeId']
          : int.tryParse(anime['animeId'].toString());
      if (animeId == null) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesMessage = '错误：动画ID格式不正确。';
        });
        return;
      }

      debugPrint(
          '正在加载动画剧集，animeId: $animeId, animeTitle: ${anime['animeTitle']}');

      final appSecret = await DandanplayService.getAppSecret();
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      final baseUrl = await DandanplayService.getApiBaseUrl();
      final url = '$baseUrl$apiPath';
      debugPrint('API请求URL: $url');

      final response = await http.get(
        WebRemoteAccessService.proxyUri(Uri.parse(url)),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
              DandanplayService.appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
        },
      );

      setState(() {
        _isLoadingEpisodes = false;
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 检查API是否成功
        if (data['success'] == true && data['bangumi'] != null) {
          final bangumi = data['bangumi'];

          if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
            final episodes =
                List<Map<String, dynamic>>.from(bangumi['episodes']);
            setState(() {
              _currentEpisodes = episodes;
              _episodesMessage = episodes.isEmpty ? '该动画暂无剧集信息' : '';
            });
            debugPrint('成功加载 ${episodes.length} 个剧集');
          } else {
            setState(() {
              _episodesMessage = '该动画暂无剧集信息';
            });
          }
        } else {
          setState(() {
            _episodesMessage = '获取动画信息失败: ${data['errorMessage'] ?? '未知错误'}';
          });
        }
      } else {
        setState(() {
          _episodesMessage = '加载剧集失败: HTTP ${response.statusCode}';
        });
        debugPrint('API请求失败，状态码: ${response.statusCode}，响应: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '加载剧集时出错: $e';
      });
    }
  }

  /// 返回动画选择
  void _backToAnimeSelection() {
    setState(() {
      _showEpisodesView = false;
      _selectedAnime = null;
      _selectedEpisode = null;
      _currentEpisodes.clear();
      _episodesMessage = '';
    });
  }

  /// 完成选择
  void _completeSelection() {
    Map<String, dynamic> result = {};

    if (_selectedAnime != null) {
      // 添加动画信息到结果中
      result['anime'] = _selectedAnime;
      result['animeId'] = _selectedAnime!['animeId'];
      result['animeTitle'] = _selectedAnime!['animeTitle'];

      // 确定要使用的剧集
      Map<String, dynamic>? episodeToUse;
      if (_selectedEpisode != null) {
        episodeToUse = _selectedEpisode;
      } else if (_currentEpisodes.isNotEmpty) {
        episodeToUse = _currentEpisodes.first;
      }

      if (episodeToUse != null) {
        result['episode'] = episodeToUse;
        result['episodeId'] = episodeToUse['episodeId'];
        result['episodeTitle'] = episodeToUse['episodeTitle'];
      } else {
        debugPrint('警告: 没有匹配到任何剧集信息，episodeId可能为空');
      }
    }

    Navigator.of(context).pop(result);
  }

  /// 处理ESC键事件
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        debugPrint('[ManualDanmakuDialog] ESC键被按下，关闭对话框');
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildHeader() {
    final title = _showEpisodesView ? '选择匹配的剧集' : '手动匹配弹幕';
    final subtitle = _showEpisodesView
        ? '选择对应的剧集以获取正确的弹幕'
        : '搜索动画并选择要匹配的剧集';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.subtitles,
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
                title,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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
              hintText: '输入动画名称',
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: _textColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
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

  Widget _buildAnimeItem(Map<String, dynamic> match) {
    final title = match['animeTitle'] ?? '未知动画';
    final typeDescription = match['typeDescription'] ?? '未知类型';
    final episodeCount = match['episodeCount'] ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _loadAnimeEpisodes(match),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _panelAltColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$typeDescription | ${episodeCount}集',
                      style: TextStyle(
                        color: _subTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: _mutedTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeItem(Map<String, dynamic> episode) {
    final isSelected = _selectedEpisode != null &&
        _selectedEpisode!['episodeId'] == episode['episodeId'];
    final title = episode['episodeTitle'] ?? '第${episode['episodeId']}话';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        onTap: () {
          setState(() {
            _selectedEpisode = episode;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? _accentColor.withOpacity(_isDarkMode ? 0.2 : 0.15)
                : _panelAltColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? _accentColor.withOpacity(0.6)
                  : _borderColor,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: _accentColor,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsPanel() {
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
            decoration: BoxDecoration(
              color: _panelColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: _isSearching
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                    ),
                  )
                : _currentMatches.isEmpty
                    ? _buildEmptyState('暂无搜索结果')
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _currentMatches.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final match = _currentMatches[index];
                          return _buildAnimeItem(match);
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedAnimePanel() {
    final title = _selectedAnime?['animeTitle'] ?? '未知动画';
    final typeDescription = _selectedAnime?['typeDescription'] ?? '未知类型';
    final episodeCount = _selectedAnime?['episodeCount'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已选动画',
            style: TextStyle(color: _subTextColor, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            '$typeDescription | ${episodeCount}集',
            style: TextStyle(color: _mutedTextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesPanel() {
    final bool isError =
        _episodesMessage.contains('出错') || _episodesMessage.contains('失败');
    final hintText = _selectedEpisode == null
        ? '请选择一个剧集来匹配弹幕'
        : '已选择剧集，可确认匹配';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('剧集列表'),
        if (_episodesMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildStatusBanner(_episodesMessage, isError: isError),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _panelColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: _isLoadingEpisodes
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                    ),
                  )
                : _currentEpisodes.isEmpty
                    ? _buildEmptyState('暂无剧集')
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _currentEpisodes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final episode = _currentEpisodes[index];
                          return _buildEpisodeItem(episode);
                        },
                      ),
          ),
        ),
        if (_currentEpisodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            hintText,
            style: TextStyle(
              color:
                  _selectedEpisode == null ? _subTextColor : _accentColor,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEpisodesContent(bool isWideLayout) {
    if (isWideLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            child: _buildSelectedAnimePanel(),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildEpisodesPanel()),
        ],
      );
    }

    return Column(
      children: [
        _buildSelectedAnimePanel(),
        const SizedBox(height: 12),
        Expanded(child: _buildEpisodesPanel()),
      ],
    );
  }

  Widget _buildActionButtons() {
    final canConfirm = _currentEpisodes.isNotEmpty && !_isLoadingEpisodes;
    final confirmText = _selectedEpisode != null ? '确认匹配' : '使用第一集';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _backToAnimeSelection,
          style: _textButtonStyle(),
          child: const Text('返回搜索'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: canConfirm ? _completeSelection : null,
          style: _primaryButtonStyle(),
          child: Text(confirmText),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width >= 960
        ? 900.0
        : globals.DialogSizes.getDialogWidth(screenSize.width);
    final maxHeightFactor = (globals.isPhone && screenSize.shortestSide < 600)
        ? 0.9
        : 0.85;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: TextSelectionTheme(
        data: _selectionTheme,
        child: NipaplayWindowScaffold(
          maxWidth: dialogWidth,
          maxHeightFactor: maxHeightFactor,
          onClose: () => Navigator.of(context).maybePop(),
          backgroundColor: _surfaceColor,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboardHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                if (!_showEpisodesView) ...[
                  _buildSearchBar(),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWideLayout = constraints.maxWidth >= 720;
                      return _showEpisodesView
                          ? _buildEpisodesContent(isWideLayout)
                          : _buildResultsPanel();
                    },
                  ),
                ),
                if (_showEpisodesView) ...[
                  const SizedBox(height: 12),
                  _buildActionButtons(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
