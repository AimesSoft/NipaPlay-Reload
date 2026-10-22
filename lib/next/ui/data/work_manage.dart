import '../../ui_data/ui_data.dart';

/// Managing a work and its episodes from the detail page: what it is
/// (its match, or a catalogue of its own), its words and pictures, which
/// file is which episode, and each episode's danmaku, subtitles and files.
/// Every change goes through the same Actions the agent uses
/// (`Invocation(origin: 'gui')`), on the device that has it
/// (`media.management.targets`, then `mesh.invoke` for another one);
/// nothing here decides for NipaPlay.
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

  /// What matching [work] to [candidate] would touch, each file in
  /// [files] to its episode, on every device that has one; applying it
  /// lets go of what a file was first (`media.management.unbind_batch`,
  /// then `media.management.bind_batch`, previewed, then with the plan).
  Future<UiAssociation> previewMatch(UiManagedWork work,
      UiMatchCandidate candidate, Map<UiFile, UiCandidateEpisode> files);

  /// What letting go of the work's match would touch, on every device
  /// that has it (`media.management.unbind_batch`, previewed, then with
  /// the plan).
  Future<UiAssociation> previewUnmatch(UiManagedWork work);

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

  /// An episode's title back to what the sources say
  /// (`media.metadata.override_batch`, `clear`).
  Future<void> clearEpisodeTitle(UiManagedEpisode episode);

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

  /// Shows the file in the file manager of the device it is on
  /// (`media.files.reveal`).
  Future<void> reveal(UiFile file);

  /// Deleting a file from the disk it is on: NipaPlay asks first
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
    this.device,
    this.away = const [],
    this.unavailable,
    this.handle,
  });

  final UiWork work;
  final UiWorkKind kind;
  final UiMatch? match;
  final Map<UiTextField, UiText> text;
  final Map<UiArtKind, UiArt> art;

  /// The episodes with a file on a device that answers now, in order.
  final List<UiManagedEpisode> episodes;

  /// The device it is changed on when it is not on this one.
  final String? device;

  /// Devices with part of it that cannot be asked now, as said:
  /// “旧笔记本不在线”.
  final List<String> away;

  /// Why nothing of it can be changed now, as said; null when it can.
  final String? unavailable;

  /// What the data layer needs to find it again; never shown.
  final Object? handle;

  bool get editable => unavailable == null;

  /// On this device: files picked here (pictures, a work's own files)
  /// can be given to it.
  bool get here => device == null;

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
      {required this.number,
      required this.ref,
      this.season,
      this.title,
      this.release,
      this.movie = false});

  /// A film's one: the film itself ([ref] is the film's), with no release.
  const UiCandidateEpisode.film(Map<String, Object?> ref)
      : this(number: '', ref: ref, movie: true);

  final int? season;
  final String number;
  final String? title;
  final Map<String, Object?> ref;

  /// The season's reference where the provider has seasons.
  final Map<String, Object?>? release;

  /// The film itself: 正片.
  final bool movie;

  String get label => movie
      ? '正片'
      : [if (int.tryParse(number) != null) '第 $number 集' else number, if (title != null && title!.isNotEmpty) title!].join('  ');
}

final class UiManagedEpisode {
  const UiManagedEpisode({
    required this.number,
    this.episode,
    this.season,
    this.title,
    this.titleEdited = false,
    this.files = const [],
    this.locations = const [],
    this.device,
    this.away = const [],
    this.unavailable,
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

  /// Its files, each once: what is matched, and whose subtitles are kept.
  final List<UiFile> files;

  /// Every place a file of it is, on every device that answers now.
  final List<UiFile> locations;

  /// The device its danmaku and subtitles are changed on when it is not
  /// on this one.
  final String? device;

  /// Devices with a file of it that cannot be asked now, as said.
  final List<String> away;

  /// Why nothing of it can be changed now, as said; null when it can.
  final String? unavailable;
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
    this.device,
    this.manager,
    this.handle,
  });

  /// A place as `media.files.list` lists it.
  factory UiFile.listed(Map<String, Object?> row,
      {String? device, UiFileManager? manager, Object? handle}) {
    final ms = row['durationMs'] as int?;
    final modified = row['modifiedAt'] as String?;
    return UiFile(
      path: row['path'] as String,
      size: row['size'] as int?,
      duration: ms == null || ms <= 0 ? null : Duration(milliseconds: ms),
      modified: modified == null ? null : DateTime.tryParse(modified),
      device: device,
      manager: manager,
      handle: handle,
    );
  }

