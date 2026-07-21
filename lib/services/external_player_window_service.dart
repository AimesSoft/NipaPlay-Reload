import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Saves and temporarily resizes the NipaPlay window for an external session.
///
/// The original bounds and window mode are restored when the session ends.
class ExternalPlayerWindowService {
  ExternalPlayerWindowService._();

  static const Size _minimumWindowSize = Size(600, 400);
  static _WindowSnapshot? _snapshot;
  static int _operationGeneration = 0;
  static Future<void>? _shrinkOperation;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static Future<void> shrinkToHalfScreenWidth() async {
    if (!_isDesktop || _snapshot != null || _shrinkOperation != null) return;

    final operation = _performShrinkToHalfScreenWidth();
    _shrinkOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_shrinkOperation, operation)) {
        _shrinkOperation = null;
      }
    }
  }

  static Future<void> _performShrinkToHalfScreenWidth() async {
    final generation = ++_operationGeneration;
    try {
      final bounds = await windowManager.getBounds();
      final isMaximized = await windowManager.isMaximized();
      final isFullScreen = await windowManager.isFullScreen();
      final displays = await screenRetriever.getAllDisplays();
      if (generation != _operationGeneration) return;

      final workArea = _nearestWorkArea(bounds, displays);
      _snapshot = _WindowSnapshot(
        bounds: bounds,
        isMaximized: isMaximized,
        isFullScreen: isFullScreen,
      );

      if (isFullScreen) await windowManager.setFullScreen(false);
      if (isMaximized) await windowManager.unmaximize();
      if (generation != _operationGeneration) return;

      await windowManager.setBounds(
        calculateHalfWidthBounds(
          currentBounds: bounds,
          workArea: workArea,
          minimumSize: _minimumWindowSize,
        ),
        animate: true,
      );
    } catch (error) {
      final snapshot = _snapshot;
      _snapshot = null;
      debugPrint(
        '[ExternalPlayerWindowService] Failed to resize main window: $error',
      );
      if (snapshot != null) {
        try {
          await _restoreSnapshot(snapshot);
        } catch (restoreError) {
          debugPrint(
            '[ExternalPlayerWindowService] Failed to roll back window: '
            '$restoreError',
          );
        }
      }
    }
  }

  static Future<void> restore() async {
    if (!_isDesktop) return;

    ++_operationGeneration;
    final pendingShrink = _shrinkOperation;
    if (pendingShrink != null) {
      try {
        await pendingShrink;
      } catch (_) {
        // The shrink path already logs and rolls back its own failures.
      }
    }

    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot == null) return;
    try {
      await _restoreSnapshot(snapshot);
    } catch (error) {
      debugPrint(
        '[ExternalPlayerWindowService] Failed to restore main window: $error',
      );
    }
  }

  static Future<void> _restoreSnapshot(_WindowSnapshot snapshot) async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    await windowManager.setBounds(snapshot.bounds, animate: true);
    if (snapshot.isFullScreen) {
      await windowManager.setFullScreen(true);
    } else if (snapshot.isMaximized) {
      await windowManager.maximize();
    }
  }

  @visibleForTesting
  static Rect calculateHalfWidthBounds({
    required Rect currentBounds,
    required Rect workArea,
    Size minimumSize = _minimumWindowSize,
  }) {
    final availableWidth = workArea.width.isFinite && workArea.width > 0
        ? workArea.width
        : currentBounds.width;
    final availableHeight = workArea.height.isFinite && workArea.height > 0
        ? workArea.height
        : currentBounds.height;
    final minimumWidth =
        minimumSize.width.clamp(0.0, availableWidth).toDouble();
    final minimumHeight =
        minimumSize.height.clamp(0.0, availableHeight).toDouble();
    final width =
        (availableWidth / 2).clamp(minimumWidth, availableWidth).toDouble();
    final aspectRatio = currentBounds.width > 0 && currentBounds.height > 0
        ? currentBounds.width / currentBounds.height
        : 16 / 10;
    final height =
        (width / aspectRatio).clamp(minimumHeight, availableHeight).toDouble();

    return Rect.fromLTWH(
      workArea.left,
      workArea.top + (availableHeight - height) / 2,
      width,
      height,
    );
  }

  static Rect _nearestWorkArea(Rect windowBounds, List<Display> displays) {
    if (displays.isEmpty) return windowBounds;

    Rect areaFor(Display display) {
      final position = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      return position & size;
    }

    var selected = areaFor(displays.first);
    var bestIntersection = _intersectionArea(windowBounds, selected);
    var bestDistance = (windowBounds.center - selected.center).distanceSquared;
    for (final display in displays.skip(1)) {
      final candidate = areaFor(display);
      final intersection = _intersectionArea(windowBounds, candidate);
      final distance = (windowBounds.center - candidate.center).distanceSquared;
      if (intersection > bestIntersection ||
          (intersection == bestIntersection && distance < bestDistance)) {
        selected = candidate;
        bestIntersection = intersection;
        bestDistance = distance;
      }
    }
    return selected;
  }

  static double _intersectionArea(Rect first, Rect second) {
    final intersection = first.intersect(second);
    if (intersection.width <= 0 || intersection.height <= 0) return 0;
    return intersection.width * intersection.height;
  }
}

class _WindowSnapshot {
  const _WindowSnapshot({
    required this.bounds,
    required this.isMaximized,
    required this.isFullScreen,
  });

  final Rect bounds;
  final bool isMaximized;
  final bool isFullScreen;
}
