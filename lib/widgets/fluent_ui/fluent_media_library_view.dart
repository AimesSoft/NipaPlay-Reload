import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';

/// A callback for when an anime card is tapped.
typedef OnAnimeTap = void Function(int animeId);

/// A view that displays the media library with a Fluent UI look.
///
/// This widget is stateless and responsible only for rendering the UI
/// based on the state provided to it.
class FluentMediaLibraryView extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final List<WatchHistoryItem> items;
  final Map<int, BangumiAnime> fullAnimeData;
  final Map<int, String> persistedImageUrls;
  final bool isJellyfinConnected;
  final ScrollController scrollController;

  final VoidCallback onRefresh;
  final VoidCallback onConnectServer;
  final OnAnimeTap onAnimeTap;

  const FluentMediaLibraryView({
    super.key,
    required this.isLoading,
    this.error,
    required this.items,
    required this.fullAnimeData,
    required this.persistedImageUrls,
    required this.isJellyfinConnected,
    required this.scrollController,
    required this.onRefresh,
    required this.onConnectServer,
    required this.onAnimeTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('本地媒体库'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('刷新'),
              onPressed: onRefresh,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.cloud_add),
              label: const Text('连接媒体服务器'),
              onPressed: onConnectServer,
            ),
          ],
        ),
      ),
      content: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isLoading) {
      return const Center(child: ProgressBar());
    }

    if (error != null) {
      return _buildErrorState(context);
    }

    if (items.isEmpty) {
      return _buildEmptyState();
    }

    return _buildGridView();
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: InfoBar(
        title: const Text('加载媒体库失败'),
        content: Text(error!),
        severity: InfoBarSeverity.error,
        isLong: true,
        action: Button(
          child: const Text('重试'),
          onPressed: onRefresh,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '媒体库为空',
            locale:Locale("zh-Hans","zh"),
style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '观看过的动画将显示在这里。',
            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          if (!isJellyfinConnected)
            FilledButton(
              onPressed: onConnectServer,
              child: const Text('添加媒体服务器'),
            ),
        ],
      ),
    );
  }

  Widget _buildGridView() {
    final gridView = GridView.builder(
      controller: scrollController,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 7 / 12,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      padding: const EdgeInsets.all(16.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final historyItem = items[index];
        final animeId = historyItem.animeId;

        String imageUrlToDisplay = historyItem.thumbnailPath ?? '';
        String nameToDisplay = historyItem.animeName.isNotEmpty
            ? historyItem.animeName
            : (historyItem.episodeTitle ?? '未知动画');

        if (animeId != null) {
          if (fullAnimeData.containsKey(animeId)) {
            final fetchedData = fullAnimeData[animeId]!;
            if (fetchedData.imageUrl.isNotEmpty) imageUrlToDisplay = fetchedData.imageUrl;
            if (fetchedData.nameCn.isNotEmpty) {
              nameToDisplay = fetchedData.nameCn;
            } else if (fetchedData.name.isNotEmpty) {
              nameToDisplay = fetchedData.name;
            }
          } else if (persistedImageUrls.containsKey(animeId)) {
            imageUrlToDisplay = persistedImageUrls[animeId]!;
          }
        }

        return FluentAnimeCard(
          key: ValueKey(animeId ?? historyItem.filePath),
          name: nameToDisplay,
          imageUrl: imageUrlToDisplay,
          source: FluentAnimeCard.getSourceFromFilePath(historyItem.filePath),
          rating: animeId != null && fullAnimeData.containsKey(animeId)
              ? fullAnimeData[animeId]!.rating
              : null,
          ratingDetails: animeId != null && fullAnimeData.containsKey(animeId)
              ? fullAnimeData[animeId]!.ratingDetails
              : null,
          onTap: () {
            if (animeId != null) {
              onAnimeTap(animeId);
            } else {
              _showErrorSnackbar(context, '无法打开详情，动画ID未知');
            }
          },
        );
      },
    );

    return Scrollbar(
      controller: scrollController,
      child: gridView,
    );
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('提示'),
          content: Text(message),
          severity: InfoBarSeverity.warning,
          isLong: true,
          onClose: close,
        );
      },
      duration: const Duration(seconds: 3),
    );
  }
}
