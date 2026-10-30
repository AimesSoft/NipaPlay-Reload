import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The subtitle settings Classic and Next share (D3), as Next applies them:
/// the same preference keys, read when a session opens and again when one
/// of them changes.
///
/// A file drawn over the video takes the overlay's own size, colour and
/// font (Classic's long press on it sets them) and its own delay and place
/// (kept per file); a subtitle the kernel draws takes the player's size and
/// text style. What the kernel cannot do (MDK has no subtitle delay) is
/// reported as such ([facts]).
@immutable
final class SubtitleLook {
  const SubtitleLook({
    this.kernelScale = 1,
    this.overlayScale = 1,
    this.color = 0xFFFFFFFF,
    this.borderColor = 0xFF000000,
    this.overlayColor = 0xFFFFFFFF,
    this.overlayFont = '',
    this.bold = false,
    this.italic = false,
    this.borderSize = 3,
    this.shadowOffset = 0,
    this.opacity = 1,
    this.alignX = 1,
    this.position = 100,
    this.alignY = 2,
    this.marginX = 0,
    this.marginY = 0,
    this.shadowColor = 0xFF000000,
    this.fontName = '',
    this.overrideMode = 0,
    this.fontsDir = '',
    this.kernelDelaySeconds = 0,
    this.overlayDelaySeconds = 0,
  });

  static const minScale = 0.5;
  static const maxScale = 2.5;
  static const delayStep = 0.1;

  /// The kernel's subtitles: `subtitle_scale`.
  final double kernelScale;

  /// Files drawn over the video: `srt_subtitle_scale`.
  final double overlayScale;

  /// The kernel's text subtitles: `subtitle_color`, `subtitle_border_color`.
  final int color;
  final int borderColor;

  /// Files drawn over the video: `external_subtitle_color`,
  /// `external_subtitle_font_name`.
  final int overlayColor;
  final String overlayFont;

  /// Both: `subtitle_bold`, `subtitle_italic`.
  final bool bold;
  final bool italic;

  /// Over the video: `subtitle_border_size`, `subtitle_shadow_offset`,
  /// `subtitle_opacity`, `subtitle_align_x` (0 left, 1 centre, 2 right).
  final double borderSize;
  final double shadowOffset;
  final double opacity;
  final int alignX;

  /// The kernel's subtitles, where the kernel places and styles them
  /// ([KernelCapabilities.subtitleStyle]): `subtitle_position` (0 top …
  /// 100 bottom), `subtitle_align_y` (0 top, 1 centre, 2 bottom),
  /// `subtitle_margin_x`, `subtitle_margin_y`, `subtitle_shadow_color`,
  /// `subtitle_font_name`, and `subtitle_override_mode` (Classic's auto,
  /// none, scale, force: how far the style above replaces an ASS file's).
  final double position;
  final int alignY;
  final double marginX;
  final double marginY;
  final int shadowColor;
  final String fontName;
  final int overrideMode;

  /// `subtitle_font_dir`: the font library's folder, where the kernel finds
  /// [fontName] (and an ASS file's own fonts) when they are not installed.
  final String fontsDir;

  /// `subtitle_delay_seconds`: Classic's delay for the kernel's subtitles.
  final double kernelDelaySeconds;

  /// `srt_subtitle_delay`: the delay of every file drawn over the video,
  /// added to each file's own.
  final double overlayDelaySeconds;

  static double _clampScale(double? v) =>
      (v ?? 1).clamp(minScale, maxScale).toDouble();

  static SubtitleLook read(SharedPreferences prefs) => SubtitleLook(
        kernelScale: _clampScale(prefs.getDouble('subtitle_scale')),
        overlayScale: _clampScale(prefs.getDouble('srt_subtitle_scale')),
        color: prefs.getInt('subtitle_color') ?? 0xFFFFFFFF,
        borderColor: prefs.getInt('subtitle_border_color') ?? 0xFF000000,
        overlayColor: prefs.getInt('external_subtitle_color') ?? 0xFFFFFFFF,
        overlayFont: prefs.getString('external_subtitle_font_name') ?? '',
        bold: prefs.getBool('subtitle_bold') ?? false,
        italic: prefs.getBool('subtitle_italic') ?? false,
        borderSize: prefs.getDouble('subtitle_border_size') ?? 3,
        shadowOffset: prefs.getDouble('subtitle_shadow_offset') ?? 0,
        opacity: (prefs.getDouble('subtitle_opacity') ?? 1).clamp(0.0, 1.0),
        alignX: (prefs.getInt('subtitle_align_x') ?? 1).clamp(0, 2),
        position:
            (prefs.getDouble('subtitle_position') ?? 100).clamp(0.0, 100.0),
        alignY: (prefs.getInt('subtitle_align_y') ?? 2).clamp(0, 2),
        marginX: prefs.getDouble('subtitle_margin_x') ?? 0,
        marginY: prefs.getDouble('subtitle_margin_y') ?? 0,
        shadowColor: prefs.getInt('subtitle_shadow_color') ?? 0xFF000000,
        fontName: prefs.getString('subtitle_font_name') ?? '',
        overrideMode: (prefs.getInt('subtitle_override_mode') ?? 0).clamp(0, 3),
        fontsDir: prefs.getString('subtitle_font_dir') ?? '',
        kernelDelaySeconds: prefs.getDouble('subtitle_delay_seconds') ?? 0,
        overlayDelaySeconds: prefs.getDouble('srt_subtitle_delay') ?? 0,
      );

