part of 'database_service.dart';

class _DatabaseDebugPrinter {
  const _DatabaseDebugPrinter(this.database);

  final Database database;

  static const tables = <String>[
    'anime',
    'episode',
    'dandanplay_anime',
    'dandanplay_episode',
    'bangumi_anime',
    'bangumi_episode',
    'asset_episode',
    'episode_watch_status',
  ];

  Future<void> printTables() async {
    for (final table in tables) {
      final rows = await database.query(table, orderBy: 'rowid');
      debugPrint('[$table] rows=${rows.length}');
      if (rows.isEmpty) {
        debugPrint('  <empty>');
      } else {
        for (var index = 0; index < rows.length; index++) {
          debugPrint('  [$index] ${rows[index]}');
        }
      }
    }
  }
}
