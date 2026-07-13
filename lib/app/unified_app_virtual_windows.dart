import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/settings/unified_settings_page.dart';

class UnifiedAppViewRequest {
  const UnifiedAppViewRequest({
    required this.viewId,
    this.initialSubpageId,
  });

  final String viewId;
  final String? initialSubpageId;
}

class UnifiedVirtualWindowLayout {
  const UnifiedVirtualWindowLayout({
    this.desktopMaxWidth = 850,
    this.desktopMaxHeightFactor = 0.8,
    this.phoneHeightRatio = 0.94,
    this.phoneFloatingTitle = true,
  });

  final double desktopMaxWidth;
  final double desktopMaxHeightFactor;
  final double phoneHeightRatio;
  final bool phoneFloatingTitle;
}

enum UnifiedAppViewContentType { settings }

class UnifiedAppVirtualWindow {
  const UnifiedAppVirtualWindow({
    required this.id,
    required this.titleBuilder,
    required this.contentType,
    this.layout = const UnifiedVirtualWindowLayout(),
  });

  final String id;
  final String Function(AppLocalizations localizations) titleBuilder;
  final UnifiedAppViewContentType contentType;
  final UnifiedVirtualWindowLayout layout;

  String title(AppLocalizations localizations) => titleBuilder(localizations);

  Widget build(
    BuildContext context,
    AppDisplaySurface surface,
    UnifiedAppViewRequest request,
  ) {
    return AppDisplaySurfaceScope(
      surface: surface,
      child: switch (contentType) {
        UnifiedAppViewContentType.settings =>
          UnifiedSettingsPage(initialEntryId: request.initialSubpageId),
      },
    );
  }
}

String _settingsTitle(AppLocalizations localizations) {
  return localizations.settingsLabel;
}

const List<UnifiedAppVirtualWindow> unifiedAppVirtualWindows =
    <UnifiedAppVirtualWindow>[
  UnifiedAppVirtualWindow(
    id: AppPageIds.settings,
    titleBuilder: _settingsTitle,
    contentType: UnifiedAppViewContentType.settings,
    layout: UnifiedVirtualWindowLayout(
      desktopMaxWidth: 980,
      desktopMaxHeightFactor: 0.85,
    ),
  ),
];

UnifiedAppVirtualWindow? unifiedAppVirtualWindowById(String id) {
  for (final window in unifiedAppVirtualWindows) {
    if (window.id == id) return window;
  }
  return null;
}
