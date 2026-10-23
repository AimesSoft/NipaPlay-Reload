import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import '../../harness_redaction.dart';
import '../core/clock.dart';
import '../kernel/driver.dart';
import '../perf/budget.dart';
import 'cue_index.dart';
import 'look.dart';

/// Who drew the subtitle: the kernel, into the picture, or NipaPlay, over it.
enum SubtitleRenderer { kernel, overlay }

/// What is wanted on screen: no subtitle, one of the media's own tracks, or
/// a subtitle file.
@immutable
final class SubtitleWant {
  const SubtitleWant.off()
      : index = null,
        path = null;
  const SubtitleWant.embedded(int this.index) : path = null;
  const SubtitleWant.file(String this.path) : index = null;

  final int? index;
  final String? path;
  bool get off => index == null && path == null;

  JsonMap toJson() => off
      ? const {'kind': 'off'}
      : index != null
          ? {'kind': 'embedded', 'index': index}
          : {'kind': 'external', 'path': redactHarnessText(path!)};

  @override
  bool operator ==(Object other) =>
      other is SubtitleWant && other.index == index && other.path == path;
  @override
  int get hashCode => Object.hash(index, path);
  @override
  String toString() => off
      ? 'off'
      : index != null
          ? 'embedded $index'
          : 'file $path';
}

/// A subtitle file known to this playback: offered by the subtitle library
/// or Mesh, or mounted by the person or Nipa.
@immutable
final class SubtitleFile {
  const SubtitleFile({
    required this.path,
    required this.title,
    required this.format,
    required this.renderer,
    required this.origin,
  });

  /// What is opened: the kernel's mount or the overlay's parse.
  final String path;
  final String title;

  /// Its extension, lowercase, without the dot.
  final String format;
  final SubtitleRenderer renderer;

  /// library, mesh, user, agent.
  final String origin;

  JsonMap toJson() => {
        'path': redactHarnessText(path),
        'title': title,
        'format': format,
        'renderer': renderer.name,
        'origin': origin,
      };
}

/// What shows now, as far as the kernel and the overlay report it.
@immutable
final class PresentedSubtitle {
  const PresentedSubtitle({
    required this.want,
    required this.renderer,
    required this.confirmed,
    required this.selectedBy,
  });
  final SubtitleWant want;
  final SubtitleRenderer renderer;

  /// The kernel reported it on (a decoder opened), or the overlay has the
  /// file's text; false: asked, not yet reported.
  final bool confirmed;
  final String selectedBy;

  JsonMap toJson() => {
        ...want.toJson(),
        'renderer': renderer.name,
        'confirmed': confirmed,
        'selectedBy': selectedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is PresentedSubtitle &&
      other.want == want &&
      other.renderer == renderer &&
      other.confirmed == confirmed &&
      other.selectedBy == selectedBy;
  @override
  int get hashCode => Object.hash(want, renderer, confirmed, selectedBy);
}

/// The subtitles of one playback: what is wanted, by whom and since when;
/// what shows; the files known.
@immutable
final class SubtitleState {
  const SubtitleState({
    this.want = const SubtitleWant.off(),
    this.selectedBy = 'default',
    this.selectedAt,
    this.presented = const [],
    this.files = const [],
    this.failure,
  });
  final SubtitleWant want;

  /// user, agent, library_selection, default (nothing was chosen).
  final String selectedBy;
  final DateTime? selectedAt;

  /// At most one (the invariant: what shows is what was chosen).
  final List<PresentedSubtitle> presented;
  final List<SubtitleFile> files;

  /// Why the last choice does not show, when it does not.
  final String? failure;

  SubtitleState copyWith({
    SubtitleWant? want,
    String? selectedBy,
    DateTime? selectedAt,
    List<PresentedSubtitle>? presented,
    List<SubtitleFile>? files,
    String? Function()? failure,
  }) =>
      SubtitleState(
        want: want ?? this.want,
        selectedBy: selectedBy ?? this.selectedBy,
        selectedAt: selectedAt ?? this.selectedAt,
        presented: presented ?? this.presented,
        files: files ?? this.files,
        failure: failure == null ? this.failure : failure(),
      );
}

/// What the overlay draws now: the line, how, where.
@immutable
final class OverlayFrame {
  const OverlayFrame(this.text, this.look, this.placement);
  final String text;
  final SubtitleLook look;
  final OverlayPlacement placement;

