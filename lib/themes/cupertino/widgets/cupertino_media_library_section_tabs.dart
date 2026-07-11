import 'dart:ui';

import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoMediaLibrarySectionTabs extends StatelessWidget {
  const CupertinoMediaLibrarySectionTabs({
    super.key,
    required this.sections,
    required this.selectedId,
    required this.onSelected,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final section = sections[index];
          return _SectionButton(
            section: section,
            selected: section.id == selectedId,
            onPressed: () => onSelected(section.id),
          );
        },
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.section,
    required this.selected,
    required this.onPressed,
  });

  final UnifiedMediaLibrarySection section;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final labelColor = selected
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveButton.child(
        onPressed: onPressed,
        style: selected
            ? AdaptiveButtonStyle.prominentGlass
            : AdaptiveButtonStyle.glass,
        size: AdaptiveButtonSize.medium,
        color: selected ? accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          section.label,
          maxLines: 1,
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      );
    }

    final background = selected
        ? accent
        : CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground.withValues(alpha: 0.72),
            context,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          minimumSize: const Size(44, 36),
          color: background,
          borderRadius: BorderRadius.circular(18),
          onPressed: onPressed,
          child: Text(
            section.label,
            maxLines: 1,
            style: TextStyle(
              color: labelColor,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
