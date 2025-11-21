import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as p;

class FluentHistoryAllDialog extends StatefulWidget {
  final List<WatchHistoryItem> history;
  final Function(WatchHistoryItem) onItemTap;

  const FluentHistoryAllDialog({
    super.key,
    required this.history,
    required this.onItemTap,
  });

  @override
  State<FluentHistoryAllDialog> createState() => _FluentHistoryAllDialogState();
}

class _FluentHistoryAllDialogState extends State<FluentHistoryAllDialog> {
  static const int _pageSize = 20;
  final List<WatchHistoryItem> _displayedHistory = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMoreData = true;
  late List<WatchHistoryItem> _validHistory;

  @override
  void initState() {
    super.initState();
    _validHistory = widget.history.where((item) => item.duration > 0).toList();
    _loadMoreItems();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100 && !_isLoading && _hasMoreData) {
        _loadMoreItems();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMoreItems() {
    if (_isLoading || !_hasMoreData) return;
    setState(() => _isLoading = true);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final startIndex = _displayedHistory.length;
      final endIndex = startIndex + _pageSize;
      final itemsToAdd = _validHistory.length > endIndex
          ? _validHistory.sublist(startIndex, endIndex)
          : _validHistory.sublist(startIndex);
      
      setState(() {
        _displayedHistory.addAll(itemsToAdd);
        _isLoading = false;
        _hasMoreData = _displayedHistory.length < _validHistory.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: Text('全部观看记录 (${_validHistory.length})'),
      content: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        width: MediaQuery.of(context).size.width * 0.8,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _displayedHistory.length + (_hasMoreData ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _displayedHistory.length) {
              return const Center(child: ProgressRing());
            }
            final item = _displayedHistory[index];
            return _buildListItem(item);
          },
        ),
      ),
      actions: [
        Button(
          child: const Text('关闭'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildListItem(WatchHistoryItem item) {
    return ListTile(
      leading: SizedBox(
        width: 80,
        height: 50,
        child: item.thumbnailPath != null && File(item.thumbnailPath!).existsSync()
            ? Image.file(File(item.thumbnailPath!), fit: BoxFit.cover)
            : Container(color: Colors.grey[170], child: const Icon(FluentIcons.video)),
      ),
      title: Text(
        item.animeName.isEmpty ? p.basename(item.filePath) : item.animeName,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.episodeTitle ?? p.basename(item.filePath),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          ProgressBar(value: item.watchProgress * 100),
        ],
      ),
      trailing: Text("${(item.watchProgress * 100).toInt()}%"),
      onPressed: () => widget.onItemTap(item),
    );
  }
}
