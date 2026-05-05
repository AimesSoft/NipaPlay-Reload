import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/src/rust/api/torrent.dart' as rust_torrent;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';

class TorrentDownloadService {
  TorrentDownloadService._();

  static final TorrentDownloadService instance = TorrentDownloadService._();

  bool _sessionInitialized = false;
  String _sessionDownloadDir = '';

  Future<String> getDownloadDirectory() async {
    final saved = await SettingsStorage.loadString(
      SettingsKeys.torrentDownloadDirectory,
    );
    if (saved.trim().isNotEmpty) {
      return saved.trim();
    }
    final defaultDir = await StorageService.getDownloadsDirectory();
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      defaultDir.path,
    );
    return defaultDir.path;
  }

  Future<void> setDownloadDirectory(String directory) async {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) return;
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      trimmed,
    );
    _sessionDownloadDir = trimmed;
  }

  Future<void> initialize() async {
    await _initSession(await getDownloadDirectory());
  }

  Future<List<TorrentTask>> listTasks() async {
    final downloadDir = await getDownloadDirectory();
    await _initSession(downloadDir);
    final jsonText = await rust_torrent.torrentList(downloadDir: downloadDir);
    return TorrentTask.listFromJson(jsonText);
  }

  Future<void> addMagnet(String magnetUri) async {
    final downloadDir = await getDownloadDirectory();
    final createFolder = await _createFolderForTask();
    await _initSession(downloadDir);
    await rust_torrent.torrentAddMagnet(
      magnetUri: magnetUri,
      downloadDir: downloadDir,
      createFolderForTask: createFolder,
    );
  }

  Future<void> addTorrentFile(String torrentFilePath) async {
    final downloadDir = await getDownloadDirectory();
    final createFolder = await _createFolderForTask();
    await _initSession(downloadDir);
    await rust_torrent.torrentAddFile(
      torrentFilePath: torrentFilePath,
      downloadDir: downloadDir,
      createFolderForTask: createFolder,
    );
  }

  Future<void> pause(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentPause(id: id);
  }

  Future<void> resume(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentResume(id: id);
  }

  Future<void> forget(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentForget(id: id);
  }

  Future<void> delete(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentDelete(id: id);
  }

  Future<void> _initSession(String downloadDir) async {
    if (_sessionInitialized && _sessionDownloadDir == downloadDir) return;
    await ensureRustInitialized();
    await rust_torrent.torrentInitSession(downloadDir: downloadDir);
    _sessionInitialized = true;
    _sessionDownloadDir = downloadDir;
  }

  Future<bool> _createFolderForTask() {
    return SettingsStorage.loadBool(
      SettingsKeys.downloaderCreateFolderForTask,
      defaultValue: true,
    );
  }
}
