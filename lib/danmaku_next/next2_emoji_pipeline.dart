import 'dart:convert';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';

class Next2PreparedFramePayload {
  const Next2PreparedFramePayload({
    required this.frameJson,
  });

  /// Fully encoded native frame payload.
  ///
  /// The renderer submits this string directly to the platform channel. This
  /// avoids rebuilding a nested Map/List object graph and then walking it a
  /// second time in jsonEncode on every display frame.
  final String frameJson;

  /// Compatibility/debug representation. The hot rendering path uses
  /// [frameJson] directly and therefore does not pay this decode cost.
  Map<String, dynamic> toJson() {
    return jsonDecode(frameJson) as Map<String, dynamic>;
  }
}

class Next2EmojiPipeline {
  static const int _glyphCacheLimit = 1200;
  static const int _maxNewGlyphsPerFrame = 16;
  static final LinkedHashMap<String, _EmojiGlyphRaster> _glyphCache =
      LinkedHashMap<String, _EmojiGlyphRaster>();

  bool _forceGlyphResend = true;

  /// LRU cache of tokenized and JSON-escaped static text fragments. Both
  /// plain and emoji-bearing text are cacheable: emoji build requests are
  /// retained beside the token JSON and re-registered while their bitmap is
  /// still absent. This removes the grapheme scan and token Map allocations
  /// from steady-state frames.
  static const int _tokenCacheLimit = 2000;
  final LinkedHashMap<String, _CachedTokenization> _tokenCache =
      LinkedHashMap<String, _CachedTokenization>();

  _CachedTokenization _tokenizeCached(String text, double fontSize) {
    final key = '${fontSize.round().clamp(8, 256)}\u0000$text';
    final cached = _tokenCache.remove(key);
    if (cached != null) {
      _tokenCache[key] = cached;
      return cached;
    }

    final tokenization = _tokenize(text, fontSize);
    _tokenCache[key] = tokenization;
    if (_tokenCache.length > _tokenCacheLimit) {
      _tokenCache.remove(_tokenCache.keys.first);
    }
    return tokenization;
  }

  void markAtlasDirty() {
    _forceGlyphResend = true;
  }

  void markAtlasSynced() {
    _forceGlyphResend = false;
  }

  Future<Next2PreparedFramePayload> buildPayload({
    required List<PositionedDanmakuItem> items,
    required double fontSize,
    required double scaleX,
    required double scaleY,
    required double fontScale,
    required Locale? locale,
    double playbackRate = 1.0,
    String? prefetchChars,
  }) async {
    final itemsJson = StringBuffer('[');
    final Map<String, _EmojiBuildRequest> pending =
        <String, _EmojiBuildRequest>{};
    var firstItem = true;

    for (final item in items) {
      final renderedFontSize =
          (fontSize * fontScale * item.content.fontSizeMultiplier)
              .clamp(8.0, 256.0)
              .toDouble();

      final textTokens = _tokenizeCached(
        item.content.text,
        renderedFontSize,
      );
      _registerPending(textTokens, pending);

      _CachedTokenization? countTokens;
      if (item.content.countText case final countText?) {
        countTokens = _tokenizeCached(' $countText', renderedFontSize);
        _registerPending(countTokens, pending);
      }

      if (!firstItem) {
        itemsJson.write(',');
      }
      firstItem = false;
      itemsJson
        ..write('{"text":')
        ..write(textTokens.sourceJson)
        ..write(',"count_text":')
        ..write(
          item.content.countText == null
              ? 'null'
              : jsonEncode(item.content.countText),
        )
        ..write(',"x":')
        ..write(_finiteJsonNumber(item.x * scaleX))
        ..write(',"y":')
        ..write(_finiteJsonNumber(item.y * scaleY))
        ..write(',"color_argb":')
        ..write(item.content.color.toARGB32().toSigned(32))
        ..write(',"font_size_multiplier":')
        ..write(_finiteJsonNumber(item.content.fontSizeMultiplier))
        ..write(',"is_me":')
        ..write(item.content.isMe)
        ..write(',"width":')
        ..write(_finiteJsonNumber(item.width * scaleX))
        ..write(',"scroll_speed":')
        ..write(
          _finiteJsonNumber(
            _signedScrollSpeed(item, scaleX, playbackRate),
          ),
        );

      if (textTokens.tokenEntriesJson.isNotEmpty ||
          (countTokens?.tokenEntriesJson.isNotEmpty ?? false)) {
        itemsJson.write(',"tokens":[');
        if (textTokens.tokenEntriesJson.isNotEmpty) {
          itemsJson.write(textTokens.tokenEntriesJson);
        }
        if (countTokens != null && countTokens.tokenEntriesJson.isNotEmpty) {
          if (textTokens.tokenEntriesJson.isNotEmpty) {
            itemsJson.write(',');
          }
          itemsJson.write(countTokens.tokenEntriesJson);
        }
        itemsJson.write(']');
      }
      itemsJson.write('}');
    }
    itemsJson.write(']');

    final cachedVisibleGlyphs = <_EmojiGlyphRaster>[];
    final newVisibleGlyphs = <_EmojiGlyphRaster>[];

    int generated = 0;
    for (final request in pending.values) {
      var glyph = _glyphCache[request.key];
      if (glyph != null) {
        _touchGlyph(request.key, glyph);
        cachedVisibleGlyphs.add(glyph);
        continue;
      }

      if (generated >= _maxNewGlyphsPerFrame) {
        continue;
      }

      glyph = await _buildEmojiGlyph(request, locale);
      if (glyph == null) {
        continue;
      }

      _insertGlyph(glyph);
      newVisibleGlyphs.add(glyph);
      generated++;
    }

    final visibleGlyphs = <_EmojiGlyphRaster>[];
    if (_forceGlyphResend || newVisibleGlyphs.isNotEmpty) {
      visibleGlyphs.addAll(cachedVisibleGlyphs);
    }
    visibleGlyphs.addAll(newVisibleGlyphs);

    return Next2PreparedFramePayload(
      frameJson: _encodeFrameJson(
        itemsJson: itemsJson,
        emojiGlyphs: visibleGlyphs,
        prefetchChars: prefetchChars,
      ),
    );
  }

