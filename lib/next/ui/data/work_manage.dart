import '../../ui_data/ui_data.dart';

/// Managing a work and its episodes from the detail page: what it is
/// (its match, or a catalogue of its own), its words and pictures, which
/// file is which episode, and each episode's danmaku, subtitles and files.
/// Every change goes through the same Actions the agent uses
/// (`Invocation(origin: 'gui')`); nothing here decides for NipaPlay.
///
/// Methods throw when NipaPlay refuses; the sheet says so in a word.
abstract interface class NextWorkManage {
  /// What the work sheet shows of [work], read fresh.
  Future<UiManagedWork> work(UiWork work);

  // —— 匹配 ——

  /// Works [provider] knows by [query] (`media.metadata.search`).
  Future<List<UiMatchCandidate>> search(UiProvider provider, String query);

  /// The episodes of [candidate], to say which file is which
  /// (`media.metadata.get`).
  Future<List<UiCandidateEpisode>> candidateEpisodes(
      UiMatchCandidate candidate);

  /// Matches [work] to [candidate]: each file in [files] to its episode
  /// (`media.identity.unbind_batch` where a file was another episode, then
  /// `media.identity.bind_batch`).
  Future<void> match(UiManagedWork work, UiMatchCandidate candidate,
      Map<UiFile, UiCandidateEpisode> files);

  /// Lets go of the work's match (`media.identity.unbind_batch`).
  Future<void> unmatch(UiManagedWork work);

  // —— 本地作品 ——

  /// A work of its own for what has no match (home videos, extras, a
  /// collection): one episode per file, in order
  /// (`media.entities.put_batch`). Returns the new work's ID.
  Future<String> createLocal(UiManagedWork from, String title);

  /// Saves a local work's episodes as edited: numbers, seasons, titles and
  /// which files they hold (`media.entities.put_batch`, previewed first).
  Future<void> saveLocal(UiManagedWork work, List<UiLocalEpisodeEdit> edits);

  /// Adds the file at [path] to a local work as a new episode
  /// (`media.identity.get` registers it, then `media.entities.put_batch`).
  Future<void> addFile(UiManagedWork work, String path);

  /// Takes a local work, or one of its episodes, out of the catalogue;
  /// files and progress stay (`media.entities.remove_batch`).
  Future<UiUndo> removeLocal(UiManagedWork work, {UiManagedEpisode? episode});

  /// Puts back what [undo] took away (`media.entities.restore`).
  Future<void> restore(UiUndo undo);

  // —— 资料与图片 ——

  /// Sets the work's own words, all at once (`media.metadata.override_batch`).
  /// A null value says it has none.
  Future<void> editText(UiManagedWork work, Map<UiTextField, String?> values);

  /// Titles of several episodes in one go (`media.metadata.override_batch`).
  Future<void> editEpisodeTitles(Map<UiManagedEpisode, String?> titles);

  /// Back to what the sources say (`media.metadata.override`, `clear`).
  Future<void> clearText(UiManagedWork work, UiTextField field);

  /// A picture from a local file (`media.artwork.set`).
  Future<void> setArt(UiManagedWork work, UiArtKind kind, String file);

  /// Back to the sources' picture (`media.artwork.clear`).
  Future<void> clearArt(UiManagedWork work, UiArtKind kind);

  /// Reads the match's sources again (`media.metadata.refresh_batch`).
  Future<void> refresh(UiManagedWork work);

  // —— 剧集 ——

  /// What the episode sheet shows of [episode], read fresh.
  Future<UiManagedEpisode> episode(UiWork work, UiEpisode episode);

  /// A track on or off, or moved in time (`danmaku.update`).
  Future<void> setDanmaku(UiDanmakuTrack track,
      {bool? enabled, Duration? offset});

  /// Comments found by [query] (`danmaku.search`).
  Future<List<UiDanmakuCandidate>> searchDanmaku(String query);

  /// Adds the found comments to [episode] (`danmaku.attach`); they arrive
  /// in the background.
  Future<void> addDanmaku(UiManagedEpisode episode, UiDanmakuCandidate found);

  /// A danmaku file from disk (`danmaku.import`).
  Future<void> importDanmaku(UiManagedEpisode episode, String path);

  /// Takes a track away from the episode (`danmaku.detach`).
  Future<void> removeDanmaku(UiDanmakuTrack track);

  /// The subtitle shown by default; null turns subtitles off
  /// (`subtitle.select`).
  Future<void> selectSubtitle(UiSubtitles file, String? trackId);

