import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/cached_network_image_widget.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'dart:io';
import 'package:nipaplay/widgets/nipaplay_theme/tag_search_widget.dart';
import 'package:nipaplay/widgets/nipaplay_theme/rating_dialog.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:nipaplay/utils/message_helper.dart';

class FluentAnimeDetailPage extends StatefulWidget {
  final int animeId;

  const FluentAnimeDetailPage({super.key, required this.animeId});

  static Future<WatchHistoryItem?> show(BuildContext context, int animeId) {
    return showDialog<WatchHistoryItem>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ContentDialog(
        constraints: const BoxConstraints(
          maxWidth: 1000,
          maxHeight: 800,
        ),
        content: SizedBox(
          width: 1000,
          height: 800,
          child: FluentAnimeDetailPage(animeId: animeId),
        ),
      ),
    );
  }

  static void popIfOpen() {
    if (_FluentAnimeDetailPageState._openPageContext != null && _FluentAnimeDetailPageState._openPageContext!.mounted) {
      Navigator.of(_FluentAnimeDetailPageState._openPageContext!).pop();
      _FluentAnimeDetailPageState._openPageContext = null;
    }
  }

  @override
  State<FluentAnimeDetailPage> createState() => _FluentAnimeDetailPageState();
}

class _FluentAnimeDetailPageState extends State<FluentAnimeDetailPage>
    with SingleTickerProviderStateMixin {
  static BuildContext? _openPageContext;
  final BangumiService _bangumiService = BangumiService.instance;
  BangumiAnime? _detailedAnime;
  bool _isLoading = true;
  String? _error;
  int _currentTabIndex = 0;
  material.TabController? _tabController;
  
  // 弹弹play观看状态相关
  Map<int, bool> _dandanplayWatchStatus = {};
  
  // 弹弹play收藏状态相关
  bool _isFavorited = false;
  bool _isTogglingFavorite = false;

  // 弹弹play用户评分相关
  int _userRating = 0;
  bool _isLoadingUserRating = false;
  bool _isSubmittingRating = false;

  // 评分到评价文本的映射
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
    _openPageContext = context;
    _tabController = material.TabController(length: 2, vsync: this);
    _tabController!.addListener(_handleTabChange);
    
    _bangumiService.cleanExpiredDetailCache().then((_) {
      debugPrint("[番剧详情] 已清理过期的番剧详情缓存");
    });
    _fetchAnimeDetails();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppearanceSettings not needed in Fluent UI version
  }

  @override
  void dispose() {
    if (_openPageContext == context) {
      _openPageContext = null;
    }
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }
  
  void _handleTabChange() {
    if (_tabController!.indexIsChanging) {
      if (_tabController!.index == 1 && _detailedAnime != null && DandanplayService.isLoggedIn) {
        _fetchDandanplayWatchStatus(_detailedAnime!);
      }
      setState(() {
        _currentTabIndex = _tabController!.index;
      });
    }
  }

  Future<void> _fetchAnimeDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      BangumiAnime anime;

      if (kIsWeb) {
        try {
          final response = await http.get(Uri.parse('/api/bangumi/detail/${widget.animeId}'));
          if (response.statusCode == 200) {
            final data = json.decode(utf8.decode(response.bodyBytes));
            anime = BangumiAnime.fromJson(data as Map<String, dynamic>);
          } else {
            throw Exception('Failed to load details from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local details API: $e');
        }
      } else {
        anime = await BangumiService.instance.getAnimeDetails(widget.animeId);
      }
      
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

  Future<void> _fetchDandanplayWatchStatus(BangumiAnime anime) async {
    if (!DandanplayService.isLoggedIn || anime.episodeList == null || anime.episodeList!.isEmpty) {
      return;
    }
    
    setState(() {
      _isLoadingUserRating = true;
    });
    
    try {
      final List<int> episodeIds = anime.episodeList!
          .where((episode) => episode.id > 0)
          .map((episode) => episode.id)
          .toList();
      
      final Future<Map<int, bool>> watchStatusFuture = episodeIds.isNotEmpty 
          ? DandanplayService.getEpisodesWatchStatus(episodeIds)
          : Future.value(<int, bool>{});
          
      final Future<bool> favoriteStatusFuture = DandanplayService.isAnimeFavorited(anime.id);
      final Future<int> userRatingFuture = DandanplayService.getUserRatingForAnime(anime.id);
      
      final results = await Future.wait([watchStatusFuture, favoriteStatusFuture, userRatingFuture]);
      final watchStatus = results[0] as Map<int, bool>;
      final isFavorited = results[1] as bool;
      final userRating = results[2] as int;
      
      if (mounted) {
        setState(() {
          _dandanplayWatchStatus = watchStatus;
          _isFavorited = isFavorited;
          _userRating = userRating;
          _isLoadingUserRating = false;
        });
      }
    } catch (e) {
      debugPrint('[番剧详情] 获取弹弹play状态失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingUserRating = false;
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

  Widget _buildRatingStars(double? rating) {
    if (rating == null || rating < 0 || rating > 10) {
      return Text('N/A',
          style: FluentTheme.of(context).typography.caption?.copyWith(
              fontSize: 13));
    }

    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool halfStar = (rating - fullStars) >= 0.5;

    for (int i = 0; i < 10; i++) {
      if (i < fullStars) {
        stars.add(const Icon(FluentIcons.favorite_star_fill, size: 16));
      } else if (i == fullStars && halfStar) {
        stars.add(const Icon(FluentIcons.favorite_star, size: 16));
      } else {
        stars.add(Icon(FluentIcons.favorite_star, 
            size: 16, 
            color: FluentTheme.of(context).inactiveColor.withOpacity(0.3)));
      }
      if (i < 9) {
        stars.add(const SizedBox(width: 1));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _buildSummaryView(BangumiAnime anime) {
    final String summaryText = (anime.summary ?? '暂无简介')
        .replaceAll('<br>', ' ')
        .replaceAll('<br/>', ' ')
        .replaceAll('<br />', ' ');
    final airWeekday = anime.airWeekday;
    final String weekdayString =
        airWeekday != null && _weekdays.containsKey(airWeekday)
            ? _weekdays[airWeekday]!
            : '待定';
    
    String coverImageUrl = anime.imageUrl;
    if (kIsWeb) {
      final encodedUrl = base64Url.encode(utf8.encode(anime.imageUrl));
      coverImageUrl = '/api/image_proxy?url=$encodedUrl';
    }

    final bangumiRatingValue = anime.ratingDetails?['Bangumi评分'];
    String bangumiEvaluationText = '';
    if (bangumiRatingValue is num &&
        _ratingEvaluationMap.containsKey(bangumiRatingValue.round())) {
      bangumiEvaluationText =
          '(${_ratingEvaluationMap[bangumiRatingValue.round()]!})';
    }

    final valueStyle = FluentTheme.of(context).typography.body?.copyWith(fontSize: 13, height: 1.5);
    final boldKeyStyle = FluentTheme.of(context).typography.body?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, height: 1.5);
    final sectionTitleStyle = FluentTheme.of(context).typography.subtitle?.copyWith(fontWeight: FontWeight.bold);

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
                      style: valueStyle?.copyWith(height: 1.3),
                      children: [
                    TextSpan(
                        text: '${parts[0].trim()}: ',
                        style: boldKeyStyle?.copyWith(fontWeight: FontWeight.w600)),
                    TextSpan(text: parts[1].trim())
                  ]))));
        } else {
          metadataWidgets
              .add(Text(item, style: valueStyle?.copyWith(height: 1.3)));
        }
      }
    }

    List<Widget> titlesWidgets = [];
    if (anime.titles != null && anime.titles!.isNotEmpty) {
      titlesWidgets.add(const SizedBox(height: 8));
      titlesWidgets.add(Text('其他标题:', style: sectionTitleStyle));
      titlesWidgets.add(const SizedBox(height: 4));
      TextStyle aliasTextStyle = FluentTheme.of(context).typography.caption?.copyWith(fontSize: 12) ?? 
          const TextStyle(fontSize: 12);
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
                    style: valueStyle?.copyWith(
                        fontSize: 14, fontStyle: FontStyle.italic))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (anime.imageUrl.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: CachedNetworkImageWidget(
                          imageUrl: coverImageUrl,
                          width: 130,
                          height: 195,
                          fit: BoxFit.cover))),
            Expanded(
              child: SizedBox(
                height: 195,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(summaryText, style: valueStyle),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          if (bangumiRatingValue is num && bangumiRatingValue > 0) ...[
            RichText(
                text: TextSpan(children: [
              TextSpan(text: 'Bangumi评分: ', style: boldKeyStyle),
              WidgetSpan(
                  child: _buildRatingStars(bangumiRatingValue.toDouble())),
              TextSpan(
                  text: ' ${bangumiRatingValue.toStringAsFixed(1)} ',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              TextSpan(
                  text: bangumiEvaluationText,
                  style: FluentTheme.of(context).typography.caption?.copyWith(fontSize: 12))
            ])),
            const SizedBox(height: 6),
          ],
          
          // 弹弹play用户评分区域（仅在登录时显示）
          if (DandanplayService.isLoggedIn) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 我的打分显示
                if (_userRating > 0) ...[
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(text: '我的打分: ', style: boldKeyStyle?.copyWith(color: FluentTheme.of(context).accentColor)),
                      TextSpan(
                        text: '$_userRating 分 ',
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                          color: FluentTheme.of(context).accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      TextSpan(
                        text: '(${_ratingEvaluationMap[_userRating] ?? ''})',
                        style: FluentTheme.of(context).typography.caption?.copyWith(
                          color: FluentTheme.of(context).accentColor.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                ],
                
                // 我要打分按钮
                Button(
                  onPressed: _isSubmittingRating ? null : _showRatingDialog,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoadingUserRating || _isSubmittingRating) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: ProgressRing(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 4),
                      ] else
                        Icon(
                          _userRating > 0 ? FluentIcons.favorite_star_fill : FluentIcons.favorite_star,
                          size: 14,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        _userRating > 0 ? '修改评分' : '我要打分',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                              style: valueStyle?.copyWith(fontSize: 12),
                              children: [
                            TextSpan(
                                text: '$siteName: ',
                                style: boldKeyStyle?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal)),
                            TextSpan(
                                text: score.toStringAsFixed(1),
                                style: valueStyle?.copyWith(fontSize: 12))
                          ]));
                    }).toList())),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                TextSpan(text: '开播: ', style: boldKeyStyle),
                TextSpan(text: '${_formatDate(anime.airDate)} ($weekdayString)')
              ]))),
          if (anime.typeDescription != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '类型: ', style: boldKeyStyle),
                  TextSpan(text: anime.typeDescription)
                ]))),
          if (anime.totalEpisodes != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '话数: ', style: boldKeyStyle),
                  TextSpan(text: '${anime.totalEpisodes}话')
                ]))),
          if (anime.isOnAir != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(text: '状态: ', style: boldKeyStyle),
                  TextSpan(text: anime.isOnAir! ? '连载中' : '已完结')
                ]))),
          Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: RichText(
                  text: TextSpan(style: valueStyle, children: [
                TextSpan(
                    text: '追番状态: ',
                    style: boldKeyStyle?.copyWith(color: material.Colors.orangeAccent)),
                TextSpan(
                    text: anime.isFavorited! ? '已追' : '未追',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(color: material.Colors.orangeAccent.withOpacity(0.85)))
              ]))),
          if (anime.isNSFW ?? false)
            Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: RichText(
                    text: TextSpan(style: valueStyle, children: [
                  TextSpan(
                      text: '限制内容: ',
                      style: boldKeyStyle?.copyWith(color: material.Colors.redAccent)),
                  TextSpan(
                      text: '是',
                      locale:Locale("zh-Hans","zh"),
style: TextStyle(color: material.Colors.redAccent.withOpacity(0.85)))
                ]))),
          ...metadataWidgets,
          ...titlesWidgets,
          if (anime.tags != null && anime.tags!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('标签:', style: sectionTitleStyle),
                IconButton(
                  onPressed: () => _openTagSearch(),
                  icon: const Icon(FluentIcons.search, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: anime.tags!
                    .map((tag) => _FluentHoverableTag(
                          tag: tag,
                          onTap: () => _searchByTag(tag),
                        ))
                    .toList())
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEpisodesListView(BangumiAnime anime) {
    if (anime.episodeList == null || anime.episodeList!.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text('暂无剧集信息', style: FluentTheme.of(context).typography.body),
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
            Widget leadingIcon = const SizedBox(width: 20);
            String? progressText;
            double progress = 0.0;

            if (historySnapshot.connectionState == ConnectionState.done) {
              if (historySnapshot.hasData && historySnapshot.data != null) {
                final historyItem = historySnapshot.data!;
                progress = historyItem.watchProgress;
                if (progress > 0.95) {
                  leadingIcon = Icon(FluentIcons.check_mark, 
                      color: material.Colors.greenAccent.withOpacity(0.8), size: 16);
                  progressText = '已看完';
                } else if (progress > 0.01) {
                  leadingIcon = Icon(FluentIcons.play, 
                      color: material.Colors.orangeAccent.withOpacity(0.8), size: 16);
                  progressText = '${(progress * 100).toStringAsFixed(0)}%';
                } else if (historyItem.isFromScan) {
                  leadingIcon = Icon(FluentIcons.play,
                      color: material.Colors.greenAccent.withOpacity(0.8), size: 16);
                  progressText = '未播放';
                } else {
                  leadingIcon = Icon(FluentIcons.play,
                      color: FluentTheme.of(context).inactiveColor, size: 16);
                  progressText = '未找到';
                }
              } else {
                leadingIcon = Icon(FluentIcons.play,
                    color: FluentTheme.of(context).inactiveColor, size: 16);
                progressText = '未找到';
              }
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: leadingIcon,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(episode.title,
                          style: FluentTheme.of(context).typography.body?.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    // 显示弹弹play观看状态标注
                    if (DandanplayService.isLoggedIn && _dandanplayWatchStatus.containsKey(episode.id))
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _dandanplayWatchStatus[episode.id] == true 
                              ? material.Colors.green.withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                            color: _dandanplayWatchStatus[episode.id] == true 
                                ? material.Colors.green.withOpacity(0.6)
                                : Colors.transparent,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          _dandanplayWatchStatus[episode.id] == true ? '已看' : '',
                          locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: material.Colors.green.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: progressText != null
                    ? Text(progressText,
                        locale:Locale("zh-Hans","zh"),
style: TextStyle(
                            color: progress > 0.95
                                ? material.Colors.greenAccent.withOpacity(0.9)
                                : (progress > 0.01
                                    ? material.Colors.orangeAccent
                                    : (progressText == '未播放'
                                        ? material.Colors.greenAccent.withOpacity(0.9)
                                        : FluentTheme.of(context).inactiveColor)),
                            fontSize: 11))
                    : null,
                onPressed: () async {
                  final WatchHistoryItem? historyItemToPlay;
                  if (historySnapshot.connectionState == ConnectionState.done &&
                      historySnapshot.data != null) {
                    historyItemToPlay = historySnapshot.data!;
                  } else {
                    MessageHelper.showMessage(context, '媒体库中找不到此剧集的视频文件', isError: true);
                    return;
                  }

                  if (historyItemToPlay.filePath.isNotEmpty) {
                    final file = File(historyItemToPlay.filePath);
                    if (await file.exists()) {
                      final playableItem = PlayableItem(
                        videoPath: historyItemToPlay.filePath,
                        title: anime.nameCn,
                        subtitle: episode.title,
                        animeId: anime.id,
                        episodeId: episode.id,
                        historyItem: historyItemToPlay,
                      );
                      await PlaybackService().play(playableItem);

                      if (mounted) Navigator.pop(context);
                    } else {
                      MessageHelper.showMessage(context, '文件已不存在于: ${historyItemToPlay.filePath}', isError: true);
                    }
                  } else {
                    MessageHelper.showMessage(context, '该剧集记录缺少文件路径', isError: true);
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
      return const Center(child: ProgressRing());
    }
    if (_error != null || _detailedAnime == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载详情失败:', style: FluentTheme.of(context).typography.body),
              const SizedBox(height: 8),
              Text(
                _error ?? '未知错误',
                style: FluentTheme.of(context).typography.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _fetchAnimeDetails,
                child: const Text('重试'),
              ),
              const SizedBox(height: 10),
              Button(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  anime.nameCn,
                  style: FluentTheme.of(context).typography.title?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // 收藏按钮（仅当登录弹弹play时显示）
              if (DandanplayService.isLoggedIn) ...[
                IconButton(
                  icon: _isTogglingFavorite
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      :                         Icon(
                          _isFavorited ? FluentIcons.heart_fill : FluentIcons.heart,
                          size: 24,
                        ),
                  onPressed: _isTogglingFavorite ? null : _toggleFavorite,
                ),
              ],
              
              IconButton(
                icon: const Icon(FluentIcons.chrome_close, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        
        // Fluent UI TabView
        Expanded(
          child: TabView(
            currentIndex: _currentTabIndex,
            onChanged: (index) {
              setState(() {
                _currentTabIndex = index;
              });
              _tabController?.animateTo(index);
            },
            tabs: [
              Tab(
                text: const Text('简介'),
                icon: const Icon(FluentIcons.info, size: 16),
                body: _buildSummaryView(anime),
              ),
              Tab(
                text: const Text('剧集'),
                icon: const Icon(FluentIcons.video, size: 16),
                body: _buildEpisodesListView(anime),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minWidth: 800,
        minHeight: 600,
      ),
      content: _buildContent(),
    );
  }

  // 打开标签搜索页面
  void _openTagSearch() {
    final currentTags = _detailedAnime?.tags ?? [];
    
    showDialog(
      context: context,
      builder: (context) => TagSearchModal(
        preselectedTags: currentTags,
        onBeforeOpenAnimeDetail: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 通过单个标签搜索
  void _searchByTag(String tag) {
    showDialog(
      context: context,
      builder: (context) => TagSearchModal(
        prefilledTag: tag,
        onBeforeOpenAnimeDetail: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  // 切换收藏状态
  Future<void> _toggleFavorite() async {
    if (!DandanplayService.isLoggedIn) {
      MessageHelper.showMessage(context, '请先登录弹弹play账号', isError: true);
      return;
    }

    if (_detailedAnime == null || _isTogglingFavorite) {
      return;
    }

    setState(() {
      _isTogglingFavorite = true;
    });

    try {
      if (_isFavorited) {
        await DandanplayService.removeFavorite(_detailedAnime!.id);
        MessageHelper.showMessage(context, '已取消收藏');
      } else {
        await DandanplayService.addFavorite(
          animeId: _detailedAnime!.id,
          favoriteStatus: 'favorited',
        );
        MessageHelper.showMessage(context, '已添加到收藏');
      }

      setState(() {
        _isFavorited = !_isFavorited;
      });
    } catch (e) {
      debugPrint('[番剧详情] 切换收藏状态失败: $e');
      MessageHelper.showMessage(context, '操作失败: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isTogglingFavorite = false;
      });
    }
  }

  // 显示评分对话框
  void _showRatingDialog() {
    if (_detailedAnime == null) return;
    
    RatingDialog.show(
      context: context,
      animeTitle: _detailedAnime!.nameCn,
      initialRating: _userRating,
      onRatingSubmitted: _handleRatingSubmitted,
    );
  }

  // 处理评分提交
  Future<void> _handleRatingSubmitted(int rating) async {
    if (_detailedAnime == null) return;
    
    setState(() {
      _isSubmittingRating = true;
    });

    try {
      await DandanplayService.submitUserRating(
        animeId: _detailedAnime!.id,
        rating: rating,
      );
      
      if (mounted) {
        setState(() {
          _userRating = rating;
          _isSubmittingRating = false;
        });
        MessageHelper.showMessage(context, '评分提交成功');
      }
    } catch (e) {
      debugPrint('[番剧详情] 提交评分失败: $e');
      if (mounted) {
        setState(() {
          _isSubmittingRating = false;
        });
        MessageHelper.showMessage(context, '评分提交失败: ${e.toString()}', isError: true);
      }
    }
  }
}

// Fluent UI 可悬浮的标签widget
class _FluentHoverableTag extends StatefulWidget {
  final String tag;
  final VoidCallback onTap;

  const _FluentHoverableTag({
    required this.tag,
    required this.onTap,
  });

  @override
  State<_FluentHoverableTag> createState() => _FluentHoverableTagState();
}

class _FluentHoverableTagState extends State<_FluentHoverableTag> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered 
                ? FluentTheme.of(context).accentColor.withOpacity(0.1)
                : FluentTheme.of(context).cardColor,
            border: Border.all(
              color: _isHovered
                  ? FluentTheme.of(context).accentColor.withOpacity(0.5)
                  : FluentTheme.of(context).inactiveColor.withOpacity(0.2),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            widget.tag,
            style: FluentTheme.of(context).typography.caption?.copyWith(
              fontSize: 12,
              fontWeight: _isHovered ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}