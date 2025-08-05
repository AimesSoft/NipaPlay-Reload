import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_history_card.dart';

class FluentWatchHistoryList extends StatelessWidget {
  final List<WatchHistoryItem> history;
  final Function(WatchHistoryItem) onItemTap;
  final VoidCallback onShowMore;

  const FluentWatchHistoryList({
    super.key,
    required this.history,
    required this.onItemTap,
    required this.onShowMore,
  });

  @override
  Widget build(BuildContext context) {
    final validHistoryItems = history.where((item) => item.duration > 0).toList();
    if (validHistoryItems.isEmpty) {
      return _buildEmptyState();
    }

    String? latestUpdatedPath;
    DateTime latestTime = DateTime(2000);
    for (var item in validHistoryItems) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        latestUpdatedPath = item.filePath;
      }
    }

    final screenWidth = MediaQuery.of(context).size.width;
    const cardWidth = 166.0; // Card width (150) + padding (16)
    final visibleCards = (screenWidth / cardWidth).floor();
    final showViewMoreButton = validHistoryItems.length > visibleCards + 2;
    final displayItemCount = showViewMoreButton ? visibleCards + 2 : validHistoryItems.length;

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: showViewMoreButton ? displayItemCount + 1 : validHistoryItems.length,
      itemBuilder: (context, index) {
        if (showViewMoreButton && index == displayItemCount) {
          return _buildShowMoreButton(context);
        }

        if (index < validHistoryItems.length) {
          final item = validHistoryItems[index];
          final isLatestUpdated = item.filePath == latestUpdatedPath;
          return Padding(
            key: ValueKey('${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}'),
            padding: const EdgeInsets.only(right: 16),
            child: FluentHistoryCard(
              item: item,
              isLatestUpdated: isLatestUpdated,
              onTap: () => onItemTap(item),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FluentIcons.history, size: 48),
          SizedBox(height: 16),
          Text('暂无观看记录，已扫描的视频可在媒体库查看'),
        ],
      ),
    );
  }

  Widget _buildShowMoreButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        width: 150,
        child: Button(
          onPressed: onShowMore,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FluentIcons.more, size: 32),
                SizedBox(height: 8),
                Text("查看更多"),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
