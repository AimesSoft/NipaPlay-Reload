import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The picture's room while a video plays with the conversation beside it.
///
/// The panel tells how far in it is ([slide]: 0 away, 1 in, a hair past on
/// its spring); what is watched (Classic's video with its subtitles and
/// danmaku) and the player's controls go left of it ([NextStageRoom]):
/// nothing being watched lies under the conversation, and when it goes the
/// picture has the whole window again.
///
/// [stepped] while the video is drawn by the system under the window (Erika,
/// Media Kit's native video): that picture follows Classic's layout on its
/// own timer, not frame by frame, so the room is taken in one step as the
/// panel starts in and given back once it is out.
class NextStage extends InheritedWidget {
  const NextStage({
    super.key,
    required this.slide,
    this.stepped = false,
    required super.child,
  });

  final ValueNotifier<double> slide;
  final bool stepped;

  static NextStage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NextStage>();

  @override
  bool updateShouldNotify(NextStage old) =>
      !identical(old.slide, slide) || old.stepped != stepped;

  /// Around the panel, and between it and the picture.
  static const margin = 12.0;

  /// The panel's width beside a video: its own ([panelMax]) where the
  /// window leaves the picture [pictureMin] with it, narrower down to
  /// [panelMin] where it does not.
  static const panelMax = 520.0;
  static const panelMin = 360.0;
  static const pictureMin = 600.0;

  static double panelWidth(double window) =>
      (window - 2 * margin - pictureMin).clamp(panelMin, panelMax);

  /// How far the panel slides in: its width and a little more, so that it
  /// starts outside the window.
  static double travel(double panel) => panel + 40;

  /// What the picture gives up on the right in a window [window] wide with
  /// the panel at [slide]: up to the panel's left edge, and a margin.
  static double cover(double window, double slide) {
    final panel = panelWidth(window);
    final edge = panel + 2 * margin - (1 - slide) * travel(panel);
    return edge.clamp(0.0, window);
  }
}

/// [child] in the picture's room: the whole window while the conversation
/// is away (or not [docked] beside a video), the part left of it while it
/// is. Follows the panel by layout and paint only, never a rebuild.
///
/// With [fit], [child] keeps the whole window's layout and is drawn scaled
/// into the room, centred: Classic's video with its subtitles, danmaku and
/// everything over it shrinks as one picture, nothing in it laid out again
/// (its danmaku renderer would make a new texture at every size). Without,
/// [child] is laid out in the room, as in a window that much narrower;
/// [stepped], in one step (see [NextStage.stepped]). With [backdrop], black
/// fills the window around it, under the panel.
class NextStageRoom extends SingleChildRenderObjectWidget {
  const NextStageRoom({
    super.key,
    required this.slide,
    this.docked = true,
    this.fit = false,
    this.stepped = false,
    this.backdrop = false,
    required Widget super.child,
  });

  final ValueListenable<double> slide;
  final bool docked;
  final bool fit;
  final bool stepped;
  final bool backdrop;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderNextStageRoom(
      slide: slide,
      docked: docked,
      fit: fit,
      stepped: stepped,
      backdrop: backdrop);

  @override
  void updateRenderObject(
          BuildContext context, RenderNextStageRoom renderObject) =>
      renderObject
        ..slide = slide
        ..docked = docked
        ..fit = fit
        ..stepped = stepped
        ..backdrop = backdrop;
}

class RenderNextStageRoom extends RenderProxyBox {
  RenderNextStageRoom({
    required ValueListenable<double> slide,
    required bool docked,
    required bool fit,
    required bool stepped,
    required bool backdrop,
  })  : _slide = slide,
        _docked = docked,
        _fit = fit,
        _stepped = stepped,
        _backdrop = backdrop;

  ValueListenable<double> _slide;
  set slide(ValueListenable<double> value) {
    if (identical(value, _slide)) return;
    if (attached) _slide.removeListener(markNeedsLayout);
    _slide = value;
    if (attached) _slide.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  bool _docked, _fit, _stepped, _backdrop;
  set docked(bool value) {
    if (value == _docked) return;
    _docked = value;
    markNeedsLayout();
  }

  set fit(bool value) {
    if (value == _fit) return;
    _fit = value;
    markNeedsLayout();
  }

  set stepped(bool value) {
    if (value == _stepped) return;
    _stepped = value;
    markNeedsLayout();
  }

  set backdrop(bool value) {
    if (value == _backdrop) return;
    _backdrop = value;
    markNeedsPaint();
  }

  /// Where the child is drawn, and how.
  Rect _frame = Rect.zero;
  Matrix4 _transform = Matrix4.identity();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _slide.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _slide.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final slide = _slide.value;
    final cover = !_docked
        ? 0.0
        : _stepped && !_fit
            ? (slide > 0 ? NextStage.cover(size.width, 1) : 0.0)
            : NextStage.cover(size.width, slide);
    final room = Size(math.max(0.0, size.width - cover), size.height);
    if (_fit) {
      child?.layout(BoxConstraints.tight(size));
      final scale = size.isEmpty
          ? 1.0
          : math.min(room.width / size.width, room.height / size.height);
      final drawn = size * scale;
      final at = Offset(
          (room.width - drawn.width) / 2, (room.height - drawn.height) / 2);
      _frame = at & drawn;
      _transform = Matrix4.translationValues(at.dx, at.dy, 0)
        ..scaleByDouble(scale, scale, 1, 1);
    } else {
      child?.layout(BoxConstraints.tight(room));
      _frame = Offset.zero & room;
      _transform = Matrix4.identity();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final whole = offset & size;
    final frame = _frame.shift(offset);
    if (_backdrop && frame != whole) {
      final black = Paint()..color = const Color(0xFF000000);
      // Under the picture drawn smaller too, so its edges, between pixels,
      // blend into black and not into a see-through seam. A picture the
      // system draws lies under the window and shows through where nothing
      // is painted: there, only right of the room.
      context.canvas.drawRect(
          _fit
              ? whole
              : Rect.fromLTRB(
                  frame.right, whole.top, whole.right, whole.bottom),
          black);
    }
    final child = this.child;
    if (child == null) {
      layer = null;
      _transformLayer.layer = null;
      return;
    }
    // Only the picture: what Classic keeps just off its edges (a hairline
    // above it, a menu waiting off to the right) stays out of sight. Drawn
    // smaller, a pixel inside: a hard clip rounds out to whole pixels.
    final scaled = _fit && _frame != Offset.zero & size;
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      scaled ? _frame.deflate(1) : _frame,
      (context, offset) => _transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _transform,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _transformLayer.layer,
      ),
      oldLayer: layer is ClipRectLayer ? layer as ClipRectLayer : null,
    );
  }

  final _transformLayer = LayerHandle<TransformLayer>();

  @override
  void dispose() {
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || !_frame.contains(position)) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}
