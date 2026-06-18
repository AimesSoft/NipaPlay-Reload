import 'dart:convert';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';

class Next2PreparedFramePayload {
  const Next2PreparedFramePayload({
    required this.items,
    required this.emojiGlyphs,
  });

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> emojiGlyphs;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'items': items,
      if (emojiGlyphs.isNotEmpty) 'emoji_glyphs': emojiGlyphs,
    };
  }
}

class Next2EmojiPipeline {
  static const int _glyphCacheLimit = 1200;
  static const int _maxNewGlyphsPerFrame = 16;
  static final LinkedHashMap<String, _EmojiGlyphRaster> _glyphCache =
      LinkedHashMap<String, _EmojiGlyphRaster>();

  bool _forceGlyphResend = true;

  /// Cache of tokenize results for plain (emoji-free) text. _tokenize is a
  /// pure function of (text, fontSize) when the text contains no emoji
  /// clusters — the result is a single {'k':'t','t':text} token and no
  /// pending emoji registration. The vast majority of danmaku are plain
  /// text, so this skips re-splitting + re-allocating the token list every
  /// frame for repeated/long-lived items. Emoji-bearing text bypasses the
  /// cache (it must re-register pending emoji each frame). LRU-bounded.
  static const int _tokenCacheLimit = 2000;
  final LinkedHashMap<String, List<Map<String, dynamic>>> _plainTokenCache =
      LinkedHashMap<String, List<Map<String, dynamic>>>();

  /// Returns cached tokenize result for emoji-free text, or null if the text
  /// contains emoji clusters (caller falls back to full _tokenize which
  /// registers pending emoji builds). Key folds in quantized fontSize.
  List<Map<String, dynamic>>? _cachedPlainTokens(String text, double fontSize) {
    if (text.isEmpty) return const <Map<String, dynamic>>[];
    // Quick emoji presence check without iterating unless likely.
    for (final cluster in text.characters) {
      if (_looksLikeEmojiCluster(cluster)) {
        return null; // has emoji → not cacheable here
      }
    }
    final key = '${fontSize.round().clamp(8, 256)}\u0000$text';
    final cached = _plainTokenCache[key];
    if (cached != null) {
      // LRU touch
      _plainTokenCache.remove(key);
      _plainTokenCache[key] = cached;
      return cached;
    }
    final tokens = <Map<String, dynamic>>[
      <String, dynamic>{'k': 't', 't': text},
    ];
    _plainTokenCache[key] = tokens;
    if (_plainTokenCache.length > _tokenCacheLimit) {
      _plainTokenCache.remove(_plainTokenCache.keys.first);
    }
    return tokens;
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
  }) async {
    final List<Map<String, dynamic>> encodedItems = <Map<String, dynamic>>[];
    final Map<String, _EmojiBuildRequest> pending =
        <String, _EmojiBuildRequest>{};

    for (final item in items) {
      final renderedFontSize =
          (fontSize * fontScale * item.content.fontSizeMultiplier)
              .clamp(8.0, 256.0)
              .toDouble();

      // Plain-text (emoji-free) tokenize results are cached: _tokenize is
      // pure for emoji-free text and the result doesn't depend on x/y. Most
      // danmaku hit this path, avoiding per-frame re-split + token list
      // allocation. Emoji-bearing text falls back to full _tokenize (which
      // registers pending emoji builds).
      var tokens = _cachedPlainTokens(item.content.text, renderedFontSize);
      tokens ??= _tokenize(item.content.text, renderedFontSize, pending);
      if (item.content.countText case final countText?) {
        final countTokens = _cachedPlainTokens(' $countText', renderedFontSize);
        if (countTokens != null) {
          tokens = List<Map<String, dynamic>>.from(tokens)..addAll(countTokens);
        } else {
          final fresh = _tokenize(' $countText', renderedFontSize, pending);
          if (fresh.isNotEmpty) {
            tokens = List<Map<String, dynamic>>.from(tokens)..addAll(fresh);
          }
        }
      }

      encodedItems.add(<String, dynamic>{
        'text': item.content.text,
        'count_text': item.content.countText,
        'x': item.x * scaleX,
        'y': item.y * scaleY,
        'color_argb': item.content.color.toARGB32().toSigned(32),
        'font_size_multiplier': item.content.fontSizeMultiplier,
        // Signed scroll velocity in TEXTURE px/s (RL<0, LR>0, static=0).
        // Lets the native renderer interpolate `x_render = x + scroll_speed*dt`
        // between Dart submissions, so 30fps submits yield smooth 60/120fps
        // motion. scaleX maps layout px/s → texture px/s, matching how `x`
        // is scaled above. Non-DFM sources leave typeCode=0 → 0 (no interp).
        'scroll_speed': _signedScrollSpeed(item, scaleX, playbackRate),
        if (tokens.isNotEmpty) 'tokens': tokens,
      });
    }

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

    final visibleGlyphs = <Map<String, dynamic>>[];
    if (_forceGlyphResend || newVisibleGlyphs.isNotEmpty) {
      for (final glyph in cachedVisibleGlyphs) {
        visibleGlyphs.add(glyph.toJson());
      }
    }
    for (final glyph in newVisibleGlyphs) {
      visibleGlyphs.add(glyph.toJson());
    }

    return Next2PreparedFramePayload(
      items: encodedItems,
      emojiGlyphs: visibleGlyphs,
    );
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

  List<Map<String, dynamic>> _tokenize(
    String text,
    double fontSize,
    Map<String, _EmojiBuildRequest> pending,
  ) {
    if (text.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final out = <Map<String, dynamic>>[];
    final plainBuffer = StringBuffer();

    for (final cluster in text.characters) {
      if (_looksLikeEmojiCluster(cluster)) {
        if (plainBuffer.isNotEmpty) {
          out.add(<String, dynamic>{'k': 't', 't': plainBuffer.toString()});
          plainBuffer.clear();
        }

        final int quantizedSize = fontSize.round().clamp(8, 256);
        final key = _emojiKey(cluster, quantizedSize);

        pending.putIfAbsent(
          key,
          () => _EmojiBuildRequest(
            key: key,
            cluster: cluster,
            fontSize: quantizedSize.toDouble(),
          ),
        );

        out.add(<String, dynamic>{'k': 'e', 'id': key});
      } else {
        plainBuffer.write(cluster);
      }
    }

    if (plainBuffer.isNotEmpty) {
      out.add(<String, dynamic>{'k': 't', 't': plainBuffer.toString()});
    }

    return out;
  }

  Future<_EmojiGlyphRaster?> _buildEmojiGlyph(
    _EmojiBuildRequest request,
    Locale? locale,
  ) async {
    final style = TextStyle(
      fontSize: request.fontSize,
      fontWeight: FontWeight.normal,
      color: Colors.white,
      height: 1.0,
      leadingDistribution: TextLeadingDistribution.even,
    );

    final painter = TextPainter(
      text: TextSpan(text: request.cluster, style: style),
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

  bool _looksLikeEmojiCluster(String cluster) {
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

  bool _isEmojiRune(int rune) {
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

class _EmojiGlyphRaster {
  const _EmojiGlyphRaster({
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
}
