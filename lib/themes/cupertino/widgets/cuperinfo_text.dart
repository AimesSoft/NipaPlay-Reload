import 'package:flutter/widgets.dart' as flutter;

typedef FlutterText = flutter.Text;

class Text extends flutter.StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
  }) : textSpan = null;

  const Text.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
  }) : data = '';

  final String data;
  final flutter.InlineSpan? textSpan;
  final flutter.TextStyle? style;
  final flutter.StrutStyle? strutStyle;
  final flutter.TextAlign? textAlign;
  final flutter.TextDirection? textDirection;
  final flutter.Locale? locale;
  final bool? softWrap;
  final flutter.TextOverflow? overflow;
  final double? textScaleFactor;
  final flutter.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final flutter.TextWidthBasis? textWidthBasis;
  final flutter.TextHeightBehavior? textHeightBehavior;

  @override
  flutter.Widget build(flutter.BuildContext context) {
    final baseStyle = style?.inherit == false
        ? (style ?? const flutter.TextStyle())
        : flutter.DefaultTextStyle.of(context).style.merge(style);
    final effectiveStyle =
        baseStyle.copyWith(decoration: flutter.TextDecoration.none);
    final resolvedTextScaleFactor =
        textScaler == null ? textScaleFactor : null;

    if (textSpan != null) {
      final wrappedSpan = flutter.TextSpan(
        style: effectiveStyle,
        children: [textSpan!],
      );
      return flutter.Text.rich(
        wrappedSpan,
        style: null,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaleFactor: resolvedTextScaleFactor,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
      );
    }

    return flutter.Text(
      data,
      style: effectiveStyle,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: resolvedTextScaleFactor,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
    );
  }
}
