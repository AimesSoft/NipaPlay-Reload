import 'dart:io';
import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as path;
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

class HistoryAllModal extends StatefulWidget {
  final List<WatchHistoryItem> history;
  final Function(WatchHistoryItem) onItemTap;

  const HistoryAllModal({
    super.key,
    required this.history, 
    required this.onItemTap,
  });

  @override
  State<HistoryAllModal> createState() => _HistoryAllModalState();
}

class _HistoryAllModalState extends State<HistoryAllModal> {
  // 分页控制参数
  static const int _pageSize = 20; // 每页加载数量
  final List<WatchHistoryItem> _displayedHistory = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMoreData = true;
  late List<WatchHistoryItem> _validHistory;
  
  @override
  void initState() {
    super.initState();
    
    // 过滤出有效的观看记录（持续时间大于0）
    _validHistory = widget.history.where((item) => item.duration > 0).toList();
    
    // 初始加载第一页
    _loadMoreItems();
    
    // 添加滚动监听器，实现触底加载更多
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 300 && // 预加载，滚动到距离底部300像素时
          !_isLoading && 
          _hasMoreData) {
        _loadMoreItems();
      }
    });
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  // 加载更多数据
  void _loadMoreItems() {
    if (_isLoading || !_hasMoreData) return;
    
    setState(() {
      _isLoading = true;
    });
    
    // 模拟异步加载，防止UI阻塞
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 20,
        blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.3),
            Colors.white.withOpacity(0.25),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.5),
            Colors.white.withOpacity(0.5),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                "全部观看记录 (${_validHistory.length})",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Platform.isAndroid || Platform.isIOS
                ? ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _displayedHistory.length + (_hasMoreData ? 1 : 0),
                    itemBuilder: (context, index) {
                      // 判断是否是加载更多项
                      if (index == _displayedHistory.length) {
                        return _buildLoadingIndicator();
                      }
                      
                      final item = _displayedHistory[index];
                      
                      return HistoryListItem(
                        key: ValueKey('history_${item.filePath}'),
                        item: item,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onItemTap(item);
                        },
                      );
                    },
                  )
                : Scrollbar(
                    controller: _scrollController,
                    radius: const Radius.circular(2),
                    thickness: 4,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _displayedHistory.length + (_hasMoreData ? 1 : 0),
                      itemBuilder: (context, index) {
                        // 判断是否是加载更多项
                        if (index == _displayedHistory.length) {
                          return _buildLoadingIndicator();
                        }
                        
                        final item = _displayedHistory[index];
                        
                        return HistoryListItem(
                          key: ValueKey('history_${item.filePath}'),
                          item: item,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onItemTap(item);
                          },
                        );
                      },
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 加载更多指示器
  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
      ),
    );
  }
} 

/// 历史记录列表项组件
/// 将列表项抽取为独立的StatelessWidget可以减少主状态组件的重建范围
class HistoryListItem extends StatelessWidget {
  final WatchHistoryItem item;
  final VoidCallback onTap;

  const HistoryListItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        height: 70,
        decoration: BoxDecoration(
          // 使用不透明背景色
          //color: const Color.fromARGB(255, 255, 255, 255),
          // 添加细微渐变效果
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.2),
              Colors.white.withOpacity(0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          // 添加精细的边框增强立体感
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 0.5,
          ),
          // 添加阴影增强立体感
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // 缩略图
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 72,
                      height: 48,
                      child: item.thumbnailPath != null && 
                             File(item.thumbnailPath!).existsSync()
                          ? Image.file(
                              File(item.thumbnailPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildDefaultThumbnail(),
                            )
                          : _buildDefaultThumbnail(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 标题和副标题
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.animeName.isEmpty
                              ? path.basename(item.filePath)
                              : item.animeName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.episodeTitle ?? path.basename(item.filePath),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 进度
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.watchProgress > 0.9
                          ? Colors.greenAccent.withOpacity(0.3)
                          : Colors.orangeAccent.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${(item.watchProgress * 100).toInt()}%",
                      style: TextStyle(
                        color: item.watchProgress > 0.9
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.white30, size: 24),
      ),
    );
  }
} 