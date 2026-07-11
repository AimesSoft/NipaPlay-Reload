import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';

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
  final GlobalKey _dropdownKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();

    final selectedSection = widget.sections.firstWhere(
      (section) => section.id == widget.selectedId,
      orElse: () => widget.sections.first,
    );

    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptivePopupMenuButton.widget<String>(
        items: [
          for (final section in widget.sections)
            AdaptivePopupMenuItem<String>(
              label: section.label,
              icon: section.id == selectedSection.id ? 'checkmark' : null,
              value: section.id,
            ),
        ],
        buttonStyle: PopupButtonStyle.glass,
        onSelected: (_, entry) {
          final sectionId = entry.value;
          if (sectionId != null && sectionId != selectedSection.id) {
            widget.onSelected(sectionId);
          }
        },
        child: _PickerLabel(section: selectedSection),
      );
    }

    return ConstrainedBox(
      key: const ValueKey<String>('media-library-section-picker'),
      constraints: const BoxConstraints(maxWidth: 240),
      child: BlurDropdown<String>(
        dropdownKey: _dropdownKey,
        items: [
          for (final section in widget.sections)
            DropdownMenuItemData<String>(
              title: section.label,
              value: section.id,
              isSelected: section.id == selectedSection.id,
            ),
        ],
        onItemSelected: (sectionId) {
          if (sectionId != selectedSection.id) {
            widget.onSelected(sectionId);
          }
        },
      ),
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