  /// MDK's colours are RGBA; the settings keep ARGB.
  static String _rgba(int argb) {
    final rgba = ((argb & 0x00FFFFFF) << 8) | ((argb >> 24) & 0xFF);
    return '0x${rgba.toRadixString(16).padLeft(8, '0')}';
  }

  /// What the kernel is told of how it draws subtitles. MDK's text style
  /// (colour, outline, bold, italic, the base font size Classic gives MDK)
  /// holds for text tracks, not ASS; its scale holds for all. The rest is
  /// for a kernel that places and styles subtitles itself (mpv): each maps
  /// what it takes and leaves the others. The opacity is the colours'
  /// alpha.
  Map<String, String> kernelProperties() => {
        'subtitle.scale': kernelScale.toStringAsFixed(2),
        'subtitle.font.size': '45',
        'subtitle.color': _rgba(_faded(color)),
        'subtitle.color.outline': _rgba(_faded(borderColor)),
        'subtitle.bold': bold ? '1' : '0',
        'subtitle.italic': italic ? '1' : '0',
        // Seconds, later when positive; a kernel that cannot shift what it
        // draws (MDK) leaves it.
        'subtitle.delay': kernelDelaySeconds.toStringAsFixed(2),
        'subtitle.position': position.round().toString(),
        'subtitle.align.x': const ['left', 'center', 'right'][alignX],
        'subtitle.align.y': const ['top', 'center', 'bottom'][alignY],
        'subtitle.margin.x': marginX.round().toString(),
        'subtitle.margin.y': marginY.round().toString(),
        'subtitle.border.size': borderSize.toStringAsFixed(1),
        'subtitle.shadow.offset': shadowOffset.toStringAsFixed(1),
        'subtitle.color.shadow': _rgba(_faded(shadowColor)),
        'subtitle.font': fontName,
        'subtitle.fonts.dir': fontsDir,
        'subtitle.override': switch (overrideMode) {
          1 => 'no',
          2 => 'scale',
          3 => 'force',
          // Classic's auto: an ASS file's own style, scaled once the size
          // is not 1.
          _ => (kernelScale - 1).abs() < 0.001 ? 'no' : 'scale',
        },
      };

  int _faded(int argb) {
    final alpha = ((argb >> 24) & 0xFF) * opacity.clamp(0.0, 1.0);
    return (alpha.round() << 24) | (argb & 0x00FFFFFF);
  }

  /// The registry's subtitle style settings the kernel draws with, beyond
  /// its size and delay, by the [kernelProperties] each one sets.
  static const kernelStyleKeys = {
    'subtitle.color': ['subtitle.color'],
    'subtitle.borderColor': ['subtitle.color.outline'],
    'subtitle.bold': ['subtitle.bold'],
    'subtitle.italic': ['subtitle.italic'],
    'subtitle.opacity': ['subtitle.color', 'subtitle.color.outline'],
    'subtitle.position': ['subtitle.position'],
    'subtitle.alignX': ['subtitle.align.x'],
    'subtitle.alignY': ['subtitle.align.y'],
    'subtitle.marginX': ['subtitle.margin.x'],
    'subtitle.marginY': ['subtitle.margin.y'],
    'subtitle.borderSize': ['subtitle.border.size'],
    'subtitle.shadowOffset': ['subtitle.shadow.offset'],
    'subtitle.shadowColor': ['subtitle.color.shadow'],
    'subtitle.fontName': ['subtitle.font'],
    'subtitle.fontDir': ['subtitle.fonts.dir'],
    'subtitle.overrideMode': ['subtitle.override'],
  };

