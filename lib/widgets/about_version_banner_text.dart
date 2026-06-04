import 'package:flutter/widgets.dart';

class AboutVersionBannerText extends StatelessWidget {
  const AboutVersionBannerText({
    super.key,
    required this.text,
    required this.targetLabel,
    required this.style,
    this.textAlign = TextAlign.center,
  });

  static const String _productName = 'NipaPlay Reload';

  final String text;
  final String targetLabel;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final label = targetLabel.trim();
    if (label.isEmpty || !text.startsWith(_productName)) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
      );
    }

    final defaultFontSize = DefaultTextStyle.of(context).style.fontSize ?? 24;
    final baseFontSize = style.fontSize ?? defaultFontSize;
    final versionText = _extractVersionText(text);
    final detailText =
        ['for $label', if (versionText.isNotEmpty) versionText].join(' ');

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: _productName),
          TextSpan(
            text: '\n$detailText',
            style: style.copyWith(
              fontSize: baseFontSize * 0.58,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.start,
    );
  }

  String _extractVersionText(String bannerText) {
    final tail = bannerText.substring(_productName.length).trim();
    if (tail.isEmpty) {
      return '';
    }
    final match = RegExp(r'[:：]\s*(.+)$').firstMatch(tail);
    return (match?.group(1) ?? tail).trim();
  }
}