  /// Back to choosing on its own (`subtitle.reset_selection`).
  Future<void> automaticSubtitle(UiSubtitles file);

  /// A subtitle file from disk (`subtitle.import`).
  Future<void> importSubtitle(UiSubtitles file, String path);

  /// Language or title of an imported subtitle (`subtitle.update`).
  Future<void> editSubtitle(UiSubtitles file, UiSubtitleTrack track,
      {String? language, String? title});

  /// Lets go of an imported subtitle; its copy stays until deleted
  /// (`subtitle.remove`).
  Future<void> detachSubtitle(UiSubtitles file, UiSubtitleTrack track);

  /// Deleting the copies of subtitles let go of: NipaPlay asks first
  /// (`subtitle.copy_delete`).
  Future<UiConfirm> deleteSubtitleCopies(UiSubtitles file);

  /// Shows the file in Finder.
  Future<void> reveal(UiFile file);

  /// Deleting a file from disk: NipaPlay asks first
  /// (`media.mesh_files.delete`).
  Future<UiConfirm> deleteFile(UiFile file);

  /// A file chosen by the viewer, of [kinds] (extensions).
  Future<String?> pickFile(List<String> kinds);
}

enum UiProvider {
  dandanplay('弹弹play'),
  tmdb('TMDB'),
  bangumi('Bangumi');

  const UiProvider(this.label);
  final String label;
}

enum UiTextField { title, originalTitle, overview }

enum UiArtKind { backdrop, poster, logo }

/// What a work is to NipaPlay: matched to a work some provider knows, a
/// catalogue of its own, a work whose match was let go, or only files
/// nobody has said anything about yet.
enum UiWorkKind { matched, local, loose, files }

final class UiManagedWork {
  const UiManagedWork({
    required this.work,
    required this.kind,
    this.match,
    this.text = const {},
    this.art = const {},
    this.episodes = const [],
    this.editable = true,
    this.elsewhere,
    this.handle,
  });

  final UiWork work;
  final UiWorkKind kind;
  final UiMatch? match;
  final Map<UiTextField, UiText> text;
  final Map<UiArtKind, UiArt> art;

  /// The episodes NipaPlay has a file for on this device, in order.
  final List<UiManagedEpisode> episodes;

  /// False when nothing of it is on this device: it is changed where it
  /// is ([elsewhere]).
  final bool editable;
  final String? elsewhere;

  /// What the data layer needs to find it again; never shown.
  final Object? handle;

  List<UiFile> get files => [for (final e in episodes) ...e.files];
}

final class UiMatch {
  const UiMatch(
      {required this.provider,
      required this.title,
      required this.candidate,
      this.year,
      this.image});
  final UiProvider provider;
  final String title;
  final int? year;
  final String? image;

  /// The match as a search would find it, for its episodes.
  final UiMatchCandidate candidate;
}

final class UiText {
  const UiText(this.value, {this.edited = false});
  final String? value;

  /// The viewer's (or Nipa's) own words over the sources'.
  final bool edited;
}

final class UiArt {
  const UiArt(this.path, {this.edited = false});
  final String? path;
  final bool edited;
}

final class UiMatchCandidate {
  const UiMatchCandidate({
    required this.provider,
    required this.title,
    required this.ref,
    this.originalTitle,
    this.year,
    this.image,
    this.movie = false,
    this.current = false,
    this.elsewhere = false,
  });
  final UiProvider provider;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? image;
  final bool movie;

  /// The work's match now.
  final bool current;

  /// Another work of the library has this match already.
  final bool elsewhere;

  /// The provider's reference, handed back as it came; never shown.
  final Map<String, Object?> ref;
}

final class UiCandidateEpisode {
  const UiCandidateEpisode(
      {required this.number, required this.ref, this.season, this.title, this.release});
  final int? season;
  final String number;
  final String? title;
  final Map<String, Object?> ref;

  /// The season's reference where the provider has seasons.
  final Map<String, Object?>? release;

  String get label =>
      [if (int.tryParse(number) != null) '第 $number 集' else number, if (title != null && title!.isNotEmpty) title!].join('  ');
}

final class UiManagedEpisode {
  const UiManagedEpisode({
    required this.number,
    this.episode,
    this.season,
    this.title,
    this.titleEdited = false,
    this.files = const [],
    this.danmaku = const [],
    this.subtitles = const [],
    this.handle,
  });

  /// As the interface shows it, where it has one.
  final UiEpisode? episode;
  final String number;
  final int? season;
  final String? title;
  final bool titleEdited;
  final List<UiFile> files;
  final List<UiDanmakuTrack> danmaku;