  @override
  bool operator ==(Object other) =>
      other is OverlayFrame &&
      other.text == text &&
      other.look == look &&
      other.placement == placement;
  @override
  int get hashCode => Object.hash(text, look, placement);
}

/// The subtitle library's side, as the session sees it: asked when the
/// media opens, told when the person or Nipa chooses.
typedef SubtitleLoader = Future<bool> Function(String path);
typedef SubtitleRecorder = Future<void> Function(
    String path, int? index, String? external);

/// A session's subtitles (player-core design §1.3 SubtitleController).
///
/// One subtitle at a time: an embedded track or a file the kernel draws
/// (ASS on a kernel with libass, bitmaps), or a text file NipaPlay draws
/// over the video ([overlay]). Switching hides what shows before the next
/// one comes up, the kernel's after it reported off, so that at no moment
/// two show.
///
/// Before the media opens the choice goes into the kernel's open plan
/// ([openPlan]); afterwards each change goes to the kernel in its queue and
/// counts once the kernel reports it. The overlay's text is parsed and
/// indexed off the main isolate; its line changes on a timer set for the
/// next line boundary, and again whenever the clock jumps: nothing polls.
final class SubtitleController {
  SubtitleController({
    required this.clock,
    required this.cues,
    required SubtitleLook look,
    required this.placementOf,
    this.recorderOf,
    this.planWait = const Duration(seconds: 3),
  }) : _look = look;

  final PlaybackClockView clock;
  final CueCache cues;
  final OverlayPlacement Function(String path) placementOf;

  /// Records a choice made in the player (the person's or Nipa's) with the
  /// subtitle library, as Classic's player told it; read when a choice is
  /// made (the library attaches while Next's interface is open).
  SubtitleRecorder? Function()? recorderOf;

  /// How long the open waits for the library's choice before it opens with
  /// nothing on (and puts the choice on when it comes).
  final Duration planWait;

  SubtitleLook _look;
  final _state = ValueNotifier(const SubtitleState());
  final _overlay = ValueNotifier<OverlayFrame?>(null);
  KernelDriver? _driver;
  KernelCapabilities? _capabilities;
  MediaFacts? _media;
  bool _closed = false;
  int _version = 0;
  Future<void> _applying = Future.value();

  // The overlay: the file whose index is up, and its line.
  String? _overlayPath;
  CueIndex? _overlayIndex;
  OverlayPlacement _placement = const OverlayPlacement();
  Timer? _lineTimer;
  bool _listening = false;

  ValueListenable<SubtitleState> get state => _state;

  /// What the overlay draws now; null while it draws nothing.
  ValueListenable<OverlayFrame?> get overlay => _overlay;
  SubtitleLook get look => _look;
  KernelCapabilities? get capabilities => _capabilities;

  SubtitleWant get want => _state.value.want;
  List<SubtitleFile> get files => _state.value.files;
  CueIndex? get overlayIndex => _overlayIndex;
  OverlayPlacement get placement => _placement;

  /// What the overlay's lines are shifted by: the shared delay of files
  /// drawn over the video plus this file's own.
  int get _overlayDelayMs =>
      ((_look.overlayDelaySeconds + _placement.delaySeconds) * 1000).round();

  /// The renderer a file gets on this kernel.
  SubtitleRenderer rendererOf(String path) {
    final format = _format(path);
    final kernel = _capabilities?.subtitleFiles ?? const {'ass', 'ssa', 'sup', 'idx'};
    return kernel.contains(format)
        ? SubtitleRenderer.kernel
        : SubtitleRenderer.overlay;
  }

  static String _format(String path) {
    final uri = Uri.tryParse(path);
    final ext = p.extension(uri?.hasScheme == true ? uri!.path : path);
    return ext.isEmpty ? '' : ext.substring(1).toLowerCase();
  }

