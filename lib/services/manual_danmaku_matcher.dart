import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';

/// 手动弹幕匹配器
/// 
/// 提供手动搜索和匹配弹幕的功能，参考jellyfin_dandanplay_matcher的实现方式
class ManualDanmakuMatcher {
  static final ManualDanmakuMatcher instance = ManualDanmakuMatcher._internal();
  
  ManualDanmakuMatcher._internal();

  /// 搜索动画
  /// 
  /// 根据关键词搜索动画列表
  Future<List<Map<String, dynamic>>> searchAnime(String keyword) async {
    if (keyword.trim().isEmpty) {
      debugPrint('搜索关键词为空');
      return [];
    }

    try {
      debugPrint('开始搜索动画: $keyword');
      
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(keyword)}';
      debugPrint('搜索请求URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId, 
            timestamp, 
            apiPath, 
            appSecret
          ),
          'X-Timestamp': '$timestamp',
        },
      );
      
      debugPrint('搜索响应状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('搜索响应数据: ${json.encode(data)}');
        
        if (data['animes'] != null && data['animes'] is List) {
          final List<dynamic> animesList = data['animes'];
          final List<Map<String, dynamic>> results = [];
          
          for (var anime in animesList) {
            if (anime is Map<String, dynamic>) {
              results.add(anime);
            }
          }
          
          debugPrint('搜索到 ${results.length} 个动画结果');
          return results;
        } else {
          debugPrint('搜索响应中没有animes字段或格式错误');
          return [];
        }
      } else {
        debugPrint('搜索请求失败，状态码: ${response.statusCode}');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('搜索动画时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
      return [];
    }
  }

  /// 获取动画的剧集列表
  /// 
  /// 根据动画ID和标题获取剧集列表
  Future<List<Map<String, dynamic>>> getAnimeEpisodes(int animeId, String animeTitle) async {
    debugPrint('开始获取动画剧集列表: animeId=$animeId, title="$animeTitle"');

    if (animeTitle.isEmpty) {
      debugPrint('动画标题为空，无法获取剧集列表');
      return [];
    }

    try {
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/search/episodes';
      
      final url = 'https://api.dandanplay.net/api/v2/search/episodes?anime=${Uri.encodeComponent(animeTitle)}';
      debugPrint('剧集请求URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-AppId': DandanplayService.appId,
          'X-Signature': DandanplayService.generateSignature(
            DandanplayService.appId, 
            timestamp, 
            apiPath, 
            appSecret
          ),
          'X-Timestamp': '$timestamp',
        },
      );
      
      debugPrint('剧集列表请求状态码: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['animes'] != null && data['animes'] is List) {
          final List<dynamic> animesList = data['animes'];
          
          // 查找匹配的动画
          Map<String, dynamic>? matchedAnime;
          for (var anime in animesList) {
            if (anime is Map<String, dynamic> && anime['animeId'] == animeId) {
              matchedAnime = anime;
              break;
            }
          }
          
          if (matchedAnime != null && 
              matchedAnime['episodes'] != null && 
              matchedAnime['episodes'] is List) {
            final episodes = List<Map<String, dynamic>>.from(matchedAnime['episodes']);
            debugPrint('成功获取 ${episodes.length} 个剧集');
            return episodes;
          } else {
            debugPrint('未找到匹配的动画或剧集信息');
            return [];
          }
        } else {
          debugPrint('响应中没有animes字段');
          return [];
        }
      } else {
        debugPrint('获取剧集列表失败，状态码: ${response.statusCode}');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('获取剧集列表时出错: $e');
      debugPrint('错误堆栈: $stackTrace');
      return [];
    }
  }

  /// 显示手动匹配对话框
  /// 
  /// 显示手动搜索和选择动画/剧集的对话框
  Future<Map<String, dynamic>?> showManualMatchDialog(
    BuildContext context, {
    String? initialSearchText,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ManualDanmakuMatchDialog(
        initialSearchText: initialSearchText ?? '',
      ),
    );
    
    return result;
  }

  /// 预加载弹幕数据（异步执行，不等待结果）
  Future<void> _preloadDanmaku(String episodeId, int animeId) async {
    try {
      debugPrint('开始预加载弹幕: episodeId=$episodeId, animeId=$animeId');
      
      // 检查是否已经缓存了弹幕数据
      final cachedDanmaku = await DanmakuCacheManager.getDanmakuFromCache(episodeId);
      if (cachedDanmaku != null) {
        debugPrint('弹幕已存在于缓存中，无需预加载: episodeId=$episodeId');
        return;
      }
      
      // 异步预加载弹幕，不等待结果
      DandanplayService.getDanmaku(episodeId, animeId).then((danmakuData) {
        final count = danmakuData['count'];
        if (count != null) {
          debugPrint('弹幕预加载成功: 加载了$count条弹幕');
        } else {
          debugPrint('弹幕预加载成功，但无法确定数量');
        }
      }).catchError((e) {
        debugPrint('弹幕预加载失败: $e');
      });
    } catch (e) {
      debugPrint('预加载弹幕时出错: $e');
    }
  }
}