  /// As its device knows it.
  final String path;
  final int? size;
  final Duration? duration;
  final DateTime? modified;

  /// The device it is on, by the name its host gave it; null for this one.
  final String? device;

  /// How that device shows a file; null when it has no file manager.
  final UiFileManager? manager;
  final Object? handle;

  String get name => path.split(RegExp(r'[\\/]')).last;
  String get folder {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }

  @override
  bool operator ==(Object other) =>
      other is UiFile && other.path == path && other.device == device;

  @override
  int get hashCode => Object.hash(path, device);
}

/// A device's file manager, as its own words for showing a file.
enum UiFileManager {
  finder('在 Finder 中显示'),
  explorer('在资源管理器中显示'),
  folder('打开所在文件夹');

  const UiFileManager(this.label);
  final String label;

  /// By the device's operating system (`Platform.operatingSystem`).
  static UiFileManager? of(Object? platform) => switch (platform) {
        'macos' => finder,
        'windows' => explorer,
        'linux' => folder,
        _ => null,
      };
}

/// `media.files.reveal`'s answer: refused unless every path was taken.
void uiRevealed(Map<String, Object?> result) {
  for (final r in (result['results'] as List).cast<Map>()) {
    if (r['requested'] != true) {
      throw UiManageError(message: '${(r['error'] as Map?)?['message']}');
    }
  }
}

/// Why a device that has a work cannot be asked now
/// (`media.management.targets`), in a phrase; null when it can.
String? uiAway(Map<String, Object?> target, String? name) {
  if (target['online'] == true) return null;
  final device = uiSpaced(name ?? '另一台设备');
  return target['reason'] == 'source_device_offline'
      ? '$device不在线'
      : '$device现在连不上';
}

/// A device's name as it runs into Chinese: a space after (and with
/// [before], before) Latin letters or digits — “书房的 Mac 不在线”.
String uiSpaced(String name, {bool before = false}) {
  final latin = RegExp(r'[A-Za-z0-9]');
  return '${before && latin.hasMatch(name[0]) ? ' ' : ''}$name'
      '${latin.hasMatch(name[name.length - 1]) ? ' ' : ''}';
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

/// A change of matches as NipaPlay previews it: what it touches, and
/// doing it as previewed. Files, progress and sources' records stay.
final class UiAssociation {
  const UiAssociation({
    this.works = const [],
    this.episodes = 0,
    this.files = 0,
    this.watched = 0,
    this.sources = const [],
    this.devices = const [],
    required this.apply,
  });

  /// What `media.management.bind_batch`/`unbind_batch` previews say,
  /// together (each preview's `preview`).
  factory UiAssociation.fromPreviews(Iterable<Map<String, Object?>> previews,
      {List<String?> devices = const [],
      required Future<void> Function() apply}) {
    final seen = <String>{};
    final works = <String>[];
    final sources = <String>{};
    var episodes = 0, files = 0, watched = 0;
    for (final preview in previews) {
      for (final e in (preview['entities'] as List).cast<Map>()) {
        final entity = e['entity'] as Map;
        if (!seen.add(entity['id'] as String)) continue;
        switch (entity['kind']) {
          case 'work':
            if ((entity['attributes'] as Map)['title'] case final String t) {
              works.add(t);
            }
          case 'episode':
            episodes++;
          case 'file':
            files++;
            if ((e['progress'] as List).cast<Map>().any((p) =>
                (p['watchProgress'] as num? ?? 0) > 0 ||
                (p['lastPosition'] as num? ?? 0) > 0)) {
              watched++;
            }
        }
        for (final s in (e['sources'] as List).cast<Map>()) {
          if (s['status'] != 'accepted') continue;
          for (final p in UiProvider.values) {
            if (p.name == s['provider']) sources.add(p.label);
          }
        }
      }
    }
    return UiAssociation(
      works: works,
      episodes: episodes,
      files: files,
      watched: watched,
      sources: sources.toList(),
      devices: devices,
      apply: apply,
    );
  }

  /// The works it touches, by title.
  final List<String> works;
  final int episodes;
  final int files;

  /// Files with progress; it stays.
  final int watched;

  /// The matches now on what it touches: 弹弹play, TMDB.
  final List<String> sources;

  /// Where it happens: device names, null for this one.
  final List<String?> devices;

  /// Throws [UiManageError] with `conflict` when something changed since
  /// the preview: preview again.
  final Future<void> Function() apply;
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