  SubtitleFile? fileOf(String path) =>
      files.where((f) => f.path == path).firstOrNull;

  // ---- before the media opens ----

  /// Asks [loader] (the subtitle library) for this media's subtitles: what
  /// it offers and puts on while this waits goes into the open plan.
  Future<void> loadFrom(SubtitleLoader? loader, String path) async {
    if (loader == null) return;
    final asked = PlayerTime.now();
    try {
      await loader(path).timeout(planWait);
    } on TimeoutException {
      _note('library_slow', {'waitedMs': (PlayerTime.now() - asked).inMilliseconds});
    } catch (error) {
      _note('library_failed', {'error': redactHarnessText('$error')});
    }
  }

  /// The kernel's subtitle for the open: what is wanted, if the kernel
  /// draws it.
  KernelTrackPlan openPlan({int? audio}) {
    final target = _kernelTarget(want);
    return KernelTrackPlan(
      audio: audio,
      subtitle: target,
      subtitleProperties: _look.kernelProperties(),
      subtitleProbe: _probe(target),
    );
  }

  /// A text file the kernel draws, parsed too (for its probe and cues).
  CueIndex? _kernelIndex;

  /// A time a line of the kernel-drawn file [target] is on.
  Duration? _probe(KernelSubtitle target) {
    final index = _kernelIndex;
    if (target is! FileKernelSubtitle ||
        index == null ||
        index.path != target.path ||
        index.length == 0) {
      return null;
    }
    return Duration(milliseconds: (index.starts[0] + index.ends[0]) ~/ 2);
  }

  static const _bitmapFormats = {'idx', 'sup', 'sub'};

  Future<void> _indexKernelFile(String path) async {
    if (_kernelIndex?.path == path || _bitmapFormats.contains(_format(path))) {
      return;
    }
    try {
      _kernelIndex = await cues.get(path);
    } catch (error) {
      _note('parse_failed', {'path': redactHarnessText(path), 'error': '$error'});
    }
  }

  KernelSubtitle _kernelTarget(SubtitleWant want) {
    if (want.index case final index?) {
      final count = _media?.subtitles.length;
      if (count != null && index >= count) return KernelSubtitle.none;
      return EmbeddedKernelSubtitle(index);
    }
    if (want.path case final path?) {
      return rendererOf(path) == SubtitleRenderer.kernel
          ? FileKernelSubtitle(path)
          : KernelSubtitle.none;
    }
    return KernelSubtitle.none;
  }

  /// The media opened on [driver] with [tracks]: from now on choices go to
  /// the kernel, and what was not met at the open is put on.
  Future<void> opened(KernelDriver driver, MediaFacts media) async {
    _driver = driver;
    _capabilities = driver.capabilities;
    _media = media;
    _version++;
    await _schedule();
  }

  /// The kernel reported its tracks (an open, a change, a late decoder).
  void kernelReported(KernelTracks tracks) => _publishPresented();

  /// The session closes: nothing more is drawn or asked.
  void close() {
    _closed = true;
    _version++;
    _lineTimer?.cancel();
    _lineTimer = null;
    _listen(false);
    _overlay.value = null;
    _driver = null;
  }

  // ---- what the library, Mesh, the person and Nipa ask ----

  /// A file known to this playback, not put on.
  void offer(String path, String title, {String origin = 'library'}) {
    if (_closed) return;
    if (fileOf(path) != null) return;
    _state.value = _state.value.copyWith(files: [
      ...files,
      SubtitleFile(
        path: path,
        title: title.isEmpty ? p.basename(path) : title,
        format: _format(path),
        renderer: rendererOf(path),
        origin: origin,
      ),
    ]);
  }

  /// Forgets the files [origin] offered (the library tells them again).
  void withdraw(String origin) {
    _state.value = _state.value.copyWith(
        files: [for (final f in files) if (f.origin != origin) f]);
  }

