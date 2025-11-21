import 'package:fluent_ui/fluent_ui.dart';
import 'dart:async';

class FluentLoadingOverlay extends StatefulWidget {
  final List<String> messages;
  final double? width;
  final double? height;
  final bool highPriorityAnimation;
  
  // 新增：媒体信息参数
  final String? animeTitle;
  final String? episodeTitle;
  final String? fileName;
  final String? coverImageUrl;

  const FluentLoadingOverlay({
    super.key,
    required this.messages,
    this.width,
    this.height,
    this.highPriorityAnimation = true,
    this.animeTitle,
    this.episodeTitle,
    this.fileName,
    this.coverImageUrl,
  });

  @override
  State<FluentLoadingOverlay> createState() => _FluentLoadingOverlayState();
}

class _FluentLoadingOverlayState extends State<FluentLoadingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _fadeController;
  final ScrollController _scrollController = ScrollController();
  String _currentMessage = '';
  int _currentMessageIndex = 0;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _updateCurrentMessage();
    _fadeController.forward();
  }

  @override
  void didUpdateWidget(FluentLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages) {
      _updateCurrentMessage();
      _scrollToBottom();
    }
  }

  void _updateCurrentMessage() {
    if (widget.messages.isNotEmpty) {
      _currentMessageIndex = widget.messages.length - 1;
      _currentMessage = widget.messages[_currentMessageIndex];
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _fadeController.dispose();
    _scrollController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final screenSize = MediaQuery.of(context).size;
    
    final effectiveWidth = (widget.width ?? (screenSize.width * 0.8 * 2.5)).clamp(600.0, screenSize.width * 0.9);
    final effectiveHeight = (screenSize.height * 0.5).clamp(300.0, screenSize.height * 0.7);
    
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: FadeTransition(
          opacity: _fadeController,
          child: Container(
            width: effectiveWidth,
            height: effectiveHeight,
            decoration: BoxDecoration(
              color: theme.micaBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.resources.controlStrokeColorDefault,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧：媒体信息区域 (1/3 宽度)
                  Expanded(
                    flex: 1,
                    child: _buildMediaInfoSection(theme),
                  ),
                  // 分隔线
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.typography.body?.color?.withOpacity(0.1) ?? Colors.grey.withOpacity(0.1),
                          theme.typography.body?.color?.withOpacity(0.3) ?? Colors.grey.withOpacity(0.3),
                          theme.typography.body?.color?.withOpacity(0.1) ?? Colors.grey.withOpacity(0.1),
                        ],
                      ),
                    ),
                  ),
                  // 右侧：加载信息区域 (2/3 宽度)
                  Expanded(
                    flex: 2,
                    child: _buildLoadingMessagesSection(theme),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 构建左侧媒体信息区域
  Widget _buildMediaInfoSection(FluentThemeData theme) {
    final titleStyle = theme.typography.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    
    final subtitleStyle = theme.typography.body?.copyWith(
      color: theme.typography.body?.color?.withOpacity(0.8),
      fontWeight: FontWeight.w500,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面图片占位
        if (widget.coverImageUrl != null)
          Container(
            width: 120,
            height: 160, // 3:4 竖屏比例
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: theme.resources.controlStrokeColorSecondary,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                widget.coverImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.resources.controlStrokeColorSecondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      FluentIcons.video,
                      size: 50,
                      color: theme.typography.body?.color?.withOpacity(0.6),
                    ),
                  );
                },
              ),
            ),
          )
        else
          Container(
            width: 120,
            height: 160, // 3:4 竖屏比例
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.resources.controlStrokeColorSecondary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              FluentIcons.video,
              size: 50,
              color: theme.typography.body?.color?.withOpacity(0.6),
            ),
          ),
        
        // 动画名称
        if (widget.animeTitle != null && widget.animeTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.animeTitle!,
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        
        // 集数标题
        if (widget.episodeTitle != null && widget.episodeTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.episodeTitle!,
              style: subtitleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        
        // 文件名（如果没有动画名时显示）
        if ((widget.animeTitle == null || widget.animeTitle!.isEmpty) && 
            widget.fileName != null && widget.fileName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.fileName!,
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // 构建右侧加载消息区域
  Widget _buildLoadingMessagesSection(FluentThemeData theme) {
    return Column(
      children: [
        // 进度环
        SizedBox(
          width: 32,
          height: 32,
          child: AnimatedBuilder(
            animation: _progressController,
            builder: (context, child) {
              return ProgressRing(
                value: widget.highPriorityAnimation ? null : 0.7,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // 消息文本区域
        Expanded(
          child: widget.messages.isEmpty
              ? Center(
                  child: Text(
                    '正在加载...',
                    style: theme.typography.body,
                  ),
                )
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    shrinkWrap: false,
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final isLatest = index == widget.messages.length - 1;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: AnimatedOpacity(
                          opacity: isLatest ? 1.0 : 0.7,
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            widget.messages[index],
                            style: theme.typography.body?.copyWith(
                              color: isLatest 
                                  ? theme.accentColor
                                  : theme.typography.body?.color?.withOpacity(0.8),
                              fontWeight: isLatest ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}