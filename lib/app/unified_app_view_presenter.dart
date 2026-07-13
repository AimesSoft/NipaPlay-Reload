import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/unified_app_virtual_windows.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:provider/provider.dart';

class UnifiedAppViewPresenter {
  const UnifiedAppViewPresenter._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String viewId,
    String? initialSubpageId,
  }) {
    final definition = unifiedAppVirtualWindowById(viewId);
    if (definition == null) {
      throw ArgumentError.value(viewId, 'viewId', 'Unknown application view');
    }

    final request = UnifiedAppViewRequest(
      viewId: viewId,
      initialSubpageId: initialSubpageId,
    );
    final surface = AppDisplaySurfaceScope.of(context);
    final localizations = AppLocalizations.of(context) ??
        lookupAppLocalizations(context.read<AppLanguageProvider>().locale);
    final title = definition.title(localizations);

    return switch (surface) {
      AppDisplaySurface.desktopTablet => _showDesktopTablet<T>(
          context,
          definition: definition,
          request: request,
          title: title,
          contentSurface: AppDisplaySurface.desktopTablet,
        ),
      AppDisplaySurface.phone => _showPhone<T>(
          context,
          definition: definition,
          request: request,
          title: title,
        ),
      AppDisplaySurface.television => _showTelevision<T>(
          context,
          definition: definition,
          request: request,
          title: title,
        ),
    };
  }

  static Future<T?> _showDesktopTablet<T>(
    BuildContext context, {
    required UnifiedAppVirtualWindow definition,
    required UnifiedAppViewRequest request,
    required String title,
    required AppDisplaySurface contentSurface,
  }) {
    final appearance = context.read<AppearanceSettingsProvider>();
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 900;
    final maxWidth =
        compact ? screenSize.width * 0.95 : definition.layout.desktopMaxWidth;
    final maxHeightFactor =
        compact ? 0.9 : definition.layout.desktopMaxHeightFactor;

    return NipaplayWindow.show<T>(
      context: context,
      enableAnimation: appearance.enablePageAnimation,
      child: Builder(
        builder: (windowContext) => NipaplayWindowScaffold(
          maxWidth: maxWidth,
          maxHeightFactor: maxHeightFactor,
          onClose: () => Navigator.of(windowContext).pop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopVirtualWindowTitle(title: title),
              Expanded(
                child: definition.build(
                  windowContext,
                  contentSurface,
                  request,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<T?> _showPhone<T>(
    BuildContext context, {
    required UnifiedAppVirtualWindow definition,
    required UnifiedAppViewRequest request,
    required String title,
  }) {
    return CupertinoBottomSheet.showPage<T>(
      context: context,
      title: title,
      heightRatio: definition.layout.phoneHeightRatio,
      floatingTitle: definition.layout.phoneFloatingTitle,
      rootPageBuilder: (sheetContext) => definition.build(
        sheetContext,
        AppDisplaySurface.phone,
        request,
      ),
    );
  }

  static Future<T?> _showTelevision<T>(
    BuildContext context, {
    required UnifiedAppVirtualWindow definition,
    required UnifiedAppViewRequest request,
    required String title,
  }) {
    return _showDesktopTablet<T>(
      context,
      definition: definition,
      request: request,
      title: title,
      contentSurface: AppDisplaySurface.television,
    );
  }
}

class _DesktopVirtualWindowTitle extends StatelessWidget {
  const _DesktopVirtualWindowTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        NipaplayWindowPositionProvider.of(context)?.onMove(details.delta);
      },
      onDoubleTap: () {
        NipaplayWindowPositionProvider.of(context)?.onToggleDisplayMode();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
