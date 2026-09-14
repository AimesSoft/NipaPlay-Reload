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

  Future<String> printAnimeEpisodeRelations({
    required Map<int, String> dandanplayAnimeTitles,
    required Map<int, String> bangumiAnimeTitles,
    required Map<int, String> dandanplayEpisodeTitles,
    required Map<int, String> bangumiEpisodeTitles,
  }) async {
      final animeSources = <int, ({Set<int> dandanplay, Set<int> bangumi})>{};
      final episodeSources = <int, ({Set<int> dandanplay, Set<int> bangumi})>{};
      final episodeAnimeIds = <int, int>{};

      final animeRows = await database.query(
        'anime',
        columns: const <String>['anime_id'],
        orderBy: 'anime_id',
      );
      for (final row in animeRows) {
        animeSources[_int(row, 'anime_id')] = (
          dandanplay: <int>{},
          bangumi: <int>{},
        );
      }

      await _collectSources(
        table: 'dandanplay_anime',
        commonIdColumn: 'anime_id',
        sourceIdColumn: 'dandanplay_anime_id',
        target: animeSources,
        selectSet: (sources) => sources.dandanplay,
      );
      await _collectSources(
        table: 'bangumi_anime',
        commonIdColumn: 'anime_id',
        sourceIdColumn: 'bangumi_anime_id',
        target: animeSources,
        selectSet: (sources) => sources.bangumi,
      );

      final episodeRows = await database.query(
        'episode',
        columns: const <String>['episode_id', 'anime_id'],
        orderBy: 'anime_id, episode_id',
      );
      for (final row in episodeRows) {
        final episodeId = _int(row, 'episode_id');
        episodeAnimeIds[episodeId] = _int(row, 'anime_id');
        episodeSources[episodeId] = (
          dandanplay: <int>{},
          bangumi: <int>{},
        );
      }

      await _collectSources(
        table: 'dandanplay_episode',
        commonIdColumn: 'episode_id',
        sourceIdColumn: 'dandanplay_episode_id',
        target: episodeSources,
        selectSet: (sources) => sources.dandanplay,
      );
      await _collectSources(
        table: 'bangumi_episode',
        commonIdColumn: 'episode_id',
        sourceIdColumn: 'bangumi_episode_id',
        target: episodeSources,
        selectSet: (sources) => sources.bangumi,
      );
      final buffer = StringBuffer('=== Anime / Episode 关联关系 ===\n');
      if (animeSources.isEmpty) {
        buffer.writeln('<empty>');
      } else {
        final animeIds = animeSources.keys.toList()..sort();
        for (final animeId in animeIds) {
          final sources = animeSources[animeId]!;
          buffer.writeln('[Anime common=$animeId]');
          buffer.writeln(
            '  Dandanplay: '
            '${_formatIds(sources.dandanplay, dandanplayAnimeTitles)}',
          );
          buffer.writeln(
            '  Bangumi:    '
            '${_formatIds(sources.bangumi, bangumiAnimeTitles)}',
          );
          buffer.writeln('  Episodes:');

          final episodeIds = episodeAnimeIds.entries
              .where((entry) => entry.value == animeId)
              .map((entry) => entry.key)
              .toList()
            ..sort();
          if (episodeIds.isEmpty) {
            buffer.writeln('    <empty>');
          } else {
            for (final episodeId in episodeIds) {
              final episode = episodeSources[episodeId]!;
              buffer.writeln(
                '    common=$episodeId'
                ' | Dandanplay='
                '${_formatIds(episode.dandanplay, dandanplayEpisodeTitles)}'
                ' | Bangumi='
                '${_formatIds(episode.bangumi, bangumiEpisodeTitles)}',
              );
          }
        }
      }
    }

      final linkedAnimeCount = animeSources.values
          .where(
            (sources) =>
                sources.dandanplay.isNotEmpty && sources.bangumi.isNotEmpty,
          )
          .length;
      final linkedEpisodeCount = episodeSources.values
          .where(
            (sources) =>
                sources.dandanplay.isNotEmpty && sources.bangumi.isNotEmpty,
          )
          .length;
      buffer
        ..writeln('=== 汇总 ===')
        ..writeln(
          'Anime: total=${animeSources.length}, cross-source=$linkedAnimeCount',
        )
        ..write(
          'Episode: total=${episodeSources.length}, '
          'cross-source=$linkedEpisodeCount',
        );

      final report = buffer.toString();
      debugPrint(report);
      return report;
    }

    Future<void> _collectSources({
      required String table,
      required String commonIdColumn,
      required String sourceIdColumn,
      required Map<int, ({Set<int> dandanplay, Set<int> bangumi})> target,
      required Set<int> Function(
        ({Set<int> dandanplay, Set<int> bangumi}) sources,
      ) selectSet,
    }) async {
      final rows = await database.query(
        table,
        columns: <String>[commonIdColumn, sourceIdColumn],
        orderBy: '$commonIdColumn, $sourceIdColumn',
      );
      for (final row in rows) {
        final commonId = _int(row, commonIdColumn);
        final sources = target.putIfAbsent(
          commonId,
          () => (dandanplay: <int>{}, bangumi: <int>{}),
        );
        selectSet(sources).add(_int(row, sourceIdColumn));
    }
  }

    static int _int(Map<String, Object?> row, String column) {
      return (row[column] as num).toInt();
    }

  static String _formatIds(Set<int> ids, Map<int, String> titles) {
      if (ids.isEmpty) return '-';
      final sorted = ids.toList()..sort();
    return sorted
        .map((id) => '$id "${titles[id] ?? '<unknown>'}"')
        .join(', ');
  }

}
