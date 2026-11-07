import 'dart:ffi';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart' as sqlite_open;

import '../utils/platform_identity.dart' as platform;

/// Packaged with the HarmonyOS app: the system RDB API cannot be called from
/// the library worker isolate, and sqlite3 has no default loader for OHOS.
const harmonySqliteName = 'libnipaplay_sqlite3.so';

/// The names the SQLite shared library has on Linux. The sqlite3 package
/// opens `libsqlite3.so`, which exists only where the development package is
/// installed; a server that has just the runtime package (`libsqlite3-0`,
/// `sqlite-libs`) has `libsqlite3.so.0` alone.
const linuxSqliteNames = ['libsqlite3.so', 'libsqlite3.so.0'];

/// The first of [names] that [load] can open, or null when none opens.
String? firstLoadableLibrary(
    List<String> names, DynamicLibrary Function(String name) load) {
  for (final name in names) {
    try {
      load(name);
      return name;
    } on ArgumentError {
      continue;
    } on UnsupportedError {
      continue;
    }
  }
  return null;
}

/// Makes this isolate's SQLite loader work on a Linux host that has only the
/// runtime library. Call it in every isolate that opens a database (it is the
/// `ffiInit` of the sqflite factory and of the library worker). On other
/// systems, and where `libsqlite3.so` opens, it does nothing. HarmonyOS uses
/// the app's bundled SQLite in every isolate, including the main DB factory.
void ensureSqliteLibrary(
    {bool? linux,
    bool? harmonyOS,
    DynamicLibrary Function(String name)? load,
    void Function(DynamicLibrary Function() open)? override}) {
  final loader = load ?? DynamicLibrary.open;
  if (harmonyOS ?? platform.isHarmonyOS) {
    (override ?? sqlite_open.open.overrideForAll)(
        () => loader(harmonySqliteName));
    return;
  }
  if (!(linux ?? Platform.isLinux)) return;
  final name = firstLoadableLibrary(linuxSqliteNames, loader);
  if (name == null || name == linuxSqliteNames.first) return;
  (override ??
      (open) => sqlite_open.open
          .overrideFor(sqlite_open.OperatingSystem.linux, open))(() => loader(name));
}
