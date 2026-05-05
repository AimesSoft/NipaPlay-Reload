import 'dart:js_interop';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

// ---------------------------------------------------------------------------
// JS side helpers (defined in web/index.html's inline <script>):
//   window._nipaLibassCreate(videoElem, subUrl, subContent)
//   window._nipaLibassDispose()
//   window._nipaLibassResize()
//   window._nipaLibassSetTimeOffset(offsetSeconds)
//   window._nipaLibassIsActive() -> bool
// ---------------------------------------------------------------------------

@JS('_nipaLibassCreate')
external void _jsCreate(JSAny videoElem, JSString subUrl, JSString subContent);

@JS('_nipaLibassDispose')
external void _jsDispose();

@JS('_nipaLibassResize')
external void _jsResize();

@JS('_nipaLibassSetTimeOffset')
external void _jsSetTimeOffset(JSNumber offset);

@JS('_nipaLibassIsActive')
external JSBoolean _jsIsActive();

// Check whether the JS helper was actually injected (guards against missing script tag).
@JS('_nipaLibassCreate')
external JSAny? get _jsCreateRef;

class LibassWebBridge {
  static bool get available => _jsCreateRef != null;
  static bool get isActive => _jsIsActive().toDart;

  static Future<void> initWithUrl(String subUrl) async {
    if (!available) {
      debugPrint('[LibassWebBridge] JS helpers not loaded — skipping initWithUrl');
      return;
    }
    final video = _findVideoElement();
    if (video == null) {
      debugPrint('[LibassWebBridge] No <video> element found in DOM');
      return;
    }
    _jsCreate(video, subUrl.toJS, ''.toJS);
    debugPrint('[LibassWebBridge] initWithUrl: $subUrl');
  }

  static Future<void> initWithContent(String assContent) async {
    if (!available) {
      debugPrint('[LibassWebBridge] JS helpers not loaded — skipping initWithContent');
      return;
    }
    final video = _findVideoElement();
    if (video == null) {
      debugPrint('[LibassWebBridge] No <video> element found in DOM');
      return;
    }
    _jsCreate(video, ''.toJS, assContent.toJS);
    debugPrint('[LibassWebBridge] initWithContent (${assContent.length} chars)');
  }

  static void dispose() {
    if (!available) return;
    _jsDispose();
    debugPrint('[LibassWebBridge] disposed');
  }

  static void resize() {
    if (!available || !isActive) return;
    _jsResize();
  }

  static void setTimeOffset(double seconds) {
    if (!available || !isActive) return;
    _jsSetTimeOffset(seconds.toJS);
  }

  // Returns the first <video> element that is currently playing (or the first one found).
  static web.Element? _findVideoElement() {
    // Prefer a playing video element.
    final all = web.document.querySelectorAll('video');
    for (var i = 0; i < all.length; i++) {
      final el = all.item(i) as web.HTMLVideoElement?;
      if (el != null && !el.paused) return el;
    }
    // Fall back to the first video element.
    return web.document.querySelector('video');
  }
}
