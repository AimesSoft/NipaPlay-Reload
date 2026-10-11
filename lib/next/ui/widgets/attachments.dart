import 'package:flutter/widgets.dart';

import '../conversation/chat_context.dart';
import '../theme/tokens.dart';
import 'artwork.dart';
import 'buttons.dart';
import 'icons.dart';

NextGlyph _glyph(String path) => switch (DroppedFile.kindOf(path)) {
      '视频' => NextGlyph.video,
      '种子' => NextGlyph.torrent,
      _ => NextGlyph.file,
    };

/// Files waiting to go with what you say next: a picture shows itself, the
/// others their name; × takes one off.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip(
      {super.key, required this.paths, required this.onRemove});
  final List<String> paths;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in paths)
            _Pending(
                key: ValueKey(p), path: p, onRemove: () => onRemove(p)),
        ],
      );
}

class _Pending extends StatelessWidget {
  const _Pending(
      {super.key, required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final image = DroppedFile.isImage(path);
    return Container(
      height: 40,
      padding: EdgeInsets.fromLTRB(image ? 4 : 10, 4, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NextColors.line2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (image)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
                dimension: 32,
                child: NextImage(path, shape: ArtShape.poster)),
          )
        else
          NextIcon(_glyph(path), size: 15, color: NextColors.p2),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(DroppedFile.name(path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(12.5, color: NextColors.p2)),
        ),
        const SizedBox(width: 4),
        Pressable(
          onTap: onRemove,
          semanticLabel: '拿掉',
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.all(5),
            child: NextIcon(NextGlyph.close,
                size: 10, color: hovered ? NextColors.paper : NextColors.p3),
          ),
        ),
      ]),
    );
  }
}

/// The files that went with something you said, above its bubble:
/// pictures as pictures, the rest by name.
class SentFiles extends StatelessWidget {
  const SentFiles({super.key, required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final images = paths.where(DroppedFile.isImage).toList();
    final others = paths.where((p) => !DroppedFile.isImage(p)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in images)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: images.length == 1 ? 200 : 120,
                    height: images.length == 1 ? 120 : 80,
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: NextColors.line2),
                    ),
                    child: NextImage(p),
                  ),
                ),
            ],
          ),
        if (images.isNotEmpty && others.isNotEmpty) const SizedBox(height: 6),
        for (final (i, p) in others.indexed) ...[
          if (i > 0) const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NextColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              NextIcon(_glyph(p), size: 15, color: NextColors.p2),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(DroppedFile.name(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13, color: NextColors.p2)),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

/// Over a drop place while files are dragged across it: the place lights
/// up and says where they go.
class DropGlow extends StatelessWidget {
  const DropGlow(
      {super.key,
      required this.over,
      required this.radius,
      this.label = '松开，交给 Nipa'});
  final bool over;
  final BorderRadius radius;
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: over ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xB3101016),
              borderRadius: radius,
              border: Border.all(color: NextColors.accent, width: 1.5),
              boxShadow: const [
                BoxShadow(color: Color(0x40FF2E55), blurRadius: 24),
              ],
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: NextText.sans(14,
                    weight: FontWeight.w600, color: NextColors.paper)),
          ),
        ),
      );
}