  /// Takes [path] off this playback; off if it was what showed.
  Future<SubtitleState> unmount(String path, {required String by}) async {
    final showing = want.path == path;
    _state.value = _state.value.copyWith(
        files: [for (final f in files) if (f.path != path) f]);
    if (showing) {
      return choose(const SubtitleWant.off(), by: by);
    }
    return _state.value;
  }

  /// Puts [next] on screen (and nothing else). Completes once the kernel or
  /// the overlay reported it, or the wait is up. [record]: the choice is
  /// told to the subtitle library (the person's and Nipa's are).
  Future<SubtitleState> choose(SubtitleWant next,
      {required String by, bool record = false, String? title}) async {
    if (_closed) return _state.value;
    if (next.path case final path?) {
      offer(path, title ?? p.basename(path),
          origin: by == 'library_selection' ? 'library' : by);
    }
    // The same choice again (the library telling back what it recorded)
    // joins the one being put on; it does not overtake it.
    final same = next == want && _inFlight > 0;
    _state.value = _state.value.copyWith(
        want: next,
        selectedBy: by,
        selectedAt: DateTime.now().toUtc(),
        failure: same ? null : () => null);
    final Future<void> applied;
    if (same) {
      applied = _applying;
    } else {
      _version++;
      applied = _schedule();
    }
    if (record) {
      final recorder = recorderOf?.call();
      final index = next.index ?? (next.off ? -1 : null);
      if (recorder != null) {
        unawaited(_recordChoice(recorder, index, next.path));
      }
    }
    await applied;
    return _state.value;
  }

  String? _mediaPath;
  set mediaPath(String path) => _mediaPath = path;

  Future<void> _recordChoice(
      SubtitleRecorder recorder, int? index, String? external) async {
    final media = _mediaPath;
    if (media == null) return;
    try {
      await recorder(media, index, external);
    } catch (error) {
      _note('record_failed', {'error': redactHarnessText('$error')});
    }
  }

  // ---- putting it on (in order; a later choice overtakes) ----

  int _inFlight = 0;

  Future<void> _schedule() {
    final version = _version;
    _inFlight++;
    final run = _applying
        .then((_) => _apply(version))
        .whenComplete(() => _inFlight--);
    _applying = run.catchError((Object _) {});
    return run;
  }

  Future<void> _apply(int version) async {
    if (_closed || version != _version) return;
    final want = this.want;
    final overlayPath = want.path != null &&
            rendererOf(want.path!) == SubtitleRenderer.overlay
        ? want.path
        : null;
    // What is not wanted goes first: the overlay at once…
    if (_overlayPath != overlayPath) _hideOverlay();
    // A text file for the kernel is read too, off the main isolate: it
    // confirms the kernel has it, and gives its cues.
    if (_kernelTarget(want) case FileKernelSubtitle(:final path)) {
      await _indexKernelFile(path);
      if (_closed || version != _version) return;
    }
    // …the kernel's once it reported it off (or on, for its own choice).
    final driver = _driver;
    if (driver != null && !driver.fenced) {
      var target = _kernelTarget(want);
      if (want.index case final index?
          when index >= (_media?.subtitles.length ?? 0)) {
        _fail('no_such_track');
        target = KernelSubtitle.none;
      }
      // Told already (the open plan, an earlier change): its report may
      // still come, and confirms it then.
      if (driver.tracks.subtitle != target) {
        try {
          final tracks =
              await driver.selectSubtitle(target, probe: _probe(target));
          if (tracks.subtitle != target) _fail('kernel_kept_other_track');
        } on KernelFenced {
          return;
        } catch (error) {
          _fail('kernel_failed: ${redactHarnessText('$error')}');
          _publishPresented();
          return;
        }
      }
    }
    _publishPresented();
    if (_closed || version != _version || overlayPath == null) return;
    // Over the video only once the kernel draws nothing.
    if (driver != null && driver.tracks.subtitle.drawn) {
      _fail('kernel_still_drawing');
      return;
    }
    CueIndex index;
    try {
      index = await cues.get(overlayPath);
    } catch (error) {
      _fail('parse_failed: ${redactHarnessText('$error')}');
      _publishPresented();
      return;
    }
    if (_closed || version != _version) return;
    if (index.length == 0) _fail('no_timed_text');
    _overlayPath = overlayPath;
    _overlayIndex = index;
    _placement = placementOf(overlayPath);
    _listen(true);
    _line();
    _publishPresented();
  }

