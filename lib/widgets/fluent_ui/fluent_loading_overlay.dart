import 'package:fluent_ui/fluent_ui.dart';
import 'dart:async';

class FluentLoadingOverlay extends StatefulWidget {
  final List<String> messages;
  final double? width;
  final double? height;
  final bool highPriorityAnimation;

  const FluentLoadingOverlay({
    super.key,
    required this.messages,
    this.width,
    this.height,
    this.highPriorityAnimation = true,
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
    
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: FadeTransition(
          opacity: _fadeController,
          child: Container(
            width: widget.width ?? (screenSize.width * 0.8).clamp(300.0, 500.0),
            constraints: BoxConstraints(
              minHeight: 120,
              maxHeight: screenSize.height * 0.6,
            ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  // 消息文本 - 使用 Flexible 而不是 Expanded
                  Flexible(
                    child: widget.messages.isEmpty
                        ? const SizedBox.shrink()
                        : ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 40,
                              maxHeight: 200,
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(
                                scrollbars: false,
                              ),
                              child: ListView.builder(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                shrinkWrap: true,
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
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  );
                                },
                              ),
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
}