  /// [kernelStyle]: the registry keys of [kernelStyleKeys] the kernel
  /// playing draws with ([KernelCapabilities.subtitleStyle]).
  JsonMap toJson({Set<String> kernelStyle = const {}}) => {
        'kernel': {
          'scale': kernelScale,
          'color': color,
          'borderColor': borderColor,
          'bold': bold,
          'italic': italic,
          'position': position,
          'alignY': alignY,
          'marginX': marginX,
          'marginY': marginY,
          'shadowColor': shadowColor,
          'fontName': fontName,
          'fontsDir': fontsDir.isEmpty ? null : 'set',
          'overrideMode': overrideMode,
          'applied': [
            'subtitle.scale',
            for (final key in kernelStyleKeys.keys)
              if (kernelStyle.contains(key)) key
          ],
          'notApplied': {
            'subtitle.delaySeconds': 'the kernel cannot shift its subtitles',
            for (final key in kernelStyleKeys.keys)
              if (!kernelStyle.contains(key))
                key: key == 'subtitle.overrideMode'
                    ? 'the kernel keeps ASS styles as written'
                    : 'not mapped to the kernel',
          },
          'textStyleOnly': 'colour, outline, bold and italic hold for text '
              'tracks; ASS keeps its own styles unless overrideMode forces '
              'them',
          if (kernelDelaySeconds != 0) 'delaySecondsSet': kernelDelaySeconds,
        },
        'overlay': {
          'scale': overlayScale,
          'color': overlayColor,
          'font': overlayFont,
          'bold': bold,
          'italic': italic,
          'borderSize': borderSize,
          'shadowOffset': shadowOffset,
          'opacity': opacity,
          'alignX': alignX,
          'delaySeconds': overlayDelaySeconds,
        },
      };

  @override
  bool operator ==(Object other) =>
      other is SubtitleLook &&
      other.kernelScale == kernelScale &&
      other.overlayScale == overlayScale &&
      other.color == color &&
      other.borderColor == borderColor &&
      other.overlayColor == overlayColor &&
      other.overlayFont == overlayFont &&
      other.bold == bold &&
      other.italic == italic &&
      other.borderSize == borderSize &&
      other.shadowOffset == shadowOffset &&
      other.opacity == opacity &&
      other.alignX == alignX &&
      other.position == position &&
      other.alignY == alignY &&
      other.marginX == marginX &&
      other.marginY == marginY &&
      other.shadowColor == shadowColor &&
      other.fontName == fontName &&
      other.overrideMode == overrideMode &&
      other.fontsDir == fontsDir &&
      other.kernelDelaySeconds == kernelDelaySeconds &&
      other.overlayDelaySeconds == overlayDelaySeconds;

  @override
  int get hashCode => Object.hashAll([
      kernelScale,
      overlayScale,
      color,
      borderColor,
      overlayColor,
      overlayFont,
      bold,
      italic,
      borderSize,
      shadowOffset,
      opacity,
      alignX,
      position,
      alignY,
      marginX,
      marginY,
      shadowColor,
      fontName,
      overrideMode,
      fontsDir,
      kernelDelaySeconds,
      overlayDelaySeconds,
    ]);
}

/// Where one file drawn over the video sits and when: its own delay
/// (seconds, later when positive), height (0 top … 100 bottom) and
/// sideways shift, kept per file under the key Classic keeps it.
@immutable
final class OverlayPlacement {
  const OverlayPlacement(
      {this.delaySeconds = 0, this.position = 90, this.marginX = 0});
  final double delaySeconds;
  final double position;
  final double marginX;

  int get delayMs => (delaySeconds * 1000).round();

  static String key(String path) =>
      'subtitle_display_${sha1.convert(utf8.encode(path))}';

  static OverlayPlacement read(SharedPreferences prefs, String path) {
    final raw = prefs.getString(key(path));
    if (raw == null || raw.isEmpty) return const OverlayPlacement();
    try {
      final map = jsonDecode(raw) as Map;
      return OverlayPlacement(
        delaySeconds: (map['delay'] as num?)?.toDouble() ?? 0,
        position: (map['position'] as num?)?.toDouble() ?? 90,
        marginX: (map['marginX'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return const OverlayPlacement();
    }
  }

  OverlayPlacement withDelay(double seconds) => OverlayPlacement(
      delaySeconds: seconds, position: position, marginX: marginX);

  OverlayPlacement copyWith({double? position, double? marginX}) =>
      OverlayPlacement(
          delaySeconds: delaySeconds,
          position: position ?? this.position,
          marginX: marginX ?? this.marginX);

  Future<void> write(SharedPreferences prefs, String path) => prefs.setString(
      key(path),
      jsonEncode(
          {'delay': delaySeconds, 'position': position, 'marginX': marginX}));

  JsonMap toJson() =>
      {'delaySeconds': delaySeconds, 'position': position, 'marginX': marginX};

  @override
  bool operator ==(Object other) =>
      other is OverlayPlacement &&
      other.delaySeconds == delaySeconds &&
      other.position == position &&
      other.marginX == marginX;

  @override
  int get hashCode => Object.hash(delaySeconds, position, marginX);
}
