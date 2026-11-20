import 'package:flutter/material.dart';

/// Keep long credits and alternative titles in the parent viewport's lazy list.
/// A shrink-wrapped list inside the summary Column would lay out every row.
class AnimeDetailMetadataSliver extends StatelessWidget {
  const AnimeDetailMetadataSliver({
    super.key,
    required this.metadata,
    required this.titles,
    required this.valueStyle,
    required this.keyStyle,
    required this.sectionTitleStyle,
    required this.secondaryTextColor,
  });

  final List<String> metadata;
  final List<Map<String, String>> titles;
  final TextStyle valueStyle;
  final TextStyle keyStyle;
  final TextStyle sectionTitleStyle;
  final Color secondaryTextColor;

  @override
  Widget build(BuildContext context) {
    final rows = metadata.where((item) {
      final text = item.trim();
      return !text.startsWith('别名:') && !text.startsWith('别名：');
    }).toList(growable: false);
    final metadataCount = metadata.isEmpty ? 0 : rows.length + 1;
    final titleCount = titles.isEmpty ? 0 : titles.length + 1;
    return SliverList.builder(
      itemCount: metadataCount + titleCount,
      itemBuilder: (context, index) {
        if (index < metadataCount) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('制作信息:', style: sectionTitleStyle),
            );
          }
          final item = rows[index - 1];
          final parts = item.split(RegExp(r'[:：]'));
          if (parts.length != 2) {
            return Text(item, style: valueStyle.copyWith(height: 1.3));
          }
          return Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichText(
              text: TextSpan(
                style: valueStyle.copyWith(height: 1.3),
                children: [
                  TextSpan(text: '${parts[0].trim()}: ', style: keyStyle),
                  TextSpan(text: parts[1].trim()),
                ],
              ),
            ),
          );
        }
        final titleIndex = index - metadataCount;
        if (titleIndex == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('其他标题:', style: sectionTitleStyle),
          );
        }
        final title = titles[titleIndex - 1];
        final language = title['language'];
        return Padding(
          padding: const EdgeInsets.only(top: 3, left: 8),
          child: Text(
            '${title['title'] ?? '未知标题'}'
            '${language != null && language.isNotEmpty ? ' ($language)' : ''}',
            style: valueStyle.copyWith(
              color: secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
        );
      },
    );
  }
}
