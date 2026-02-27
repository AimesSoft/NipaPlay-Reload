import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoManualDanmakuSheet extends StatefulWidget {
  const CupertinoManualDanmakuSheet({super.key, this.initialVideoTitle});

  final String? initialVideoTitle;

  @override
  State<CupertinoManualDanmakuSheet> createState() =>
      _CupertinoManualDanmakuSheetState();
}

class _CupertinoManualDanmakuSheetState
    extends State<CupertinoManualDanmakuSheet> {
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

  @override
  void initState() {
    super.initState();
    if (widget.initialVideoTitle != null) {
      _searchController.text = widget.initialVideoTitle!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _searchMessage = '请输入搜索关键词';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _currentMatches.clear();
    });

    try {
      final results = await _searchAnime(keyword);
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
        _currentMatches.clear();
      });
    }
  }

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

    FocusScope.of(context).unfocus();

    setState(() {
      _selectedAnime = anime;
      _showEpisodesView = true;
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _currentEpisodes.clear();
      _selectedEpisode = null;
    });

    try {
      final animeId = anime['animeId'] is int
          ? anime['animeId']
          : int.tryParse(anime['animeId'].toString());
      if (animeId == null) {
        if (!mounted) return;
        setState(() {
          _isLoadingEpisodes = false;
          _episodesMessage = '错误：动画ID格式不正确。';
        });
        return;
      }

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
              DandanplayService.appId, timestamp, apiPath, appSecret),
          'X-Timestamp': '$timestamp',
        },
      );

      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['bangumi'] != null) {
          final bangumi = data['bangumi'];

          if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
            final episodes =
                List<Map<String, dynamic>>.from(bangumi['episodes']);
            setState(() {
              _currentEpisodes = episodes;
              _episodesMessage = episodes.isEmpty ? '该动画暂无剧集信息' : '';
            });
          } else {
            setState(() {
              _episodesMessage = '该动画暂无剧集信息';
            });
          }
        } else {
          setState(() {
            _episodesMessage =
                '获取动画信息失败: ${data['errorMessage'] ?? '未知错误'}';
          });
        }
      } else {
        setState(() {
          _episodesMessage = '加载剧集失败: HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '加载剧集时出错: $e';
      });
    }
  }

  void _backToAnimeSelection() {
    setState(() {
      _showEpisodesView = false;
      _selectedAnime = null;
      _selectedEpisode = null;
      _currentEpisodes.clear();
      _episodesMessage = '';
    });
  }

  void _completeSelection() {
    final Map<String, dynamic> result = {};

    if (_selectedAnime != null) {
      result['anime'] = _selectedAnime;
      result['animeId'] = _selectedAnime!['animeId'];
      result['animeTitle'] = _selectedAnime!['animeTitle'];

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
      }
    }

    Navigator.of(context).pop(result);
  }

  Widget _buildHeader(BuildContext context, double topSpacing) {
    final Color subtitleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final title = _showEpisodesView ? '选择剧集' : '搜索动画';
    final subtitle =
        _showEpisodesView ? '选择对应剧集以匹配弹幕' : '输入动画名称搜索弹幕';

    final List<Widget> children = [];
    if (_showEpisodesView) {
      children.add(
        CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: _backToAnimeSelection,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.chevron_back,
                size: 18,
                color: CupertinoTheme.of(context).primaryColor,
              ),
              const SizedBox(width: 4),
              Text(
                '返回搜索',
                style: TextStyle(
                  color: CupertinoTheme.of(context).primaryColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
      children.add(const SizedBox(height: 6));
    }

    children.add(
      Text(
        title,
        style: CupertinoTheme.of(context)
            .textTheme
            .navTitleTextStyle
            .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
    children.add(const SizedBox(height: 4));
    children.add(
      Text(
        subtitle,
        style: CupertinoTheme.of(context)
            .textTheme
            .textStyle
            .copyWith(fontSize: 13, color: subtitleColor),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: '输入动画名称',
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minSize: 0,
            onPressed: _isSearching ? null : _performSearch,
            child: _isSearching
                ? const CupertinoActivityIndicator(radius: 8)
                : const Text(
                    '搜索',
                    style: TextStyle(color: CupertinoColors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context, String message,
      {bool isError = false}) {
    final Color color = CupertinoDynamicColor.resolve(
      isError ? CupertinoColors.systemRed : CupertinoColors.secondaryLabel,
      context,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String title,
      {String? subtitle}) {
    final Color iconColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey,
      context,
    );
    final Color subtitleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.tray, size: 36, color: iconColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 13, color: subtitleColor),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context, String title) {
    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 13, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimeResultsSection(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      children: _currentMatches.map((match) {
        final title = match['animeTitle']?.toString() ?? '未知动画';
        final typeDescription =
            match['typeDescription']?.toString() ?? '未知类型';
        final episodeCount = match['episodeCount'] ?? 0;

        return CupertinoListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('$typeDescription · ${episodeCount}集'),
          trailing: const Icon(CupertinoIcons.chevron_forward),
          onTap: () => _loadAnimeEpisodes(match),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedAnimeSection(BuildContext context) {
    final title = _selectedAnime?['animeTitle']?.toString() ?? '未知动画';
    final typeDescription =
        _selectedAnime?['typeDescription']?.toString() ?? '未知类型';
    final episodeCount = _selectedAnime?['episodeCount'] ?? 0;

    return CupertinoListSection.insetGrouped(
      header: const Text('已选动画'),
      children: [
        CupertinoListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('$typeDescription · ${episodeCount}集'),
        ),
      ],
    );
  }

  Widget _buildEpisodesSection(BuildContext context) {
    final Color accentColor = CupertinoTheme.of(context).primaryColor;
    final Color selectedBackground = accentColor.withOpacity(0.12);

    return CupertinoListSection.insetGrouped(
      header: const Text('剧集列表'),
      children: _currentEpisodes.map((episode) {
        final title = episode['episodeTitle']?.toString() ??
            '第${episode['episodeId'] ?? ''}话';
        final bool isSelected = _selectedEpisode != null &&
            _selectedEpisode!['episodeId'] == episode['episodeId'];

        return CupertinoListTile(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: isSelected ? selectedBackground : null,
          trailing: isSelected
              ? Icon(CupertinoIcons.check_mark, color: accentColor)
              : null,
          onTap: () {
            setState(() {
              _selectedEpisode = episode;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildEpisodeHint(BuildContext context) {
    final Color accentColor = CupertinoTheme.of(context).primaryColor;
    final Color secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final String text = _selectedEpisode == null
        ? '请选择一个剧集来匹配弹幕'
        : '已选择剧集，可确认匹配';
    final Color textColor =
        _selectedEpisode == null ? secondaryColor : accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: textColor),
      ),
    );
  }

  Widget _buildConfirmButton(BuildContext context) {
    final bool canConfirm = _currentEpisodes.isNotEmpty && !_isLoadingEpisodes;
    final String label = _selectedEpisode != null ? '确认匹配' : '使用第一集';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: CupertinoButton.filled(
        onPressed: canConfirm ? _completeSelection : null,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        final slivers = <Widget>[
          SliverToBoxAdapter(child: _buildHeader(context, topSpacing)),
        ];

        if (!_showEpisodesView) {
          slivers.add(SliverToBoxAdapter(child: _buildSearchBar(context)));

          if (_searchMessage.isNotEmpty) {
            final bool isError = _searchMessage.contains('出错');
            slivers.add(
              SliverToBoxAdapter(
                child: _buildMessage(
                  context,
                  _searchMessage,
                  isError: isError,
                ),
              ),
            );
          }

          if (_isSearching) {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildLoadingState(context, '正在搜索...'),
              ),
            );
          } else if (_currentMatches.isEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildEmptyState(
                  context,
                  '暂无搜索结果',
                  subtitle: '请尝试更换关键词',
                ),
              ),
            );
          } else {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildAnimeResultsSection(context),
              ),
            );
          }
        } else {
          slivers.add(
            SliverToBoxAdapter(
              child: _buildSelectedAnimeSection(context),
            ),
          );

          if (_episodesMessage.isNotEmpty) {
            final bool isError = _episodesMessage.contains('出错') ||
                _episodesMessage.contains('失败');
            slivers.add(
              SliverToBoxAdapter(
                child: _buildMessage(
                  context,
                  _episodesMessage,
                  isError: isError,
                ),
              ),
            );
          }

          if (_isLoadingEpisodes) {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildLoadingState(context, '正在加载剧集...'),
              ),
            );
          } else if (_currentEpisodes.isEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildEmptyState(context, '暂无剧集'),
              ),
            );
          } else {
            slivers.add(
              SliverToBoxAdapter(
                child: _buildEpisodesSection(context),
              ),
            );
            slivers.add(
              SliverToBoxAdapter(child: _buildEpisodeHint(context)),
            );
          }

          slivers.add(
            SliverToBoxAdapter(child: _buildConfirmButton(context)),
          );
        }

        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(height: 16 + bottomPadding),
          ),
        );

        return slivers;
      },
    );
  }
}
