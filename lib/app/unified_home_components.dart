import 'package:nipaplay/providers/home_sections_settings_provider.dart';

enum UnifiedHomeComponentType {
  hero,
  todaySeries,
  randomRecommendations,
  continueWatching,
  remoteLibraries,
  localLibrary,
}

class UnifiedHomeComponent {
  const UnifiedHomeComponent({
    required this.id,
    required this.type,
    this.sectionType,
  });

  final String id;
  final UnifiedHomeComponentType type;
  final HomeSectionType? sectionType;
}

List<UnifiedHomeComponent> buildUnifiedHomeComponents({
  required HomeSectionsSettingsProvider settings,
  required bool hasTodaySeries,
  required bool hasRandomRecommendations,
  required bool hasLocalLibrary,
}) {
  final components = <UnifiedHomeComponent>[
    const UnifiedHomeComponent(
      id: 'hero',
      type: UnifiedHomeComponentType.hero,
    ),
  ];

  for (final section in settings.orderedSections) {
    if (!settings.isSectionEnabled(section)) continue;
    switch (section) {
      case HomeSectionType.todaySeries:
        if (hasTodaySeries) {
          components.add(const UnifiedHomeComponent(
            id: 'today-series',
            type: UnifiedHomeComponentType.todaySeries,
            sectionType: HomeSectionType.todaySeries,
          ));
        }
        break;
      case HomeSectionType.randomRecommendations:
        if (hasRandomRecommendations) {
          components.add(const UnifiedHomeComponent(
            id: 'random-recommendations',
            type: UnifiedHomeComponentType.randomRecommendations,
            sectionType: HomeSectionType.randomRecommendations,
          ));
        }
        break;
      case HomeSectionType.continueWatching:
        components.add(const UnifiedHomeComponent(
          id: 'continue-watching',
          type: UnifiedHomeComponentType.continueWatching,
          sectionType: HomeSectionType.continueWatching,
        ));
        break;
      case HomeSectionType.remoteLibraries:
        components.add(const UnifiedHomeComponent(
          id: 'remote-libraries',
          type: UnifiedHomeComponentType.remoteLibraries,
          sectionType: HomeSectionType.remoteLibraries,
        ));
        break;
      case HomeSectionType.localLibrary:
        if (hasLocalLibrary) {
          components.add(const UnifiedHomeComponent(
            id: 'local-library',
            type: UnifiedHomeComponentType.localLibrary,
            sectionType: HomeSectionType.localLibrary,
          ));
        }
        break;
    }
  }
  return components;
}
