import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bangumi_service.dart';
import '../models/bangumi_model.dart';
import '../utils/image_cache_manager.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../widgets/cached_network_image_widget.dart';
import '../widgets/custom_refresh_indicator.dart';
import '../widgets/translation_button.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/dandanplay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NewSeriesPage extends StatefulWidget {
  const NewSeriesPage({super.key});

  @override
  State<NewSeriesPage> createState() => _NewSeriesPageState();
}

class _NewSeriesPageState extends State<NewSeriesPage> {
  final BangumiService _bangumiService = BangumiService.instance;
  List<BangumiAnime> _animes = [];
  bool _isLoading = true;
  String? _error;
  bool _isReversed = false;
  Map<int, String> _translatedSummaries = {};
  static const String _translationCacheKey = 'bangumi_translation_cache';
  static const Duration _translationCacheDuration = Duration(days: 7);
  bool _isShowingTranslation = false;

  // 切换排序方向
  void _toggleSort() {
    setState(() {
      _isReversed = !_isReversed;
    });
  }

  // 添加星期几的映射
  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日', // 添加周日（7）的映射
    -1: '未知', // 添加未知类别
  };

  @override
  void initState() {
    super.initState();
    ////print('NewSeriesPage 初始化');
    _loadAnimes();
    _loadTranslationCache();
  }

  @override
  void dispose() {
    // 释放所有图片资源
    for (var anime in _animes) {
      ImageCacheManager.instance.releaseImage(anime.imageUrl);
    }
    super.dispose();
  }

  Future<void> _loadAnimes() async {
    try {
      //print('开始加载番剧数据');
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 加载数据
      //print('调用 BangumiService.loadData()');
      await _bangumiService.loadData();

      //print('调用 BangumiService.getCalendar()');
      final animes = await _bangumiService.getCalendar();
      //print('获取到 ${animes.length} 个番剧');

      if (mounted) {
        setState(() {
          _animes = animes;
          _isLoading = false;
        });
      }
      //print('番剧数据加载完成');
    } catch (e) {
      //print('加载番剧数据时出错: $e');
      String errorMsg = e.toString();
      if (e is TimeoutException) {
        errorMsg = '网络请求超时，请检查网络连接后重试';
      } else if (errorMsg.contains('SocketException')) {
        errorMsg = '网络连接失败，请检查网络设置';
      } else if (errorMsg.contains('HttpException')) {
        errorMsg = '服务器无法连接，请稍后重试';
      } else if (errorMsg.contains('FormatException')) {
        errorMsg = '服务器返回数据格式错误';
      }
      
      if (mounted) {
        setState(() {
          _error = errorMsg;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTranslationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedString = prefs.getString(_translationCacheKey);
      
      if (cachedString != null) {
        //print('找到翻译缓存数据');
        final data = json.decode(cachedString);
        final timestamp = data['timestamp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch;
        
        //print('缓存时间戳: $timestamp');
        //print('当前时间戳: $now');
        //print('时间差: ${now - timestamp}ms');
        //print('缓存有效期: ${_translationCacheDuration.inMilliseconds}ms');
        
        // 检查缓存是否过期
        if (now - timestamp <= _translationCacheDuration.inMilliseconds) {
          final translations = Map<String, String>.from(data['translations']);
          // 将字符串键转换回整数
          final Map<int, String> parsedTranslations = {};
          translations.forEach((key, value) {
            parsedTranslations[int.parse(key)] = value;
          });
          //print('从缓存加载翻译，共 ${parsedTranslations.length} 条');
          setState(() {
            _translatedSummaries = parsedTranslations;
          });
        } else {
          //print('翻译缓存已过期，清除缓存');
          await prefs.remove(_translationCacheKey);
        }
      } else {
        //print('未找到翻译缓存');
      }
    } catch (e) {
      //print('加载翻译缓存失败: $e');
    }
  }

  Future<void> _saveTranslationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 确保所有值都是可序列化的字符串
      final Map<String, String> serializableTranslations = {};
      _translatedSummaries.forEach((key, value) {
        serializableTranslations[key.toString()] = value;
      });
      
      final data = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'translations': serializableTranslations,
      };
      final jsonString = json.encode(data);
      await prefs.setString(_translationCacheKey, jsonString);
      //print('保存翻译到缓存，共 ${_translatedSummaries.length} 条');
      //print('缓存数据大小: ${jsonString.length} 字节');
    } catch (e) {
      //print('保存翻译缓存失败: $e');
    }
  }

  // 按星期几分组番剧
  Map<int, List<BangumiAnime>> _groupAnimesByWeekday() {
    final grouped = <int, List<BangumiAnime>>{};
    // 过滤掉没有图片信息和没有名字的番剧
    final validAnimes = _animes.where((anime) => 
      anime.imageUrl != 'assets/backempty.png' && 
      anime.imageUrl != 'assets/backEmpty.png' &&
      anime.nameCn.isNotEmpty &&  // 确保有中文名
      anime.name.isNotEmpty      // 确保有日文名
    ).toList();
    
    // 先处理未知更新时间的番剧
    final unknownAnimes = validAnimes.where((anime) => 
      anime.airWeekday == null || 
      anime.airWeekday == -1 || 
      anime.airWeekday! < 0 || 
      anime.airWeekday! > 7
    ).toList();
    
    if (unknownAnimes.isNotEmpty) {
      grouped[-1] = unknownAnimes;
    }
    
    // 再处理已知更新时间的番剧
    for (var anime in validAnimes) {
      if (anime.airWeekday != null && 
          anime.airWeekday != -1 && 
          anime.airWeekday! >= 0 && 
          anime.airWeekday! <= 7) {
        // 将 7 转换为 0，保持一致性
        final weekday = anime.airWeekday == 7 ? 0 : anime.airWeekday!;
        grouped.putIfAbsent(weekday, () => []).add(anime);
      }
    }
    
    ////print('分组结果: ${grouped.keys.toList()}');
    return grouped;
  }

  Widget _buildAnimeSection(List<BangumiAnime> animes) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 7/12,
        crossAxisSpacing: 20,
        mainAxisSpacing: 0,
      ),
      itemCount: animes.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemBuilder: (context, index) {
        final anime = animes[index];
        return _buildAnimeCard(context, anime);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ////print('NewSeriesPage build - isLoading: $_isLoading, hasError: ${_error != null}, animeCount: ${_animes.length}');
    
    if (_isLoading && _animes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _animes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAnimes,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final groupedAnimes = _groupAnimesByWeekday();
    // 分离已知和未知更新时间的番剧
    final knownWeekdays = groupedAnimes.keys.where((day) => day != -1).toList();
    final unknownWeekdays = groupedAnimes.keys.where((day) => day == -1).toList();
    
    // 对已知更新时间的番剧进行排序
    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7; // 获取今天的星期（0-6）
      
      // 如果是今天，排在最前面
      if (a == today) return -1;
      if (b == today) return 1;

      // 计算与今天的距离
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return _isReversed ? distB.compareTo(distA) : distA.compareTo(distB);
    });

    return Stack(
      children: [
        CustomRefreshIndicator(
          onRefresh: _loadAnimes,
          color: Colors.white,
          strokeWidth: 3.0,
          blur: 20.0,
          opacity: 0.8,
          child: CustomScrollView(
            slivers: [
              SliverList(
                delegate: SliverChildListDelegate([
                  ...knownWeekdays.map((weekday) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _weekdays[weekday] ?? '未知',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildAnimeSection(groupedAnimes[weekday]!),
                    ],
                  )),
                  if (unknownWeekdays.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '更新时间未定',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildAnimeSection(groupedAnimes[-1]!),
                  ],
                ]),
              ),
            ],
          ),
        ),
        // 添加悬浮按钮
        Positioned(
          right: 16,
          bottom: 16,
          child: GlassmorphicContainer(
            width: 56,
            height: 56,
            borderRadius: 28,
            blur: 10,
            alignment: Alignment.center,
            border: 1,
            linearGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFffffff).withOpacity(0.1),
                const Color(0xFFFFFFFF).withOpacity(0.05),
              ],
            ),
            borderGradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFffffff).withOpacity(0.5),
                const Color((0xFFFFFFFF)).withOpacity(0.5),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _toggleSort,
                child: Center(
                  child: Icon(
                    _isReversed ? Ionicons.chevron_up_outline : Ionicons.chevron_down_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard(BuildContext context, BangumiAnime anime) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showAnimeDetail(anime),
        child: Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 7/10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImageWidget(
                    imageUrl: anime.imageUrl,
                    fit: BoxFit.cover,
                    shouldRelease: true,
                    errorBuilder: (context, error) {
                      ////print('图片加载失败: ${anime.nameCn}, URL: ${anime.imageUrl}');
                      return Container(
                        color: Colors.grey[800],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.white54),
                            const SizedBox(height: 8),
                            Text(
                              '加载失败\n${anime.nameCn}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  anime.nameCn,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    height: 1.2,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) {
      return '';
    }
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return '${parts[0]}年${parts[1]}月${parts[2]}日';
      }
      ////print('日期格式不正确: $dateStr');
      return dateStr;
    } catch (e) {
      ////print('格式化日期出错: $e');
      return dateStr;
    }
  }

  Future<String?> _translateSummary(String text) async {
    try {
      final appSecret = await DandanplayService.getAppSecret();
      //print('开始请求翻译...');
      final response = await http.post(
        Uri.parse('https://nipaplay.aimes-soft.com/tran.php'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'appSecret': appSecret,
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        //print('翻译请求成功');
        return response.body;
      }
      //print('翻译请求失败，状态码: ${response.statusCode}');
      return null;
    } catch (e) {
      //print('翻译请求异常: $e');
      return null;
    }
  }

  Future<void> _showAnimeDetail(BangumiAnime anime) async {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<BangumiAnime>(
        future: _bangumiService.getAnimeDetails(anime.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('错误'),
              content: Text('加载失败: ${snapshot.error}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          }

          final detailedAnime = snapshot.data!;
          final airWeekday = anime.airWeekday;
          
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    width: 600,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 130, 130, 130).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.light
                            ? const Color.fromARGB(255, 201, 201, 201)
                            : const Color.fromARGB(255, 130, 130, 130),
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
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 120,
                                    height: 120 * 10 / 7,
                                    color: Colors.transparent,
                                    child: CachedNetworkImageWidget(
                                      imageUrl: anime.imageUrl,
                                      width: 120,
                                      height: 120 * 10 / 7,
                                      fit: BoxFit.cover,
                                      shouldRelease: true,
                                      errorBuilder: (context, error) => Container(
                                        color: Colors.transparent,
                                        child: const Icon(Icons.error, color: Colors.white54),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detailedAnime.nameCn,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (detailedAnime.name != detailedAnime.nameCn)
                                        Text(
                                          detailedAnime.name,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontSize: 14,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      if (detailedAnime.rating != null)
                                        Row(
                                          children: [
                                            const Icon(Icons.star, color: Colors.amber, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              detailedAnime.rating!.toStringAsFixed(1),
                                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 4),
                                      if (detailedAnime.airDate != null && detailedAnime.airDate!.isNotEmpty) ...[
                                        Text(
                                          '放送日期: ${_formatDate(detailedAnime.airDate)}${airWeekday != null ? ' (${_weekdays[airWeekday]})' : ''}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                      if (detailedAnime.totalEpisodes != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '话数: ${detailedAnime.totalEpisodes}话',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                      if (detailedAnime.originalWork != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '原作: ${detailedAnime.originalWork}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                      if (detailedAnime.director != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '导演: ${detailedAnime.director}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                      if (detailedAnime.studio != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '制作公司: ${detailedAnime.studio}',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (detailedAnime.summary != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    '简介:',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (detailedAnime.summary!.contains('の')) ...[
                                    const SizedBox(width: 8),
                                    TranslationButton(
                                      animeId: detailedAnime.id,
                                      summary: detailedAnime.summary!,
                                      translatedSummaries: _translatedSummaries,
                                      onTranslationUpdated: (updatedTranslations) {
                                        setDialogState(() {
                                          _translatedSummaries = updatedTranslations;
                                          _saveTranslationCache();
                                        });
                                      },
                                      isShowingTranslation: _isShowingTranslation,
                                      onTranslationStateChanged: (isShowing) {
                                        setDialogState(() {
                                          _isShowingTranslation = isShowing;
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _translatedSummaries.containsKey(detailedAnime.id) && _isShowingTranslation
                                    ? _translatedSummaries[detailedAnime.id]!
                                    : detailedAnime.summary!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                            if (detailedAnime.tags?.isNotEmpty == true) ...[
                              const SizedBox(height: 12),
                              Text(
                                '标签:',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: detailedAnime.tags!
                                    .map((tag) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        tag,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
} 