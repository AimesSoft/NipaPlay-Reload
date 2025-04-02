import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/bangumi_service.dart';
import '../models/bangumi_model.dart';
import '../utils/image_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/loading_placeholder.dart';

class NewSeriesPage extends StatefulWidget {
  const NewSeriesPage({super.key});

  @override
  State<NewSeriesPage> createState() => _NewSeriesPageState();
}

class _NewSeriesPageState extends State<NewSeriesPage> with AutomaticKeepAliveClientMixin {
  final BangumiService _bangumiService = BangumiService.instance;
  List<BangumiAnime> _animes = [];
  bool _isLoading = true;
  String? _error;

  // 添加星期几的映射
  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    -1: '未知', // 添加未知类别
  };

  // 将 1-7 的星期转换为 0-6

  @override
  bool get wantKeepAlive => true; // 保持页面状态

  @override
  void initState() {
    super.initState();
    print('NewSeriesPage 初始化');
    _loadAnimes();
  }

  Future<void> _loadAnimes() async {
    try {
      print('开始加载番剧数据');
      setState(() {
        _isLoading = true;
        _error = null;
      });

      print('调用 BangumiService.getCalendar()');
      final animes = await _bangumiService.getCalendar();
      print('获取到 ${animes.length} 个番剧');

      // 预加载所有图片
      ImageCacheManager.instance.preloadImages(
        animes.map((anime) => anime.imageUrl).toList(),
      );

      if (mounted) {
        setState(() {
          _animes = animes;
          _isLoading = false;
        });
      }
      print('番剧数据加载完成');
    } catch (e) {
      print('加载番剧数据时出错: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
      anime.airWeekday! > 6
    ).toList();
    
    if (unknownAnimes.isNotEmpty) {
      grouped[-1] = unknownAnimes;
    }
    
    // 再处理已知更新时间的番剧
    for (var anime in validAnimes) {
      if (anime.airWeekday != null && 
          anime.airWeekday != -1 && 
          anime.airWeekday! >= 0 && 
          anime.airWeekday! <= 6) {
        grouped.putIfAbsent(anime.airWeekday!, () => []).add(anime);
      }
    }
    
    print('分组结果: ${grouped.keys.toList()}');
    return grouped;
  }

  Widget _buildAnimeSection(List<BangumiAnime> animes) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 7/10,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: animes.length,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final anime = animes[index];
        return _buildAnimeCard(context, anime);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    print('NewSeriesPage build - isLoading: $_isLoading, hasError: ${_error != null}, animeCount: ${_animes.length}');
    
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
    
    // 只对已知更新时间的番剧进行排序
    knownWeekdays.sort((a, b) {
      final today = DateTime.now().weekday % 7; // 获取今天的星期（0-6）
      
      // 如果是今天，排在最前面
      if (a == today) return -1;
      if (b == today) return 1;

      // 计算与今天的距离
      final distA = (a - today + 7) % 7;
      final distB = (b - today + 7) % 7;
      return distA.compareTo(distB);
    });
    

    return RefreshIndicator(
      onRefresh: _loadAnimes,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 常规更新部分
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
          // 未知更新时间的部分 - 始终显示在最底部
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
        ],
      ),
    );
  }

  Widget _buildAnimeCard(BuildContext context, BangumiAnime anime) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showAnimeDetail(anime),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Card(
                elevation: 2,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 160,
                    height: 228, // 160 * 10/7 ≈ 228
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: anime.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const LoadingPlaceholder(
                              width: 160,
                              height: 228,
                            ),
                            errorWidget: (context, url, error) {
                              return Image.asset(
                                'assets/backempty.png',
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              anime.nameCn,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
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
      print('日期格式不正确: $dateStr');
      return dateStr;
    } catch (e) {
      print('格式化日期出错: $e');
      return dateStr;
    }
  }

  Future<void> _showAnimeDetail(BangumiAnime anime) async {
    print('显示番剧详情 - ID: ${anime.id}');
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<BangumiAnime>(
        future: _bangumiService.getAnimeDetails(anime.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            print('加载详情出错: ${snapshot.error}');
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
          // 使用列表页传入的 airWeekday
          final airWeekday = anime.airWeekday;
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
                                child: CachedNetworkImage(
                                  imageUrl: detailedAnime.imageUrl,
                                  width: 120,
                                  height: 120 * 10 / 7,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const LoadingPlaceholder(
                                    width: 120,
                                    height: 120 * 10 / 7,
                                  ),
                                  errorWidget: (context, url, error) => Container(
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
                          Text(
                            '简介:',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detailedAnime.summary!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              height: 1.5,
                              color: Colors.white70,
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
      ),
    );
  }
} 