  void _hideOverlay() {
    _overlayPath = null;
    _overlayIndex = null;
    _lineTimer?.cancel();
    _lineTimer = null;
    _listen(false);
    _overlay.value = null;
  }

  void _fail(String why) {
    _state.value = _state.value.copyWith(failure: () => why);
    _note('apply_failed', {'why': why, 'want': want.toJson()});
  }

  void _publishPresented() {
    final s = _state.value;
    final presented = <PresentedSubtitle>[];
    final kernel = _driver?.tracks;
    if (kernel != null && kernel.subtitle.drawn) {
      presented.add(PresentedSubtitle(
        want: switch (kernel.subtitle) {
          EmbeddedKernelSubtitle(:final index) => SubtitleWant.embedded(index),
          FileKernelSubtitle(:final path) => SubtitleWant.file(path),
          NoKernelSubtitle() => const SubtitleWant.off(),
        },
        renderer: SubtitleRenderer.kernel,
        confirmed: kernel.subtitleConfirmed,
        selectedBy: s.selectedBy,
      ));
    }
    if (_overlayPath case final path?) {
      presented.add(PresentedSubtitle(
        want: SubtitleWant.file(path),
        renderer: SubtitleRenderer.overlay,
        confirmed: _overlayIndex != null,
        selectedBy: s.selectedBy,
      ));
    }
    if (listEquals(presented, s.presented)) return;
    _state.value = s.copyWith(presented: presented);
  }

  // ---- the overlay's line ----

  void _listen(bool on) {
    if (on == _listening) return;
    _listening = on;
    on ? clock.addListener(_line) : clock.removeListener(_line);
  }

  /// The line at the clock now, and a timer for the next boundary.
  void _line() => PlayerPerf.span('subtitle.line', () {
        _lineTimer?.cancel();
        _lineTimer = null;
        final index = _overlayIndex;
        if (_closed || index == null) {
          _overlay.value = null;
          return;
        }
        final at = clock.now().inMilliseconds - _overlayDelayMs;
        final line = index.lineAt(at);
        final frame = OverlayFrame(line.text, _look, _placement);
        if (frame != _overlay.value) _overlay.value = frame;
        final until = line.until;
        if (until == null || !clock.advancing) return;
        final rate = clock.rate <= 0 ? 1.0 : clock.rate;
        final wait = ((until - at) / rate).ceil() + 1;
        _lineTimer = Timer(Duration(milliseconds: wait.clamp(1, 1 << 30)), _line);
      });

  /// Another delay or place for the file drawn over the video.
  void placementChanged(String path, OverlayPlacement placement) {
    if (_overlayPath != path) return;
    _placement = placement;
    _line();
  }

  /// The shared settings changed: the kernel is told, the overlay redrawn.
  Future<void> lookChanged(SubtitleLook look) async {
    if (look == _look) return;
    _look = look;
    final driver = _driver;
    if (driver != null && !driver.fenced) {
      try {
        await driver.setSubtitleProperties(look.kernelProperties());
      } on KernelFenced {
        return;
      }
    }
    if (_overlayIndex != null) _line();
  }

  // ---- subtitle.cues ----