  static void _registerPending(
    _CachedTokenization tokenization,
    Map<String, _EmojiBuildRequest> pending,
  ) {
    for (final request in tokenization.emojiRequests) {
      pending.putIfAbsent(request.key, () => request);
    }
  }

  static String _encodeFrameJson({
    required StringBuffer itemsJson,
    required List<_EmojiGlyphRaster> emojiGlyphs,
    required String? prefetchChars,
  }) {
    final out = StringBuffer('{"items":')..write(itemsJson);
    if (emojiGlyphs.isNotEmpty) {
      out.write(',"emoji_glyphs":[');
      for (var i = 0; i < emojiGlyphs.length; i++) {
        if (i > 0) out.write(',');
        out.write(emojiGlyphs[i].toJsonString());
      }
      out.write(']');
    }
    if (prefetchChars != null && prefetchChars.isNotEmpty) {
      out
        ..write(',"prefetch_chars":')
        ..write(jsonEncode(prefetchChars));
    }
    out.write('}');
    return out.toString();
  }

  static String _finiteJsonNumber(double value) {
    return value.isFinite ? value.toString() : '0.0';
  }

  /// Signed scroll velocity in texture px/s for native interpolation.
  /// typeCode 6 = ScrollLR (moves right, +), 1 = ScrollRL (moves left, -).
  /// Static items or unknown typeCode → 0 (no interpolation, safe fallback).
  ///
  /// `playbackRate` folds the video playback speed into the velocity so the
  /// native renderer (which advances interpolation by pure wall-clock dt)
  /// matches the Dart side's rate-scaled position advancement. Without this,
  /// at 2× speed the native inter-submission interpolation lags behind the
  /// Dart-submitted x, causing a snap-back each frame. Default 1.0 = no
  /// change (Next2 path, which doesn't interpolate anyway).
  static double _signedScrollSpeed(
    PositionedDanmakuItem item,
    double scaleX,
    double playbackRate,
  ) {
    if (item.scrollSpeed == 0.0) return 0.0;
    final magnitude = item.scrollSpeed * scaleX * playbackRate;
    switch (item.typeCode) {
      case 6:
        return magnitude;
      case 1:
        return -magnitude;
      default:
        return 0.0;
    }
  }

  _CachedTokenization _tokenize(
    String text,
    double fontSize,
  ) {
    if (text.isEmpty) {
      return const _CachedTokenization(
        sourceJson: '""',
        tokenEntriesJson: '',
        emojiRequests: <_EmojiBuildRequest>[],
      );
    }

    final out = <String>[];
    final emojiRequests = <_EmojiBuildRequest>[];
    final plainBuffer = StringBuffer();

    for (final cluster in text.characters) {
      if (isEmojiCluster(cluster)) {
        if (plainBuffer.isNotEmpty) {
          out.add(
            '{"k":"t","t":${jsonEncode(plainBuffer.toString())}}',
          );
          plainBuffer.clear();
        }

        final int quantizedSize = fontSize.round().clamp(8, 256);
        final key = _emojiKey(cluster, quantizedSize);

        emojiRequests.add(
          _EmojiBuildRequest(
            key: key,
            cluster: cluster,
            fontSize: quantizedSize.toDouble(),
          ),
        );

        out.add('{"k":"e","id":${jsonEncode(key)}}');
      } else {
        plainBuffer.write(cluster);
      }
    }

    if (plainBuffer.isNotEmpty) {
      out.add('{"k":"t","t":${jsonEncode(plainBuffer.toString())}}');
    }

    return _CachedTokenization(
      sourceJson: jsonEncode(text),
      tokenEntriesJson: out.join(','),
      emojiRequests: List<_EmojiBuildRequest>.unmodifiable(emojiRequests),
    );
  }

