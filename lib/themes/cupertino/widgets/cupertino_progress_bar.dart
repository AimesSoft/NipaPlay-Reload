import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoProgressBar extends StatelessWidget {
  const CupertinoProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final progress = (value ?? 0).clamp(0.0, 1.0);
    final foreground = color ?? CupertinoTheme.of(context).primaryColor;
    final background = backgroundColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey4, context);

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: ColoredBox(
          color: background,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: ColoredBox(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
