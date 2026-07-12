import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nipaplay/media_library/media_source_option.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoMediaSourceSheet extends StatelessWidget {
  const CupertinoMediaSourceSheet({
    super.key,
    required this.options,
  });

  final List<MediaSourceOption> options;

  static Future<String?> show(
    BuildContext context, {
    List<MediaSourceOption> options = mediaSourceOptions,
  }) {
    return CupertinoBottomSheet.show<String>(
      context: context,
      title: '添加媒体',
      heightRatio: 0.82,
      child: CupertinoMediaSourceSheet(options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, topSpacing + 4, 12, 28),
          sliver: SliverList.list(
            children: [
              for (final category in MediaSourceCategory.values)
                if (options.any((option) => option.category == category)) ...[
                  CupertinoListSection.insetGrouped(
                    margin: EdgeInsets.zero,
                    header: Text(category.label),
                    children: [
                      for (final option in options.where(
                        (option) => option.category == category,
                      ))
                        _MediaSourceTile(option: option),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MediaSourceTile extends StatelessWidget {
  const _MediaSourceTile({required this.option});

  final MediaSourceOption option;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leadingSize: 40,
      leading: _MediaSourceIcon(option: option),
      title: Text(
        option.title,
        style: TextStyle(color: label, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(option.subtitle),
      trailing:
          Icon(CupertinoIcons.chevron_forward, size: 15, color: secondary),
      onTap: () => Navigator.of(context).pop(option.id),
    );
  }
}

class _MediaSourceIcon extends StatelessWidget {
  const _MediaSourceIcon({required this.option});

  final MediaSourceOption option;

  @override
  Widget build(BuildContext context) {
    final color = _brandColor(option.iconKind);
    return SizedBox.square(
      dimension: 40,
      child: Center(child: _icon(option.iconKind, color)),
    );
  }

  Widget _icon(MediaSourceIconKind kind, Color color) {
    return switch (kind) {
      MediaSourceIconKind.localFolder =>
        Icon(CupertinoIcons.folder, size: 30, color: color),
      MediaSourceIconKind.nipaplay => _image('assets/nipaplay.png', color),
      MediaSourceIconKind.jellyfin => _svg('assets/jellyfin.svg', color),
      MediaSourceIconKind.dandanplay => _image('assets/dandanplay.png', color),
      MediaSourceIconKind.emby => _svg('assets/emby.svg', color),
      MediaSourceIconKind.webdav =>
        Icon(CupertinoIcons.cloud, size: 30, color: color),
      MediaSourceIconKind.smb =>
        Icon(CupertinoIcons.rectangle_3_offgrid, size: 30, color: color),
    };
  }

  Widget _svg(String asset, Color color) {
    return SvgPicture.asset(
      asset,
      width: 30,
      height: 30,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _image(String asset, Color color) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(asset, width: 30, height: 30),
    );
  }
}

Color _brandColor(MediaSourceIconKind kind) => switch (kind) {
      MediaSourceIconKind.localFolder => const Color(0xFFD69035),
      MediaSourceIconKind.nipaplay => const Color(0xFF8C72C3),
      MediaSourceIconKind.jellyfin => const Color(0xFF3E9DCF),
      MediaSourceIconKind.dandanplay => const Color(0xFF3B87CE),
      MediaSourceIconKind.emby => const Color(0xFF459C40),
      MediaSourceIconKind.webdav => const Color(0xFF438EC4),
      MediaSourceIconKind.smb => const Color(0xFF438F58),
    };