  Future<_EmojiGlyphRaster?> _buildEmojiGlyph(
    _EmojiBuildRequest request,
    Locale? locale,
  ) async {
    final painter = _layoutEmojiPainter(
      request.cluster,
      request.fontSize,
      locale,
    );

    final width = painter.width;
    final height = painter.height;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return null;
    }

    final int drawWidth = width.ceil().clamp(1, 512);
    final int drawHeight = height.ceil().clamp(1, 512);
    final int padding = math.max(4, (request.fontSize * 0.28).round());

    final int imageWidth = (drawWidth + padding * 2).clamp(1, 1024);
    final int imageHeight = (drawHeight + padding * 2).clamp(1, 1024);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    painter.paint(canvas, Offset(padding.toDouble(), padding.toDouble()));

    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();

    if (byteData == null) {
      return null;
    }

    final rgba = byteData.buffer.asUint8List();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    return _EmojiGlyphRaster(
      key: request.key,
      width: imageWidth,
      height: imageHeight,
      advance: width,
      offsetX: -padding.toDouble(),
      offsetY: -(baseline + padding),
      rgba: Uint8List.fromList(rgba),
    );
  }

  void _insertGlyph(_EmojiGlyphRaster glyph) {
    if (_glyphCache.length >= _glyphCacheLimit && _glyphCache.isNotEmpty) {
      _glyphCache.remove(_glyphCache.keys.first);
    }
    _glyphCache[glyph.key] = glyph;
  }

  void _touchGlyph(String key, _EmojiGlyphRaster glyph) {
    _glyphCache.remove(key);
    _glyphCache[key] = glyph;
  }

  static String _emojiKey(String emoji, int fontPx) => '$fontPx::$emoji';

  /// Uses the same grapheme classification for layout measurement and GPU
  /// tokenization. Keeping this public avoids the collision system treating a
  /// ZWJ/flag/skin-tone sequence differently from the renderer.
  static bool isEmojiCluster(String cluster) {
    if (cluster.isEmpty) {
      return false;
    }

    bool hasEmojiRune = false;
    for (final rune in cluster.runes) {
      if (_isEmojiRune(rune)) {
        hasEmojiRune = true;
      }
    }
    return hasEmojiRune;
  }

  /// Logical-width advance reserved by DFM+ for one emoji token. The base
  /// advance comes from the exact TextPainter used to build the emoji bitmap;
  /// the extra bearing mirrors renderer_draw.rs's two-sided emoji bearing.
  static double measureEmojiLayoutAdvance(
    String cluster,
    double fontSize,
    Locale? locale,
  ) {
    final painter = _layoutEmojiPainter(cluster, fontSize, locale);
    final sideBearing = (fontSize * 0.08).clamp(1.0, 5.0).toDouble();
    return painter.width + sideBearing * 2.0;
  }

  static TextPainter _layoutEmojiPainter(
    String cluster,
    double fontSize,
    Locale? locale,
  ) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.normal,
      color: Colors.white,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return TextPainter(
      text: TextSpan(text: cluster, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      locale: locale,
      maxLines: 1,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: true,
        applyHeightToLastDescent: true,
      ),
    )..layout(minWidth: 0.0, maxWidth: double.infinity);
  }

  static bool _isEmojiRune(int rune) {
    return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x1FC00 && rune <= 0x1FFFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x2B00 && rune <= 0x2BFF) ||
        (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
        rune == 0x200D ||
        rune == 0xFE0F ||
        rune == 0x20E3;
  }
}

class _EmojiBuildRequest {
  const _EmojiBuildRequest({
    required this.key,
    required this.cluster,
    required this.fontSize,
  });

  final String key;
  final String cluster;
  final double fontSize;

  double get estimatedAdvance => fontSize;
}

class _CachedTokenization {
  const _CachedTokenization({
    required this.sourceJson,
    required this.tokenEntriesJson,
    required this.emojiRequests,
  });

  /// JSON string literal for the original source text.
  final String sourceJson;

  /// Comma-separated token object fragments, without surrounding brackets.
  final String tokenEntriesJson;
  final List<_EmojiBuildRequest> emojiRequests;
}

class _EmojiGlyphRaster {
  _EmojiGlyphRaster({
    required this.key,
    required this.width,
    required this.height,
    required this.advance,
    required this.offsetX,
    required this.offsetY,
    required this.rgba,
  });

  final String key;
  final int width;
  final int height;
  final double advance;
  final double offsetX;
  final double offsetY;
  final Uint8List rgba;

  String? _jsonCache;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': key,
      'w': width,
      'h': height,
      'adv': advance,
      'ox': offsetX,
      'oy': offsetY,
      'rgba_b64': base64Encode(rgba),
    };
  }

  /// Emoji rasters can be resent after a native atlas rebuild. Cache their
  /// base64/JSON representation so a resend does not re-encode the bitmap on
  /// the UI isolate.
  String toJsonString() {
    return _jsonCache ??= jsonEncode(toJson());
  }
}
