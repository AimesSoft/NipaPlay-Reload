import 'package:flutter/material.dart' as material;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class AdaptiveMarkdown extends material.StatelessWidget {
  const AdaptiveMarkdown({
    super.key,
    required this.data,
    required this.brightness,
    this.baseTextStyle,
    this.linkColor,
    this.onTapLink,
    this.selectable = true,
  });

  final String data;
  final material.Brightness brightness;
  final material.TextStyle? baseTextStyle;
  final material.Color? linkColor;
  final void Function(String href)? onTapLink;
  final bool selectable;

  @override
  material.Widget build(material.BuildContext context) {
    final material.Color effectiveLinkColor = linkColor ??
        (brightness == material.Brightness.dark
            ? material.Colors.lightBlueAccent
            : material.Colors.blue);

    final material.ThemeData theme = material.ThemeData(
      brightness: brightness,
      colorScheme: material.ColorScheme.fromSeed(
        seedColor: effectiveLinkColor,
        brightness: brightness,
      ),
      useMaterial3: true,
    );

    final double baseFontSize =
        baseTextStyle?.fontSize ?? theme.textTheme.bodyMedium?.fontSize ?? 14;

    final material.ThemeData safeTheme = theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        bodyMedium: (theme.textTheme.bodyMedium ?? const material.TextStyle())
            .copyWith(fontSize: baseFontSize),
      ),
    );

    final material.TextStyle fallbackStyle = safeTheme.textTheme.bodyMedium ??
        material.TextStyle(fontSize: baseFontSize);

    final material.TextStyle candidateStyle = baseTextStyle ?? fallbackStyle;
    final material.TextStyle effectiveTextStyle = candidateStyle.copyWith(
      color: candidateStyle.color ?? theme.colorScheme.onSurface,
      fontSize: candidateStyle.fontSize ?? baseFontSize,
    );

    final material.Color codeBackgroundColor =
        brightness == material.Brightness.dark
            ? material.Colors.white.withOpacity(0.08)
            : material.Colors.black.withOpacity(0.05);

    final MarkdownStyleSheet styleSheet =
        MarkdownStyleSheet.fromTheme(safeTheme).copyWith(
      p: effectiveTextStyle,
      a: effectiveTextStyle.copyWith(color: effectiveLinkColor),
      listBullet: effectiveTextStyle,
      code: effectiveTextStyle.copyWith(
        fontFamily: 'monospace',
        backgroundColor: codeBackgroundColor,
      ),
      blockquoteDecoration: material.BoxDecoration(
        color: brightness == material.Brightness.dark
            ? material.Colors.white.withOpacity(0.05)
            : material.Colors.black.withOpacity(0.04),
        border: material.Border(
          left: material.BorderSide(
            color: effectiveLinkColor.withOpacity(0.7),
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const material.EdgeInsets.all(12),
    );

    return material.Theme(
      data: safeTheme,
      child: material.Material(
        type: material.MaterialType.transparency,
        child: MarkdownBody(
          data: data,
          selectable: selectable,
          extensionSet: md.ExtensionSet.gitHubWeb,
          onTapLink: onTapLink == null
              ? null
              : (text, href, title) {
                  if (href == null || href.trim().isEmpty) return;
                  onTapLink!(href);
                },
          styleSheet: styleSheet,
        ),
      ),
    );
  }
}
