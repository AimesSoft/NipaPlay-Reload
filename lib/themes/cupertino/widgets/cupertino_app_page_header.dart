import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoAppPageHeader extends StatelessWidget {
  const CupertinoAppPageHeader({
    super.key,
    required this.title,
    this.bottomPadding = 10,
    this.trailingReservedWidth = 148,
  });

  final String title;
  final double bottomPadding;
  final double trailingReservedWidth;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 8,
        20,
        bottomPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: label,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(width: trailingReservedWidth),
        ],
      ),
    );
  }
}
