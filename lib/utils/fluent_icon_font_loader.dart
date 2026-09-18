import 'package:flutter/services.dart';

/// Registers the bundled Fluent fonts with the engine before their first use.
///
/// IconData from fluent_ui uses package-qualified family names. Loading the
/// same assets explicitly also clears the engine's font-family cache, allowing
/// icons to recover if an earlier implicit font lookup returned a missing glyph.
class FluentIconFontLoader {
  FluentIconFontLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final instance = FluentIconFontLoader();

  static const _fonts = <String, String>{
    'packages/fluent_ui/FluentIcons':
        'packages/fluent_ui/fonts/FluentIcons.ttf',
    'packages/fluent_ui/SegoeIcons': 'packages/fluent_ui/fonts/SegoeIcons.ttf',
  };

  final AssetBundle _bundle;
  final Set<String> _loadedFamilies = {};
  Future<void>? _pendingLoad;

  Future<void> ensureLoaded() {
    return _pendingLoad ??= _loadFonts().whenComplete(() {
      // A failed read must remain retryable when the account page opens later.
      _pendingLoad = null;
    });
  }

  Future<void> _loadFonts() async {
    for (final font in _fonts.entries) {
      if (_loadedFamilies.contains(font.key)) continue;
      final bytes = await _bundle.load(font.value);
      final loader = FontLoader(font.key)..addFont(Future.value(bytes));
      await loader.load();
      _loadedFamilies.add(font.key);
    }
  }
}
