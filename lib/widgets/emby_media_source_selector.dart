import 'package:flutter/material.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/utils/media_path_name.dart';

String embyMediaSourceLabel(
  PlaybackMediaSource source, {
  required int index,
}) {
  final path = source.path?.trim();
  if (path != null && path.isNotEmpty) {
    final name = mediaPathName(path);
    if (name.isNotEmpty) return name;
  }

  final container = source.container?.trim().toUpperCase();
  return [
    '版本 ${index + 1}',
    if (container != null && container.isNotEmpty) container,
  ].join(' · ');
}

class EmbyMediaSourceSelector extends StatelessWidget {
  const EmbyMediaSourceSelector({
    super.key,
    required this.sources,
    required this.selectedSourceId,
    required this.onSelected,
  });

  final List<PlaybackMediaSource> sources;
  final String? selectedSourceId;
  final ValueChanged<PlaybackMediaSource> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < sources.length; index++)
          Padding(
            padding:
                EdgeInsets.only(bottom: index == sources.length - 1 ? 0 : 8),
            child: Semantics(
              selected: sources[index].id == selectedSourceId,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(sources[index]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sources[index].id == selectedSourceId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: sources[index].id == selectedSourceId
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            embyMediaSourceLabel(sources[index], index: index),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
