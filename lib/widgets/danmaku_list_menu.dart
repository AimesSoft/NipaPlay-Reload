import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'base_settings_menu.dart'; // Import the base menu

// Convert to StatefulWidget
class DanmakuListMenu extends StatefulWidget {
  final VoidCallback onClose;

  const DanmakuListMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<DanmakuListMenu> createState() => _DanmakuListMenuState();
}

class _DanmakuListMenuState extends State<DanmakuListMenu> {
  late final List<Map<String, dynamic>> _allSortedDanmakus;
  final List<Map<String, dynamic>> _displayedDanmakus = [];
  final ScrollController _scrollController = ScrollController();
  final int _batchSize = 100; // Number of items to load each time
  bool _isLoadingMore = false;
  bool _hasMore = true; // Track if there are more items to load

  @override
  void initState() {
    super.initState();
    // Get the full, pre-sorted list from VideoPlayerState
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _allSortedDanmakus = videoState.danmakuList; 
    _loadMore(); // Load the initial batch

    _scrollController.addListener(() {
      // Load more when near the bottom
      if (_scrollController.position.extentAfter < 300 && // Threshold before reaching end
          !_isLoadingMore &&
          _hasMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMore() {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate a small delay for loading, can be removed if data is local
    // Future.delayed(Duration(milliseconds: 50), () {
      final currentLength = _displayedDanmakus.length;
      final nextItemsEnd = (currentLength + _batchSize) > _allSortedDanmakus.length
          ? _allSortedDanmakus.length
          : currentLength + _batchSize;

      // Get the next batch of items
      final nextItems = _allSortedDanmakus.sublist(currentLength, nextItemsEnd);

      setState(() {
        _displayedDanmakus.addAll(nextItems);
        _isLoadingMore = false;
        _hasMore = _displayedDanmakus.length < _allSortedDanmakus.length;
      });
    // });
  }

  @override
  Widget build(BuildContext context) {
    // BaseSettingsMenu setup remains the same
    return BaseSettingsMenu(
      title: '弹幕列表 (${_allSortedDanmakus.length}条)', // Show total count
      onClose: widget.onClose, 
      content: _allSortedDanmakus.isEmpty
          ? const Padding( 
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(child: Text('当前没有弹幕', style: TextStyle(color: Colors.white70))),
            )
          : ListView.builder(
              controller: _scrollController, // Attach the scroll controller
              padding: const EdgeInsets.symmetric(vertical: 8), 
              shrinkWrap: true, 
              physics: const ClampingScrollPhysics(), 
              // Item count is displayed items + 1 for loading indicator if needed
              itemCount: _hasMore ? _displayedDanmakus.length + 1 : _displayedDanmakus.length,
              itemBuilder: (context, index) {
                // If it's the last item and there's more to load, show indicator
                if (index == _displayedDanmakus.length && _hasMore) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                  );
                }

                // Build the actual ListTile
                final danmaku = _displayedDanmakus[index];
                final timeInSeconds = (danmaku['time'] as double?) ?? 0.0;
                final minutes = (timeInSeconds / 60).floor();
                final seconds = (timeInSeconds % 60).floor();
                final timeString = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                final text = (danmaku['content'] as String?) ?? '无效弹幕';
                final typeStringValue = (danmaku['type'] as String?) ?? 'scroll';
                String displayTypeString = "滚动";
                if (typeStringValue == 'top') displayTypeString = "顶部";
                if (typeStringValue == 'bottom') displayTypeString = "底部";

                return ListTile(
                  title: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('时间: $timeString  类型: $displayTypeString', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  dense: true,
                );
              },
            ),
    );
  }
} 