import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/global_hotkey_manager.dart';
import 'dart:ui';

/// 手动弹幕匹配对话框
/// 
/// 显示搜索动画和选择剧集的界面
class ManualDanmakuMatchDialog extends StatefulWidget {
  final String? initialVideoTitle;
  
  const ManualDanmakuMatchDialog({super.key, this.initialVideoTitle});

  @override
  State<ManualDanmakuMatchDialog> createState() => _ManualDanmakuMatchDialogState();
}

class _ManualDanmakuMatchDialogState extends State<ManualDanmakuMatchDialog> 
    with GlobalHotkeyManagerMixin {
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

  // 实现GlobalHotkeyManagerMixin要求的方法
  @override
  String get hotkeyDisableReason => 'manual_danmaku_dialog';

  @override
  void initState() {
    super.initState();
    debugPrint('=== 新版ManualDanmakuMatchDialog初始化 ===');
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
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      const apiPath = '/api/v2/search/anime';
      
      final url = 'https://api.dandanplay.net/api/v2/search/anime?keyword=${Uri.encodeComponent(keyword)}';
      
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
      final animeId = anime['animeId'] is int ? anime['animeId'] : int.tryParse(anime['animeId'].toString());
      if (animeId == null) {
        setState(() {
          _isLoadingEpisodes = false;
          _episodesMessage = '错误：动画ID格式不正确。';
        });
        return;
      }
      
      debugPrint('正在加载动画剧集，animeId: $animeId, animeTitle: ${anime['animeTitle']}');
      
      final appSecret = await DandanplayService.getAppSecret();
      final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
      final apiPath = '/api/v2/bangumi/$animeId';
      
      final url = 'https://api.dandanplay.net/api/v2/bangumi/$animeId';
      debugPrint('API请求URL: $url');
      
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
      
      setState(() {
        _isLoadingEpisodes = false;
      });
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 添加调试信息
        debugPrint('API响应成功，检查数据结构');
        debugPrint('根级别success: ${data['success']}');
        debugPrint('根级别errorCode: ${data['errorCode']}');
        
        // 检查API是否成功
        if (data['success'] == true && data['bangumi'] != null) {
          final bangumi = data['bangumi'];
          debugPrint('bangumi字段存在，检查episodes...');
          
          if (bangumi['episodes'] != null && bangumi['episodes'] is List) {
            final episodes = List<Map<String, dynamic>>.from(bangumi['episodes']);
            setState(() {
              _currentEpisodes = episodes;
              _episodesMessage = episodes.isEmpty ? '该动画暂无剧集信息' : '';
            });
            debugPrint('成功加载 ${episodes.length} 个剧集');
          } else {
            setState(() {
              _episodesMessage = '该动画暂无剧集信息';
            });
            debugPrint('bangumi.episodes字段为空或不是列表');
          }
        } else {
          setState(() {
            _episodesMessage = '获取动画信息失败: ${data['errorMessage'] ?? '未知错误'}';
          });
          debugPrint('API返回错误: ${data['errorMessage']}');
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

  /// 构建内容区域 - 根据设备类型选择布局方式
  Widget _buildContentArea() {
    // 判断是否为真正的手机设备（基于最短边，不受屏幕旋转影响）
    final window = WidgetsBinding.instance.window;
    final size = window.physicalSize / window.devicePixelRatio;
    final shortestSide = size.width < size.height ? size.width : size.height;
    final bool isRealPhone = isPhone && shortestSide < 600;
    
    // 调试信息
    debugPrint('设备判断: isPhone=$isPhone, isTablet=$isTablet, isRealPhone=$isRealPhone, shortestSide=$shortestSide, _showEpisodesView=$_showEpisodesView');
    
    if (isRealPhone) {
      // 真正的手机设备使用左右布局（包括选择剧集界面）
      debugPrint('使用左右布局');
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左半部分：搜索区域或返回按钮
          Expanded(
            flex: 1,
            child: _showEpisodesView ? _buildEpisodesLeftSection() : _buildSearchSection(),
          ),
          const SizedBox(width: 12),
          // 右半部分：搜索结果或剧集列表
          Expanded(
            flex: 1,
            child: _showEpisodesView ? _buildEpisodesSection() : _buildResultsSection(),
          ),
        ],
      );
    } else {
      // 其他情况使用原来的上下布局
      debugPrint('使用垂直布局');
      return _buildVerticalLayout();
    }
  }

  /// 构建搜索区域（紧凑版，用于左侧）
  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('搜索', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: '动画名称',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onSubmitted: (_) => _performSearch(),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSearching ? null : _performSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.3)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: _isSearching ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ) : const Text('搜索'),
          ),
        ),
        if (_searchMessage.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _searchMessage.contains('出错') 
                  ? Colors.red.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _searchMessage, 
              style: TextStyle(
                color: _searchMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 构建搜索结果区域
  Widget _buildResultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('结果', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
            child: _isSearching 
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  )
                )
              : _currentMatches.isEmpty
                ? const Center(
                    child: Text('暂无结果', style: TextStyle(color: Colors.white54, fontSize: 12))
                  )
                : ListView.builder(
                    itemCount: _currentMatches.length,
                    itemBuilder: (context, index) {
                      final match = _currentMatches[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 0.5,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(
                            match['animeTitle'] ?? '未知动画',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${match['typeDescription'] ?? '未知'} | ${match['episodeCount'] ?? 0}集',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _loadAnimeEpisodes(match),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// 构建原来的垂直布局（用于其他设备类型）
  Widget _buildVerticalLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 显示当前选择的动画（在剧集选择视图中）
        if (_showEpisodesView && _selectedAnime != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('已选动画:',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_selectedAnime!['animeTitle'] ?? '未知动画',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          )),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white70),
                  label: const Text('返回', style: TextStyle(fontSize: 12, color: Colors.white70)),
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
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '输入动画名称搜索',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
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
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
        
        // 动画选择视图
        if (!_showEpisodesView) ...[
          const Text('搜索结果:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          
          if (_searchMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _searchMessage.contains('出错') 
                    ? Colors.red.withOpacity(0.2) 
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_searchMessage, 
                style: TextStyle(
                  color: _searchMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                ),
              ),
            ),
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
              child: _isSearching 
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    )
                  )
                : _currentMatches.isEmpty
                  ? const Center(
                      child: Text('没有搜索结果', style: TextStyle(color: Colors.white54))
                    )
                  : ListView.builder(
                      itemCount: _currentMatches.length,
                      itemBuilder: (context, index) {
                        final match = _currentMatches[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              match['animeTitle'] ?? '未知动画',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '类型: ${match['typeDescription'] ?? '未知'} | 剧集数: ${match['episodeCount'] ?? 0}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            onTap: () => _loadAnimeEpisodes(match),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
        
        // 剧集选择视图
        if (_showEpisodesView) ...[
          const Text('选择剧集:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          
          if (_episodesMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _episodesMessage.contains('出错') 
                    ? Colors.red.withOpacity(0.2) 
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_episodesMessage, 
                style: TextStyle(
                  color: _episodesMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
              child: _isLoadingEpisodes
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    )
                  )
                : _currentEpisodes.isEmpty
                  ? const Center(
                      child: Text('没有可用的剧集', style: TextStyle(color: Colors.white54))
                    )
                  : ListView.builder(
                      itemCount: _currentEpisodes.length,
                      itemBuilder: (context, index) {
                        final episode = _currentEpisodes[index];
                        final isSelected = _selectedEpisode != null && 
                                          _selectedEpisode!['episodeId'] == episode['episodeId'];
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected 
                              ? Colors.green.withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected 
                                ? Colors.green.withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              '${episode['episodeTitle'] ?? '未知剧集'}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: isSelected 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                            onTap: () {
                              setState(() {
                                _selectedEpisode = episode;
                              });
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          
          if (_currentEpisodes.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Text(
                _selectedEpisode == null 
                  ? '请选择一个剧集来获取正确的弹幕'
                  : '已选择剧集，点击"确认选择"继续',
                style: TextStyle(
                  color: _selectedEpisode == null ? Colors.white70 : Colors.green
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// 构建剧集视图的左侧部分（返回按钮和已选动画信息）
  Widget _buildEpisodesLeftSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        const Text('选择剧集', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        
        // 显示当前选择的动画
        if (_selectedAnime != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已选动画:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _selectedAnime!['animeTitle'] ?? '未知动画',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white70),
                    label: const Text('返回', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    onPressed: _backToAnimeSelection,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 32),
                      backgroundColor: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建剧集列表（紧凑版，用于右侧）
  Widget _buildEpisodesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('剧集列表', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        
        // 错误或状态消息
        if (_episodesMessage.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _episodesMessage.contains('出错') 
                  ? Colors.red.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _episodesMessage, 
              style: TextStyle(
                color: _episodesMessage.contains('出错') ? Colors.redAccent : Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        
        // 剧集列表
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
            child: _isLoadingEpisodes 
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  )
                )
              : _currentEpisodes.isEmpty
                ? const Center(
                    child: Text('暂无剧集', style: TextStyle(color: Colors.white54, fontSize: 12))
                  )
                : ListView.builder(
                    itemCount: _currentEpisodes.length,
                    itemBuilder: (context, index) {
                      final episode = _currentEpisodes[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 0.5,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          title: Text(
                            episode['episodeTitle'] ?? '第${episode['episodeId']}话',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            setState(() {
                              _selectedEpisode = episode;
                            });
                            _completeSelection();
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
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
    // 其他键事件不处理，让它们正常传递给输入框
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('=== 新版ManualDanmakuMatchDialog.build() 调用 ===');
    
    // 检查是否为真正的手机设备
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
          // 点击空白区域关闭对话框
          onTap: () {
            debugPrint('[ManualDanmakuDialog] 点击空白区域，关闭对话框');
            Navigator.of(context).pop();
          },
          behavior: HitTestBehavior.translucent,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: GestureDetector(
              // 阻止对话框内容区域的点击事件冒泡
              onTap: () {},
              child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(24),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏 - 非手机设备显示
              if (!isRealPhone) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _showEpisodesView ? '选择匹配的剧集' : '手动匹配弹幕',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
              ],
              
              // 内容区域
              Expanded(
                child: Stack(
                  children: [
                    // 主要内容
                    _buildContentArea(),
                    
                    // 手机设备的关闭按钮 - 悬浮在右上角
                    if (isRealPhone)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                  ],
                ),
              ),
              
              // 操作按钮区域 - 仅在非手机设备显示
              if (!isRealPhone) ...[
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_showEpisodesView) ...[
                      TextButton(
                        onPressed: _backToAnimeSelection,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text('返回动画选择'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_showEpisodesView && _currentEpisodes.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 0.5,
                              ),
                            ),
                            child: TextButton(
                              onPressed: _completeSelection,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: Text(_selectedEpisode != null 
                                ? '确认选择剧集' 
                                : '使用第一集'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
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
