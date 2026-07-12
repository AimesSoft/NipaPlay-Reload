import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoMediaLibrarySectionPicker extends StatefulWidget {
  const CupertinoMediaLibrarySectionPicker({
    super.key,
    required this.sections,
    required this.selectedId,
    required this.onSelected,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<CupertinoMediaLibrarySectionPicker> createState() =>
      _CupertinoMediaLibrarySectionPickerState();
}

class _CupertinoMediaLibrarySectionPickerState
    extends State<CupertinoMediaLibrarySectionPicker> {
  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();

    final selectedSection = widget.sections.firstWhere(
      (section) => section.id == widget.selectedId,
      orElse: () => widget.sections.first,
    );

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () async {
        final sectionId = await CupertinoBottomSheet.showSelection<String>(
          context: context,
          title: '媒体库分区',
          options: [
            for (final section in widget.sections)
              CupertinoBottomSheetOption(
                label: section.label,
                value: section.id,
                selected: section.id == selectedSection.id,
              ),
          ],
        );
        if (sectionId != null && sectionId != selectedSection.id) {
          widget.onSelected(sectionId);
        }
      },
      child: _PickerLabel(section: selectedSection),
    );
  }
}

class _PickerLabel extends StatelessWidget {
  const _PickerLabel({required this.section});

  final UnifiedMediaLibrarySection section;

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final secondaryColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return ConstrainedBox(
      key: const ValueKey<String>('media-library-section-picker'),
      constraints: const BoxConstraints(maxWidth: 240),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                CupertinoIcons.chevron_down,
                size: 15,
                color: secondaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
