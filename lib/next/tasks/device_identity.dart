import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// The root is <AppStorage>/next. Identity is independent of endpoint tokens.
Future<String> loadDeviceIdentity(Directory root) async {
  await root.create(recursive: true);
  final file = File('${root.path}/device.json');
  if (await file.exists()) {
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final id = json['deviceId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid deviceId.');
    }
    return id;
  }
  final random = Random.secure();
  final id =
      'device-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  final pending = File('${file.path}.tmp');
  await pending.writeAsString(jsonEncode({'deviceId': id}), flush: true);
  await pending.rename(file.path);
  return id;
}
