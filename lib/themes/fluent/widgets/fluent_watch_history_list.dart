import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/fluent/widgets/fluent_history_card.dart';

class FluentWatchHistoryList extends StatefulWidget {
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
  State<FluentWatchHistoryList> createState() => _FluentWatchHistoryListState();
}

class _FluentWatchHistoryListState extends State<FluentWatchHistoryList> {
  List<WatchHistoryItem> _validHistoryItems = const [];
  String? _latestUpdatedPath;
  int _displayItemCount = 0;
  bool _showViewMoreButton = false;
  double _lastKnownWidth = 0;
  List<WatchHistoryItem>? _lastHistoryRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recomputeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant FluentWatchHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recomputeIfNeeded(force: widget.history != _lastHistoryRef);
  }

  void _recomputeIfNeeded({bool force = false}) {
    final width = MediaQuery.of(context).size.width;
    if (!force && width == _lastKnownWidth && widget.history == _lastHistoryRef) return;

    _lastKnownWidth = width;
    _lastHistoryRef = widget.history;

    _validHistoryItems = widget.history.where((item) => item.duration > 0).toList();

    _latestUpdatedPath = null;
    DateTime latestTime = DateTime(2000);
    for (var item in _validHistoryItems) {
      if (item.lastWatchTime.isAfter(latestTime)) {
        latestTime = item.lastWatchTime;
        _latestUpdatedPath = item.filePath;
      }
    }

    const cardWidth = 166.0; // Card width (150) + padding (16)
    final visibleCards = (_lastKnownWidth / cardWidth).floor();
    _showViewMoreButton = _validHistoryItems.length > visibleCards + 2;
    _displayItemCount =
        _showViewMoreButton ? visibleCards + 2 : _validHistoryItems.length;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_validHistoryItems.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount:
          _showViewMoreButton ? _displayItemCount + 1 : _validHistoryItems.length,
      itemBuilder: (context, index) {
        if (_showViewMoreButton && index == _displayItemCount) {
          return _buildShowMoreButton(context);
        }

        if (index < _validHistoryItems.length) {
          final item = _validHistoryItems[index];
          final isLatestUpdated = item.filePath == _latestUpdatedPath;
          return Padding(
            key: ValueKey(
                '${item.filePath}_${item.lastWatchTime.millisecondsSinceEpoch}'),
            padding: const EdgeInsets.only(right: 16),
            child: FluentHistoryCard(
              item: item,
              isLatestUpdated: isLatestUpdated,
              onTap: () => widget.onItemTap(item),
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
          onPressed: widget.onShowMore,
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