  /// Per file.
  final List<UiSubtitles> subtitles;
  final Object? handle;

  String get label =>
      int.tryParse(number) != null ? '第 $number 集' : number;
}

/// A local work's episode as edited in its sheet: [handle] null for a new
/// one.
final class UiLocalEpisodeEdit {
  const UiLocalEpisodeEdit(
      {required this.number,
      this.season,
      this.title,
      this.files = const [],
      this.handle});
  final String number;
  final int? season;
  final String? title;
  final List<UiFile> files;
  final Object? handle;
}

final class UiFile {
  const UiFile({
    required this.path,
    this.size,
    this.duration,
    this.modified,
    this.handle,
  });
  final String path;
  final int? size;
  final Duration? duration;
  final DateTime? modified;
  final Object? handle;

  String get name => path.split(RegExp(r'[\\/]')).last;
  String get folder {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }

  @override
  bool operator ==(Object other) => other is UiFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class UiDanmakuTrack {
  const UiDanmakuTrack({
    required this.source,
    this.name,
    this.count,
    this.enabled = true,
    this.offset = Duration.zero,
    this.loading = false,
    this.removable = true,
    this.handle,
  });

  /// Where the comments are from, as viewers name it: 弹弹play, 本地文件.
  final String source;
  final String? name;
  final int? count;
  final bool enabled;

  /// Positive: the comments come earlier.
  final Duration offset;

  /// Still being fetched.
  final bool loading;
  final bool removable;
  final Object? handle;
}

final class UiDanmakuCandidate {
  const UiDanmakuCandidate(
      {required this.title, required this.source, this.handle});
  final String title;
  final String source;
  final Object? handle;
}

enum UiSubtitleKind { embedded, external, imported }

final class UiSubtitleTrack {
  const UiSubtitleTrack({
    required this.id,
    required this.kind,
    this.language,
    this.title,
    this.format,
    this.available = true,
  });
  final String id;
  final UiSubtitleKind kind;

  /// BCP-47; null or `und` when unknown.
  final String? language;
  final String? title;
  final String? format;
  final bool available;

  bool get editable => kind == UiSubtitleKind.imported;
}

/// One file's subtitles: the tracks, the one shown by default, and copies
/// of let-go subtitles still on disk.
final class UiSubtitles {
  const UiSubtitles({
    required this.file,
    this.tracks = const [],
    this.selected,
    this.explicit = false,
    this.detached = const [],
    this.handle,
  });
  final UiFile file;
  final List<UiSubtitleTrack> tracks;

  /// The track shown by default; null with [explicit] means off.
  final String? selected;

  /// The viewer chose (or turned them off); otherwise NipaPlay chooses.
  final bool explicit;
  final List<String> detached;
  final Object? handle;
}

/// Something NipaPlay only does once the viewer says so: what it touches,
/// and doing it.
final class UiConfirm {
  const UiConfirm({required this.items, required this.run});

  /// As the viewer knows them: file names.
  final List<String> items;
  final Future<void> Function() run;
}

/// The way back from a removal.
final class UiUndo {
  const UiUndo(this.handle);
  final Object handle;
}

/// Thrown when NipaPlay refuses; [conflict] when something changed in
/// between (read again and retry).
final class UiManageError implements Exception {
  const UiManageError({this.conflict = false, this.message});
  final bool conflict;
  final String? message;

  @override
  String toString() => 'UiManageError(${conflict ? 'conflict' : message})';
}

/// The languages a subtitle is said to be in, as the sheet offers them.
const uiSubtitleLanguages = <(String, String)>[
  ('zh-Hans', '简体中文'),
  ('zh-Hant', '繁体中文'),
  ('ja', '日语'),
  ('en', '英语'),
  ('ko', '韩语'),
  ('und', '未知'),
];

String uiLanguageName(String? code) {
  if (code == null || code == 'und' || code.isEmpty) return '未知语言';
  for (final (c, name) in uiSubtitleLanguages) {
    if (c == code) return name;
  }
  final lower = code.toLowerCase();
  if (lower.startsWith('zh')) {
    return lower.contains('hant') ||
            lower.contains('tw') ||
            lower.contains('hk')
        ? '繁体中文'
        : '中文';
  }
  if (lower.startsWith('ja') || lower == 'jpn') return '日语';
  if (lower.startsWith('en') || lower == 'eng') return '英语';
  if (lower.startsWith('ko') || lower == 'kor') return '韩语';
  return code;
}