  /// The timed text of what shows (player-core design §5.3): the file
  /// drawn over the video, or the file the kernel draws, parsed off the
  /// main isolate; for the media's own tracks, the line the kernel draws
  /// now when it can tell.
  Future<JsonMap> readCues(JsonMap input, {required int positionMs}) async {
    if (input['endMs'] != null &&
        input['startMs'] != null &&
        (input['endMs'] as int) < (input['startMs'] as int)) {
      throw const Failure(FailureCode.invalidInput, 'endMs must be >= startMs.');
    }
    final unsupported = <JsonMap>[];
    final want = this.want;
    JsonMap? kernelLine;
    String? path;
    var delayMs = 0;
    SubtitleRenderer? renderer;
    if (want.path case final file?) {
      renderer = rendererOf(file);
      final format = _format(file);
      if (format == 'idx' || format == 'sup') {
        unsupported.add({'path': redactHarnessText(file), 'reason': 'bitmap_requires_ocr'});
      } else {
        path = file;
        if (renderer == SubtitleRenderer.overlay) delayMs = _overlayDelayMs;
      }
    } else if (want.index != null) {
      unsupported.add({'reason': 'embedded_text_not_extracted'});
    }
    // What the kernel draws now, in its own words, when it can tell.
    final driver = _driver;
    final reading = input['positionMs'] == null &&
        driver != null &&
        !driver.fenced &&
        driver.capabilities.subtitleText &&
        driver.tracks.subtitle.drawn;
    if (reading) {
      try {
        final text = await driver.subtitleText();
        kernelLine = {
          'text': text ?? '',
          'positionMs': positionMs,
          'source': 'kernel_drawn_now',
          ...driver.tracks.subtitle.toJson(),
        };
      } on KernelFenced {
        kernelLine = null;
      }
    }
    final cursor = input['cursor'] as int? ?? 0;
    final limit = input['limit'] as int? ?? 100;
    final items = <JsonMap>[];
    int total = 0;
    int? nextCursor;
    if (path != null) {
      final index = path == _overlayPath && _overlayIndex != null
          ? _overlayIndex!
          : await cues.get(path);
      final file = fileOf(path);
      final page = PlayerPerf.span(
          'subtitle.cues',
          () => index.page(
                positionMs: positionMs,
                delayMs: delayMs,
                context: input['context'] as int? ?? 2,
                startMs: input['startMs'] as int?,
                endMs: input['endMs'] as int?,
                cursor: cursor,
                limit: limit,
              ));
      for (final c in page.items) {
        items.add({
          'id': '$path:${c.index}',
          'path': redactHarnessText(path),
          'startMs': c.startMs,
          'endMs': c.endMs,
          'text': c.text,
          'trackId': null,
          'language': null,
          'source': file?.origin,
          'current': c.current,
          'renderer': renderer!.name,
        });
      }
      total = page.total;
      nextCursor = page.nextCursor;
    }
    return {
      'positionMs': positionMs,
      'unsupported': unsupported,
      if (kernelLine != null) 'kernelLine': kernelLine,
      'delayMs': delayMs,
      'items': items,
      'nextCursor': nextCursor,
      'total': total,
    };
  }

  // ---- facts ----

  final _notes = <JsonMap>[];
  void _note(String kind, JsonMap data) {
    _notes.add({'at': DateTime.now().toUtc().toIso8601String(), 'kind': kind, ...data});
    if (_notes.length > 12) _notes.removeAt(0);
  }

  JsonMap facts() {
    final s = _state.value;
    final presented = s.presented;
    return {
      'selected': s.want.toJson(),
      'selectedBy': s.selectedBy,
      'selectedAt': s.selectedAt?.toIso8601String(),
      'presented': [for (final p in presented) p.toJson()],
      // The invariant: what shows is the one chosen, and only it.
      'presentedIsSelected': presentedIsSelected,
      'settling': _inFlight > 0,
      'failure': s.failure,
      'files': [for (final f in s.files) f.toJson()],
      if (_overlayIndex case final index?)
        'overlay': {
          'path': redactHarnessText(index.path),
          'format': index.format,
          'encoding': index.encoding,
          'cues': index.length,
          'parseUs': index.parseUs,
          'placement': _placement.toJson(),
          'line': _overlay.value?.text,
        },
      'look': _look.toJson(),
      'notes': List.of(_notes),
    };
  }

  /// Nothing shows but what is chosen: nothing when off, and never two.
  bool get presentedIsSelected {
    final s = _state.value;
    final presented = s.presented;
    if (presented.length > 1) return false;
    if (presented.isEmpty) return true;
    return presented.single.want == s.want;
  }
}
