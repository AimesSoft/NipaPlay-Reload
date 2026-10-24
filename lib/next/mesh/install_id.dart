import 'dart:io';
import 'dart:math';

/// A random number that names this installation's Mesh key in the vault. A
/// path names it badly on a device whose application container moves (an
/// iPad restored from a backup, an update that gets a new container).
Future<String> meshInstallId(Directory root) async {
  await root.create(recursive: true);
  final file = File('${root.path}/mesh-install-id');
  if (await file.exists()) {
    final saved = (await file.readAsString()).trim();
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(saved)) return saved;
  }
  final random = Random.secure();
  final id = [
    for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')
  ].join();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(id, flush: true);
  await tmp.rename(file.path);
  return id;
}
