import 'dart:io';

class FolderOpener {
  static Future<bool> open(String folderPath) async {
    final trimmed = folderPath.trim();
    if (trimmed.isEmpty) return false;

    try {
      if (Platform.isMacOS) {
        final result = await Process.run('open', [trimmed]);
        return result.exitCode == 0;
      }
      if (Platform.isWindows) {
        final result = await Process.run(
          'explorer',
          [trimmed],
          runInShell: true,
        );
        return result.exitCode == 0;
      }
      if (Platform.isLinux) {
        final result = await Process.run('xdg-open', [trimmed]);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }

    return false;
  }
}
