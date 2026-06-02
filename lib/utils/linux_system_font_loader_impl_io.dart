import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isLinuxSystemFontLoaded => _loadedFontFamily != null;

String? _loadedFontFamily;
Future<void>? _loadFuture;

Future<void> ensureLinuxSystemFontLoadedImpl(String fontFamily) {
  if (!Platform.isLinux || ffi.Abi.current() != ffi.Abi.linuxArm64) {
    return Future<void>.value();
  }
  return _loadFuture ??= _loadSystemFont(fontFamily);
}

Future<void> _loadSystemFont(String fontFamily) async {
  try {
    final fontConfig = _FontConfig.open();
    final fontPaths = <String>{
      for (final pattern in const <String>[
        'sans-serif:lang=zh-cn:weight=regular',
        'sans-serif:lang=zh-cn:weight=bold',
      ])
        if (fontConfig.matchFile(pattern) case final String path)
          if (await File(path).exists()) path,
    };
    if (fontPaths.isEmpty) {
      debugPrint('[LinuxSystemFont] fontconfig did not return a CJK font.');
      return;
    }

    final loader = FontLoader(fontFamily);
    for (final path in fontPaths) {
      loader.addFont(
        File(path).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
    _loadedFontFamily = fontFamily;
    debugPrint(
      '[LinuxSystemFont] Loaded system CJK fonts: ${fontPaths.join(', ')}',
    );
  } catch (error, stackTrace) {
    debugPrint('[LinuxSystemFont] Failed to load system CJK font: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

final class _FcConfig extends ffi.Opaque {}

final class _FcPattern extends ffi.Opaque {}

class _FontConfig {
  _FontConfig(this._library) {
    if (_init() == 0) {
      throw StateError('FcInit failed');
    }
  }

  factory _FontConfig.open() {
    try {
      return _FontConfig(ffi.DynamicLibrary.open('libfontconfig.so.1'));
    } on ArgumentError {
      return _FontConfig(ffi.DynamicLibrary.open('libfontconfig.so'));
    }
  }

  static const int _matchPattern = 0;
  static const int _resultMatch = 0;

  final ffi.DynamicLibrary _library;

  late final int Function() _init =
      _library.lookupFunction<ffi.Int Function(), int Function()>('FcInit');
  late final ffi.Pointer<_FcPattern> Function(ffi.Pointer<ffi.Uint8>)
      _nameParse = _library.lookupFunction<
          ffi.Pointer<_FcPattern> Function(ffi.Pointer<ffi.Uint8>),
          ffi.Pointer<_FcPattern> Function(
              ffi.Pointer<ffi.Uint8>)>('FcNameParse');
  late final int Function(
    ffi.Pointer<_FcConfig>,
    ffi.Pointer<_FcPattern>,
    int,
  ) _configSubstitute = _library.lookupFunction<
      ffi.Int Function(
        ffi.Pointer<_FcConfig>,
        ffi.Pointer<_FcPattern>,
        ffi.Int,
      ),
      int Function(
        ffi.Pointer<_FcConfig>,
        ffi.Pointer<_FcPattern>,
        int,
      )>('FcConfigSubstitute');
  late final void Function(ffi.Pointer<_FcPattern>) _defaultSubstitute =
      _library.lookupFunction<ffi.Void Function(ffi.Pointer<_FcPattern>),
          void Function(ffi.Pointer<_FcPattern>)>('FcDefaultSubstitute');
  late final ffi.Pointer<_FcPattern> Function(
    ffi.Pointer<_FcConfig>,
    ffi.Pointer<_FcPattern>,
    ffi.Pointer<ffi.Int>,
  ) _fontMatch = _library.lookupFunction<
      ffi.Pointer<_FcPattern> Function(
        ffi.Pointer<_FcConfig>,
        ffi.Pointer<_FcPattern>,
        ffi.Pointer<ffi.Int>,
      ),
      ffi.Pointer<_FcPattern> Function(
        ffi.Pointer<_FcConfig>,
        ffi.Pointer<_FcPattern>,
        ffi.Pointer<ffi.Int>,
      )>('FcFontMatch');
  late final int Function(
    ffi.Pointer<_FcPattern>,
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
  ) _patternGetString = _library.lookupFunction<
      ffi.Int Function(
        ffi.Pointer<_FcPattern>,
        ffi.Pointer<ffi.Uint8>,
        ffi.Int,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      ),
      int Function(
        ffi.Pointer<_FcPattern>,
        ffi.Pointer<ffi.Uint8>,
        int,
        ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
      )>('FcPatternGetString');
  late final void Function(ffi.Pointer<_FcPattern>) _patternDestroy =
      _library.lookupFunction<ffi.Void Function(ffi.Pointer<_FcPattern>),
          void Function(ffi.Pointer<_FcPattern>)>('FcPatternDestroy');

  String? matchFile(String pattern) {
    final nativePattern = pattern.toNativeUtf8();
    final fileProperty = 'file'.toNativeUtf8();
    final matchResult = malloc<ffi.Int>();
    final fileValue = malloc<ffi.Pointer<ffi.Uint8>>();
    ffi.Pointer<_FcPattern>? query;
    ffi.Pointer<_FcPattern>? match;
    try {
      query = _nameParse(nativePattern.cast());
      if (query == ffi.nullptr) {
        return null;
      }
      _configSubstitute(ffi.nullptr, query, _matchPattern);
      _defaultSubstitute(query);
      match = _fontMatch(ffi.nullptr, query, matchResult);
      if (match == ffi.nullptr || matchResult.value != _resultMatch) {
        return null;
      }
      if (_patternGetString(match, fileProperty.cast(), 0, fileValue) !=
          _resultMatch) {
        return null;
      }
      return fileValue.value.cast<Utf8>().toDartString();
    } finally {
      if (match != null && match != ffi.nullptr) {
        _patternDestroy(match);
      }
      if (query != null && query != ffi.nullptr) {
        _patternDestroy(query);
      }
      malloc.free(fileValue);
      malloc.free(matchResult);
      malloc.free(fileProperty);
      malloc.free(nativePattern);
    }
  }
}
