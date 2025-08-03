import 'package:fluent_ui/fluent_ui.dart';

/// FluentUI风格的自定义InfoBar组件
class FluentInfoBar extends StatelessWidget {
  final String title;
  final String? content;
  final InfoBarSeverity severity;
  final VoidCallback? onClose;

  const FluentInfoBar({
    super.key,
    required this.title,
    this.content,
    this.severity = InfoBarSeverity.info,
    this.onClose,
  });

  Color _getBackgroundColor() {
    switch (severity) {
      case InfoBarSeverity.info:
        return const Color(0xFF0078D4).withOpacity(0.1);
      case InfoBarSeverity.success:
        return const Color(0xFF107C10).withOpacity(0.1);
      case InfoBarSeverity.warning:
        return const Color(0xFFFF8C00).withOpacity(0.1);
      case InfoBarSeverity.error:
        return const Color(0xFFD13438).withOpacity(0.1);
    }
  }

  Color _getBorderColor() {
    switch (severity) {
      case InfoBarSeverity.info:
        return const Color(0xFF0078D4);
      case InfoBarSeverity.success:
        return const Color(0xFF107C10);
      case InfoBarSeverity.warning:
        return const Color(0xFFFF8C00);
      case InfoBarSeverity.error:
        return const Color(0xFFD13438);
    }
  }

  IconData _getIcon() {
    switch (severity) {
      case InfoBarSeverity.info:
        return FluentIcons.info;
      case InfoBarSeverity.success:
        return FluentIcons.check_mark;
      case InfoBarSeverity.warning:
        return FluentIcons.warning;
      case InfoBarSeverity.error:
        return FluentIcons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        border: Border.all(
          color: _getBorderColor(),
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            color: _getBorderColor(),
            size: 16,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (content != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    content!,
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(FluentIcons.chrome_close, size: 12),
              onPressed: onClose,
              style: ButtonStyle(
                padding: WidgetStateProperty.all(const EdgeInsets.all(2)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 显示自定义FluentUI风格的InfoBar
  static void show(
    BuildContext context,
    String title, {
    String? content,
    InfoBarSeverity severity = InfoBarSeverity.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return FluentInfoBar(
          title: title,
          content: content,
          severity: severity,
          onClose: close,
        );
      },
      duration: duration,
    );
  }
}