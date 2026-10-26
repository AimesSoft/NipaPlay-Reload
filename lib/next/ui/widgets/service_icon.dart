import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The same service artwork used by Classic, at any Next entry point.
class ServiceIcon extends StatelessWidget {
  const ServiceIcon(this.provider,
      {super.key, required this.color, this.size = 22});
  final String provider;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = switch (provider) {
      'dandanplay' || 'dandanplay_remote' => 'assets/dandanplay.png',
      'bangumi' => 'assets/bangumi.png',
      'jellyfin' => 'assets/jellyfin.svg',
      'emby' => 'assets/emby.svg',
      'nipaplay' => 'assets/nipaplay.png',
      _ => null,
    };
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        return SvgPicture.asset(asset,
            width: size,
            height: size,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
      }
      return Image.asset(asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          color: color,
          colorBlendMode: BlendMode.srcIn);
    }
    return Icon(
      switch (provider) {
        'webdav' => CupertinoIcons.cloud,
        'smb' => CupertinoIcons.rectangle_3_offgrid,
        _ => CupertinoIcons.folder,
      },
      size: size,
      color: color,
    );
  }
}
