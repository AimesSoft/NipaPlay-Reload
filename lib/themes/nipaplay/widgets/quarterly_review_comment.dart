import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

/// Matches the accent treatment of "my comment" in the anime detail page.
class QuarterlyReviewComment extends StatefulWidget {
  const QuarterlyReviewComment({
    super.key,
    required this.comment,
    this.updatedAt,
    this.onEdit,
  });

  final String comment;
  final int? updatedAt;
  final VoidCallback? onEdit;

  static const _bodyStyle = TextStyle(fontSize: 12, height: 1.4);
  static const _headingStyle =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
  static const _timeStyle = TextStyle(fontSize: 10);

  static double _textHeight(
      BuildContext context, String text, TextStyle style, double width,
      {int? maxLines}) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
      locale: Localizations.maybeLocaleOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// Reserve two complete text lines, including the fixed heading and date.
  /// Use the same font metrics as the rendered text, including text scaling.
  static double minimumHeight(BuildContext context,
      {required double width,
      required String comment,
      required bool hasTimestamp,
      required bool editable}) {
    final innerWidth = width - 17.6; // Padding plus the panel border.
    final headingHeight = _textHeight(
        context, '我的短评', _headingStyle, innerWidth - 19 - (editable ? 22 : 0),
        maxLines: 1);
    final bodyHeight =
        _textHeight(context, comment, _bodyStyle, innerWidth, maxLines: 2);
    final twoLineHeight =
        _textHeight(context, '短评\n短评', _bodyStyle, innerWidth, maxLines: 2);
    final dateHeight = hasTimestamp
        ? _textHeight(context, '2026/09/29 20:05', _timeStyle, innerWidth - 15,
            maxLines: 1)
        : 0.0;
    final header = [headingHeight, 15.0, if (editable) 22.0]
        .reduce((a, b) => a > b ? a : b);
    return (17.6 +
            header +
            4 +
            (bodyHeight > twoLineHeight ? bodyHeight : twoLineHeight) +
            (hasTimestamp ? 4 + (dateHeight > 11 ? dateHeight : 11) : 0) +
            1)
        .ceilToDouble();
  }

  @override
  State<QuarterlyReviewComment> createState() => _QuarterlyReviewCommentState();
}

class _QuarterlyReviewCommentState extends State<QuarterlyReviewComment> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant QuarterlyReviewComment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comment != widget.comment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _dateLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final accent = AppAccentColors.current;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 15, color: accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text('我的短评',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuarterlyReviewComment._headingStyle
                        .copyWith(color: foreground.withValues(alpha: 0.72))),
              ),
              if (widget.onEdit != null)
                Tooltip(
                  message: '编辑短评',
                  child: Semantics(
                    button: true,
                    label: '编辑短评',
                    child: HoverScaleTextButton(
                      onPressed: widget.onEdit,
                      idleColor: foreground.withValues(alpha: 0.6),
                      hoverColor: accent,
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.edit_outlined, size: 14),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final textHeight = QuarterlyReviewComment._textHeight(
                  context,
                  widget.comment,
                  QuarterlyReviewComment._bodyStyle,
                  constraints.maxWidth);
              final needsScrollbar = textHeight > constraints.maxHeight;
              return RawScrollbar(
                controller: _scrollController,
                thumbVisibility: needsScrollbar,
                interactive: true,
                thickness: 3,
                radius: const Radius.circular(3),
                thumbColor: accent.withValues(alpha: 0.5),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    // Preserve the original line wrapping for short comments.
                    padding: EdgeInsets.only(right: needsScrollbar ? 8 : 0),
                    child: Text(widget.comment,
                        style: QuarterlyReviewComment._bodyStyle.copyWith(
                            color: foreground.withValues(alpha: 0.82))),
                  ),
                ),
              );
            }),
          ),
          if (widget.updatedAt != null) ...[
            const SizedBox(height: 4),
            Semantics(
              label: '评论更新于 ${_dateLabel(widget.updatedAt!)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 11, color: foreground.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(_dateLabel(widget.updatedAt!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuarterlyReviewComment._timeStyle.copyWith(
                            color: foreground.withValues(alpha: 0.5))),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
