import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../services/bangumi_service.dart';
import '../models/bangumi_model.dart';
import '../models/watch_history_model.dart';
import '../widgets/cached_network_image_widget.dart';
// import '../widgets/translation_button.dart'; // Removed
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
// import 'dart:convert'; // No longer needed for local translation state
// import 'package:http/http.dart' as http; // No longer needed for local translation state
// import '../services/dandanplay_service.dart'; // No longer needed for local translation state
import '../widgets/blur_snackbar.dart'; // Added for blur snackbar
// import 'package:provider/provider.dart'; // Removed from here
// import '../utils/video_player_state.dart'; // Removed from here
import 'dart:io'; // Added for File operations
// import '../utils/tab_change_notifier.dart'; // Removed from here

class AnimeDetailPage extends StatefulWidget {
  final int animeId;

  const AnimeDetailPage({super.key, required this.animeId});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
  
  static Future<WatchHistoryItem?> show(BuildContext context, int animeId) {
    return showGeneralDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '关闭详情页',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AnimeDetailPage(animeId: animeId);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
}

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with SingleTickerProviderStateMixin {
  final BangumiService _bangumiService = BangumiService.instance;
  BangumiAnime? _detailedAnime;
  bool _isLoading = true;
  String? _error;
  TabController? _tabController;

  // 新增：评分到评价文本的映射
  static const Map<int, String> _ratingEvaluationMap = {
    1: '不忍直视',
    2: '很差',
    3: '差',
    4: '较差',
    5: '不过不失',
    6: '还行',
    7: '推荐',
    8: '力荐',
    9: '神作',
    10: '超神作',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // 启动时异步清理过期缓存
    _bangumiService.cleanExpiredDetailCache().then((_) {
      debugPrint("[番剧详情] 已清理过期的番剧详情缓存");
    });
    _fetchAnimeDetails();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _fetchAnimeDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final anime = await _bangumiService.getAnimeDetails(widget.animeId);
      if (mounted) {
        setState(() {
          _detailedAnime = anime;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) return '${parts[0]}年${parts[1]}月${parts[2]}日';
      return dateStr;
    } catch (e) {
      return dateStr;
    }
  }

  static const Map<int, String> _weekdays = {
    0: '周日',
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    -1: '未知',
  };

  // 新增：构建星星评分的 Widget
  Widget _buildRatingStars(double? rating) {
    if (rating == null || rating < 0 || rating > 10) {
      return Text('N/A',
          style:
              TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13));
    }

    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool halfStar = (rating - fullStars) >= 0.5;

    for (int i = 0; i < 10; i++) {
      if (i < fullStars) {
        stars.add(Icon(Ionicons.star, color: Colors.yellow[600], size: 16));
      } else if (i == fullStars && halfStar) {
        stars
            .add(Icon(Ionicons.star_half, color: Colors.yellow[600], size: 16));
      } else {
        stars.add(Icon(Ionicons.star_outline,
            color: Colors.yellow[600]?.withOpacity(0.7), size: 16));
      }
      if (i < 9) {
        stars.add(const SizedBox(width: 1)); // 星星之间的小间距
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _buildSummaryView(BangumiAnime anime) {
    final String summaryText = anime.summary ?? '暂无简介';
    final airWeekday = anime.airWeekday;
    final String weekdayString =
        airWeekday != null && _weekdays.containsKey(airWeekday)
            ? _weekdays[airWeekday]!
            : '待定';
    final bangumiRatingValue = anime.ratingDetails?['Bangumi评分'];
    String bangumiEvaluationText = '';
    if (bangumiRatingValue is num &&
        _ratingEvaluationMap.containsKey(bangumiRatingValue.round())) {
      bangumiEvaluationText =
          '(${_ratingEvaluationMap[bangumiRatingValue.round()]!})';
    }

    final valueStyle = TextStyle(
        color: Colors.white.withOpacity(0.85), fontSize: 13, height: 1.5);
    const boldWhiteKeyStyle = TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        height: 1.5);
    final sectionTitleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold);

    List<Widget> metadataWidgets = [];
    if (anime.metadata != null && anime.metadata!.isNotEmpty) {
      metadataWidgets.add(const SizedBox(height: 8));
      metadataWidgets.add(Text('制作信息:', style: sectionTitleStyle));
      for (String item in anime.metadata!) {
        if (item.trim().startsWith('别名:') || item.trim().startsWith('别名：')) {
          continue;
        }
        var parts = item.split(RegExp(r'[:：]'));
        if (parts.length == 2) {
          metadataWidgets.add(Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: RichText(
                  text: TextSpan(
                      style: valueStyle.copyWith(height: 1.3),
                      children: [
                    TextSpan(
                        text: '${parts[0].trim()}: ',
                        style: boldWhiteKeyStyle.copyWith(
                            fontWeight: FontWeight.w600)),
                    TextSpan(text: parts[1].trim())
                  ]))));
        } else {
          metadataWidgets
              .add(Text(item, style: valueStyle.copyWith(height: 1.3)));
        }
      }
    }

    List<Widget> titlesWidgets = [];
    if (anime.titles != null && anime.titles!.isNotEmpty) {
      titlesWidgets.add(const SizedBox(height: 8));
      titlesWidgets.add(Text('其他标题:', style: sectionTitleStyle));
      titlesWidgets.add(const SizedBox(height: 4));
      TextStyle aliasTextStyle =
          TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12);
      for (var titleEntry in anime.titles!) {
        String titleText = titleEntry['title'] ?? '未知标题';
        String languageText = '';
        if (titleEntry['language'] != null &&
            titleEntry['language']!.isNotEmpty) {
          languageText = ' (${titleEntry['language']})';
        }
        titlesWidgets.add(Padding(
            padding: const EdgeInsets.only(top: 3.0, left: 8.0),
            child: Text(
              '$titleText$languageText',
              style: aliasTextStyle,
            )));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (anime.name != anime.nameCn)
            Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(anime.name,
                    style: valueStyle.copyWith(
                        fontSize: 14, fontStyle: FontStyle.italic))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (anime.imageUrl.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImageWidget(
                          imageUrl: anime.imageUrl,
                          width: 130,
                          height: 195,
                          fit: BoxFit.cover))),
            Expanded(
              child: SizedBox(
                height: 195,
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(summaryText, style: valueStyle),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          if (bangumiRatingValue is num && bangumiRatingValue > 0) ...[
            RichText(
                text: TextSpan(children: [
              TextSpan(text: 'Bangumi评分: ', style: boldWhiteKeyStyle),
              WidgetSpan(
                  child: _buildRatingStars(bangumiRatingValue.toDouble())),
              TextSpan(
                  text: ' ${bangumiRatingValue.toStringAsFixed(1)} ',
                  style: TextStyle(
                      color: Colors.yellow[600],
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              TextSpan(
                  text: bangumiEvaluationText,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 12))
            ])),
            const SizedBox(height: 6),
          ],
          if (anime.ratingDetails != null &&
              anime.ratingDetails!.entries.any((entry) =>
                  entry.key != 'Bangumi评分' &&
                  entry.value is num &&
                  (entry.value as num) > 0))
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0, top: 2.0),
                child: Wrap(
                    spacing: 12.0,
                    runSpacing: 4.0,
                    children: anime.ratingDetails!.entries
                        .where((entry) =>
                            entry.key != 'Bangumi评分' &&
                            entry.value is num &&
                            (entry.value as num) > 0)
                        .map((entry) {
                      String siteName = entry.key;
                      if (siteName.endsWith('评分')) {
                        siteName = siteName.substring(0, siteName.length - 2);
                      }
                      final score = entry.value as num;
                      return RichText(
                          text: TextSpan(
                              style: valueStyle.copyWith(fontSize: 12),
                              children: [
                            TextSpan(
                                text: '$siteName: ',
                                style: boldWhiteKeyStyle.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal)),
                            TextSpan(
                                text: score.toStringAsFixed(1),
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.95)))
                          ]));
                    }).toList())),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                TextSpan(text: '开播: ', style: boldWhiteKeyStyle),
                TextSpan(text: '${_formatDate(anime.airDate)} ($weekdayString)')
              ]))),
          if (anime.typeDescription != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '类型: ', style: boldWhiteKeyStyle),
                  TextSpan(text: anime.typeDescription)
                ]))),
          if (anime.totalEpisodes != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '话数: ', style: boldWhiteKeyStyle),
                  TextSpan(text: '${anime.totalEpisodes}话')
                ]))),
          if (anime.isOnAir != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '状态: ', style: boldWhiteKeyStyle),
                  TextSpan(text: anime.isOnAir! ? '连载中' : '已完结')
                ]))),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                TextSpan(
                    text: '追番状态: ',
                    style:
                        boldWhiteKeyStyle.copyWith(color: Colors.orangeAccent)),
                TextSpan(
                    text: anime.isFavorited! ? '已追' : '未追',
                    style:
                        TextStyle(color: Colors.orangeAccent.withOpacity(0.85)))
              ]))),
          if (anime.isNSFW ?? false)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(
                      text: '限制内容: ',
                      style:
                          boldWhiteKeyStyle.copyWith(color: Colors.redAccent)),
                  TextSpan(
                      text: '是',
                      style:
                          TextStyle(color: Colors.redAccent.withOpacity(0.85)))
                ]))),
          ...metadataWidgets,
          ...titlesWidgets,
          if (anime.tags != null && anime.tags!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('标签:', style: sectionTitleStyle),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: anime.tags!
                    .map((tag) => Chip(
                        label: Text(tag,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white.withOpacity(0.15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.3)))))
                    .toList())
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEpisodesListView(BangumiAnime anime) {
    if (anime.episodeList == null || anime.episodeList!.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(20.0),
        child: Text('暂无剧集信息', style: TextStyle(color: Colors.white70)),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      itemCount: anime.episodeList!.length,
      itemBuilder: (context, index) {
        final episode = anime.episodeList![index];

        return FutureBuilder<WatchHistoryItem?>(
          future:
              WatchHistoryManager.getHistoryItemByEpisode(anime.id, episode.id),
          builder: (context, historySnapshot) {
            Widget leadingIcon =
                const SizedBox(width: 20); // Default empty space
            String? progressText;
            Color? tileColor;
            Color iconColor =
                Colors.orangeAccent.withOpacity(0.8); // Default for playing
            double progress = 0.0;

            if (historySnapshot.connectionState == ConnectionState.done) {
              if (historySnapshot.hasData && historySnapshot.data != null) {
                final historyItem = historySnapshot.data!;
                progress = historyItem.watchProgress;
                if (progress > 0.95) {
                  // Watched
                  leadingIcon = Icon(Ionicons.checkmark_circle,
                      color: Colors.greenAccent.withOpacity(0.8), size: 16);
                  tileColor = Colors.white.withOpacity(0.03);
                  progressText = '已看完';
                } else if (progress > 0.01) {
                  // Watching
                  leadingIcon = Icon(Ionicons.play_circle_outline,
                      color: iconColor, size: 16);
                  progressText = '${(progress * 100).toStringAsFixed(0)}%';
                } else if (historyItem.isFromScan) {
                  // Scanned but not (really) watched
                  leadingIcon = Icon(Ionicons.play_circle_outline,
                      color: Colors.greenAccent.withOpacity(0.8), size: 16);
                  progressText = '未播放';
                } else {
                  // Exists in history, 0 progress, not from scan - unlikely state, treat as not found or specific icon?
                  // For now, let it fall through to the "Not Found in History" case or define a specific state.
                  // To treat as not found for icon/text:
                  leadingIcon = const Icon(Ionicons.play_circle_outline,
                      color: Colors.white38, size: 16);
                  progressText = '未找到';
                }
              } else {
                // No data in snapshot, even if connection is done (means not found in WatchHistoryManager)
                leadingIcon = const Icon(Ionicons.play_circle_outline,
                    color: Colors.white38, size: 16); // Grey play icon
                progressText = '未找到'; // Text indicating "Not Found"
              }
            }
            // Optional: Show a loading indicator while waiting for history data
            // else if (historySnapshot.connectionState == ConnectionState.waiting) {
            //   leadingIcon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
            // }

            return Material(
              color: tileColor ?? Colors.transparent,
              child: ListTile(
                dense: true,
                leading: leadingIcon,
                title: Text(episode.title,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9), fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                trailing: progressText != null
                    ? Text(progressText,
                        style: TextStyle(
                            color: progress > 0.95
                                ? Colors.greenAccent
                                    .withOpacity(0.9) // Green for "已看完"
                                : (progress > 0.01
                                    ? Colors.orangeAccent
                                    : (progressText == '未播放'
                                        ? Colors.greenAccent.withOpacity(0.9)
                                        : Colors
                                            .white54)), // Grey for "未找到" or other 0-progress cases
                            fontSize: 11))
                    : null,
                onTap: () async {
                  final WatchHistoryItem? historyItemToPlay;
                  if (historySnapshot.connectionState == ConnectionState.done &&
                      historySnapshot.data != null) {
                    // If we have snapshot data (meaning local file potentially exists)
                    historyItemToPlay = historySnapshot.data!;
                  } else {
                    // If snapshot is not done, or no data, means we don't have a WatchHistoryItem for it yet.
                    // This case implies it's an API episode not yet scanned/played.
                    BlurSnackBar.show(context, '媒体库中找不到此剧集的视频文件');
                    return;
                  }

                  if (historyItemToPlay.filePath.isNotEmpty) {
                    final file = File(historyItemToPlay.filePath);
                    if (await file.exists()) {
                      if (mounted) Navigator.pop(context, historyItemToPlay);
                    } else {
                      BlurSnackBar.show(
                          context, '文件已不存在于: ${historyItemToPlay.filePath}');
                    }
                  } else {
                    // This case should ideally not be reached if historyItemToPlay is from WatchHistoryManager
                    // and filePath is required by WatchHistoryItem.
                    BlurSnackBar.show(context, '该剧集记录缺少文件路径');
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null || _detailedAnime == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载详情失败:',
                  style: TextStyle(color: Colors.white.withOpacity(0.8))),
              const SizedBox(height: 8),
              Text(
                _error ?? '未知错误',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2)),
                onPressed: _fetchAnimeDetails,
                child: const Text('重试', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child:
                    const Text('关闭', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    final anime = _detailedAnime!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: 
              Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  anime.nameCn,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              IconButton(
                icon: const Icon(Ionicons.close_circle_outline,
                    color: Colors.white70, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          dividerColor: const Color.fromARGB(59, 255, 255, 255),
          dividerHeight: 3.0,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.only(top: 46, left: 15, right: 15),
          indicator: BoxDecoration(
            color: Colors.greenAccent, // 设置指示器的颜色

            borderRadius: BorderRadius.circular(30), // 设置圆角矩形的圆角半径
          ),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '简介'),
            Tab(text: '剧集'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryView(anime),
              _buildEpisodesListView(anime),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.3),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.of(context).padding.top + 20, 20, 20),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 15,
          blur: 25,
          alignment: Alignment.center,
          border: 0.5,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color.fromARGB(255, 219, 219, 219).withOpacity(0.2),
              const Color.fromARGB(255, 208, 208, 208).withOpacity(0.2),
            ],
            stops: const [0.1, 1],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.15),
              Colors.white.withOpacity(0.15),
            ],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }
}
