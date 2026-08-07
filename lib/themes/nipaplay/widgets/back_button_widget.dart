import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'tooltip_bubble.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'blur_snackbar.dart';
import 'control_shadow.dart';
import 'keyboard_activatable.dart';

class BackButtonWidget extends StatefulWidget {
  final VideoPlayerState videoState;
  final Future<void> Function()? onExit;

  const BackButtonWidget({
    super.key,
    required this.videoState,
    this.onExit,
  });

  @override
  State<BackButtonWidget> createState() => _BackButtonWidgetState();
}

class _BackButtonWidgetState extends State<BackButtonWidget> {
  bool _isBackButtonPressed = false;
  bool _isHovered = false;
  bool _isFocused = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() => _isHovered = value);
  }

  void _setFocused(bool value) {
    if (_isFocused == value) {
      return;
    }
    setState(() => _isFocused = value);
  }

  Future<void> _handleBackAction() async {
    // 返回按钮直接绑定续播倒计时取消，确保退出时 snackbar 立即消失。
    AutoNextEpisodeService.instance.cancelAutoNext();

    if (mounted) {
      setState(() => _isBackButtonPressed = false);
    }
    try {
      if (widget.onExit != null) {
        await widget.onExit!();
        return;
      }
      // 先调用handleBackButton处理截图
      final shouldExit = await widget.videoState.handleBackButton();
      if (!shouldExit) return;
      // 然后重置播放器状态
      await widget.videoState.resetPlayer();
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '重置播放器时出错: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.videoState.hasVideo &&
        !(globals.isDesktop && widget.videoState.isFullscreen))) {
      return const SizedBox.shrink();
    }
    final isActive = _isHovered || _isFocused;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.videoState.showControls ? 1.0 : 0.0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        offset: Offset(widget.videoState.showControls ? 0 : -0.1, 0),
        child: MouseRegion(
          onEnter: (_) {
            widget.videoState.setControlsHovered(true);
            _setHovered(true);
          },
          onExit: (_) {
            widget.videoState.setControlsHovered(false);
            _setHovered(false);
          },
          child: TooltipBubble(
            text: '返回',
            showOnRight: false,
            verticalOffset: 8,
            child: KeyboardActivatable(
              onActivate: () {
                _handleBackAction();
              },
              onFocusChange: _setFocused,
              child: GestureDetector(
                onTapDown: (_) => setState(() => _isBackButtonPressed = true),
                onTapUp: (_) {
                  _handleBackAction();
                },
                onTapCancel: () => setState(() => _isBackButtonPressed = false),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: _isBackButtonPressed ? 0.9 : (isActive ? 1.1 : 1.0),
                  child: ControlIconShadow(
                    child: const Icon(
                      Ionicons.chevron_back_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