/// 手动弹幕匹配对话框
/// 
/// 显示搜索动画和选择剧集的界面
class ManualDanmakuMatchDialog extends StatefulWidget {
  final String initialSearchText;
  
  const ManualDanmakuMatchDialog({
    Key? key,
    required this.initialSearchText,
  }) : super(key: key);
  
  @override
  State<ManualDanmakuMatchDialog> createState() => _ManualDanmakuMatchDialogState();
}

class _ManualDanmakuMatchDialogState extends State<ManualDanmakuMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _currentMatches = [];
  List<Map<String, dynamic>> _currentEpisodes = [];
  bool _isSearching = false;
  bool _isLoadingEpisodes = false;
  String _searchMessage = '';
  String _episodesMessage = '';
  
  // 匹配的动画和剧集状态
  Map<String, dynamic>? _selectedAnime;
  Map<String, dynamic>? _selectedEpisode;
  
  // 视图状态
  bool _showEpisodesView = false;
  
  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialSearchText;
    
    // 如果有初始搜索文本，自动执行搜索
    if (widget.initialSearchText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    } else {
      _searchMessage = '请输入动画名称进行搜索';
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // 执行搜索动画
  Future<void> _performSearch() async {
    final searchText = _searchController.text.trim();
    if (searchText.isEmpty) return;
    
    setState(() {
      _isSearching = true;
      _searchMessage = '正在搜索...';
      _showEpisodesView = false;
      _selectedAnime = null;
      _selectedEpisode = null;
      _currentEpisodes = [];
    });
    
    try {
      final results = await ManualDanmakuMatcher.instance.searchAnime(searchText);
      
      setState(() {
        _isSearching = false;
        _currentMatches = results;
        
        if (results.isEmpty) {
          _searchMessage = '没有找到匹配"$searchText"的结果';
        } else {
          _searchMessage = '';
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchMessage = '搜索出错: $e';
      });
    }
  }
  
  // 加载动画的剧集列表
  Future<void> _loadAnimeEpisodes(Map<String, dynamic> anime) async {
    if (anime['animeId'] == null) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画ID为空。';
        _currentEpisodes = [];
      });
      return;
    }
    if (anime['animeTitle'] == null || (anime['animeTitle'] as String).isEmpty) {
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '错误：动画标题为空。';
        _currentEpisodes = [];
      });
      return;
    }
    
    final int animeId = anime['animeId'];
    final String animeTitle = anime['animeTitle'] as String;
    debugPrint('开始加载动画ID $animeId (标题: "$animeTitle") 的剧集列表');
    
    setState(() {
      _isLoadingEpisodes = true;
      _episodesMessage = '正在加载剧集...';
      _currentEpisodes = [];
      _selectedAnime = anime;
      _showEpisodesView = true;
    });
    
    try {
      final episodes = await ManualDanmakuMatcher.instance.getAnimeEpisodes(animeId, animeTitle);
      
      if (!mounted) return;
      
      debugPrint('加载到 ${episodes.length} 个剧集');
      
      setState(() {
        _isLoadingEpisodes = false;
        _currentEpisodes = episodes;
        
        if (episodes.isEmpty) {
          _episodesMessage = '没有找到该动画的剧集信息';
          debugPrint('动画 $animeId 没有剧集信息');
        } else {
          _episodesMessage = '';
          debugPrint('成功加载剧集: ${episodes.length} 集');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingEpisodes = false;
        _episodesMessage = '加载剧集时出错: $e';
        _currentEpisodes = [];
      });
      debugPrint('加载剧集时出错: $e');
    }
  }
  
  // 返回动画选择列表
  void _backToAnimeSelection() {
    setState(() {
      _showEpisodesView = false;
      _selectedEpisode = null;
    });
  }
  
  // 完成选择并返回结果
  void _completeSelection() {
    if (_selectedAnime == null) return;
    
    // 创建最终结果对象
    final result = Map<String, dynamic>.from(_selectedAnime!);
    
    // 如果用户选择了剧集，添加剧集信息
    if (_selectedEpisode != null && _selectedEpisode!.isNotEmpty) {
      result['episodeId'] = _selectedEpisode!['episodeId'];
      result['episodeTitle'] = _selectedEpisode!['episodeTitle'];
      debugPrint('用户选择了剧集: ${_selectedEpisode!['episodeTitle']}, episodeId=${_selectedEpisode!['episodeId']}');
    } else {
      // 如果在剧集选择界面用户没有选择具体剧集，但有可用剧集，默认使用第一个
      if (_showEpisodesView && _currentEpisodes.isNotEmpty) {
        final firstEpisode = _currentEpisodes.first;
        result['episodeId'] = firstEpisode['episodeId'];
        result['episodeTitle'] = firstEpisode['episodeTitle'];
        debugPrint('用户没有选择具体剧集，默认使用第一个: ${firstEpisode['episodeTitle']}, episodeId=${firstEpisode['episodeId']}');
      } else {
        debugPrint('警告: 没有匹配到任何剧集信息，episodeId可能为空');
      }
    }
    
    Navigator.of(context).pop(result);
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_showEpisodesView ? '选择匹配的剧集' : '手动匹配弹幕'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 显示当前选择的动画（在剧集选择视图中）
            if (_showEpisodesView && _selectedAnime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('已选动画:',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(_selectedAnime!['animeTitle'] ?? '未知动画',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('返回', style: TextStyle(fontSize: 12)),
                      onPressed: _backToAnimeSelection,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ),
              ),
            
            // 手动搜索区域（只在动画选择视图中显示）
            if (!_showEpisodesView)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: '输入动画名称搜索',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSearching ? null : _performSearch,
                    child: const Text('搜索'),
                  ),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // 动画选择视图
            if (!_showEpisodesView) ...[
              const Text('搜索结果:'),
              const SizedBox(height: 8),
              
              if (_searchMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_searchMessage, 
                    style: TextStyle(
                      color: _searchMessage.contains('出错') ? Colors.red : Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              
              Expanded(
                child: _isSearching 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentMatches.isEmpty
                    ? const Center(
                        child: Text('没有搜索结果', style: TextStyle(color: Colors.grey))
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentMatches.length,
                        itemBuilder: (context, index) {
                          final match = _currentMatches[index];
                          return ListTile(
                            title: Text(match['animeTitle'] ?? '未知动画'),
                            subtitle: match['typeDescription'] != null
                                ? Text(match['typeDescription'])
                                : null,
                            onTap: () => _loadAnimeEpisodes(match),
                          );
                        },
                      ),
              ),
            ],
            
            // 剧集选择视图
            if (_showEpisodesView) ...[
              const Text('请选择匹配的剧集:'),
              const SizedBox(height: 8),
              
              if (_episodesMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_episodesMessage, 
                    style: TextStyle(
                      color: _episodesMessage.contains('出错') ? Colors.red : Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              
              Expanded(
                child: _isLoadingEpisodes 
                  ? const Center(child: CircularProgressIndicator())
                  : _currentEpisodes.isEmpty
                    ? const Center(
                        child: Text('没有找到剧集', style: TextStyle(color: Colors.grey))
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _currentEpisodes.length,
                        itemBuilder: (context, index) {
                          final episode = _currentEpisodes[index];
                          final bool isSelected = _selectedEpisode != null &&
                              _selectedEpisode!['episodeId'] == episode['episodeId'];
                          
                          return ListTile(
                            title: Text('第${episode['episodeIndex'] ?? '?'}集: ${episode['episodeTitle'] ?? '未知剧集'}'),
                            trailing: isSelected 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedEpisode = episode;
                              });
                            },
                          );
                        },
                      ),
              ),
              
              if (_currentEpisodes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  child: _selectedEpisode == null 
                    ? const Text(
                      '请选择一个剧集来获取正确的弹幕',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red),
                    )
                    : const Text(
                      '已选择剧集，点击"确认选择"继续',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.green),
                    ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_showEpisodesView)
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (_showEpisodesView) ...[
          TextButton(
            child: const Text('返回动画选择'),
            onPressed: _backToAnimeSelection,
            style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
          ),
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
          ),
          if (_currentEpisodes.isNotEmpty) 
            ElevatedButton(
              child: _selectedEpisode != null 
                ? const Text('确认选择剧集') 
                : const Text('使用第一集'),
              onPressed: _completeSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedEpisode != null ? Colors.green : Colors.amber,
              ),
            ),
        ],
      ],
    );
  }
}
