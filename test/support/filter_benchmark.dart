import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/playback/documents.dart';

class _NoDocuments extends DocumentAccess {
  _NoDocuments() : super(android: false);
  @override
  Future<List<String>> roots() async => [];
}

/// Runs the production filter/controller over an isolated synthetic database.
/// Expected membership uses integer predicates, independent of FilterRule.
Future<Map<String, Object?>> runFilterBenchmark() async {
  final directory = await Directory.systemTemp.createTemp('tag-music-r4-');
  final db = LibraryDatabase(
    NativeDatabase.createInBackground(File('${directory.path}/filters.sqlite')),
  );
  final library = LibraryController(db, _NoDocuments());
  try {
    await db.transaction(() async {
      await db.customStatement(
        "INSERT INTO library_roots(location) VALUES ('synthetic')",
      );
      await db.customStatement('''
        WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM numbers WHERE n < 9999)
        INSERT INTO songs(id,identity,location,name,title,artist,album)
        SELECT CAST(n AS TEXT), CAST(n AS TEXT), '/synthetic/' || n,
               '歌曲' || n, '标题' || n, '歌手' || (n % 20), '专辑' || (n % 100) FROM numbers
      ''');
      await db.customStatement(
        "INSERT INTO song_locations(song_id,root,location,relative_path) SELECT id,'synthetic',location,name FROM songs",
      );
      for (var bit = 0; bit < 8; bit++) {
        await db.customStatement(
          'INSERT INTO tags(id,name,name_key) VALUES (?,?,?)',
          ['t$bit', '标签$bit', '标签$bit'],
        );
        await db.customStatement(
          'INSERT INTO song_tags(song_id,tag_id) SELECT id,? FROM songs WHERE (CAST(id AS INT) & ?) != 0',
          ['t$bit', 1 << bit],
        );
      }
    });
    final load = Stopwatch()..start();
    await library.initialize();
    load.stop();
    final scenarios = <(String, FilterRule, bool Function(int))>[
      ('empty', FilterRule(), (_) => true),
      ('all', FilterRule(allTagIds: ['t0', 't1']), (n) => n & 3 == 3),
      ('any', FilterRule(anyTagIds: ['t2', 't3']), (n) => n & 12 != 0),
      (
        'combined',
        FilterRule(
          allTagIds: ['t0', 't1'],
          anyTagIds: ['t2', 't3'],
          excludedTagIds: ['t4', 't5'],
        ),
        (n) => (n & 3 == 3 || n & 12 != 0) && n & 48 == 0,
      ),
      ('excludeOnly', FilterRule(excludedTagIds: ['t7']), (n) => n & 128 == 0),
      (
        'crossBoxZero',
        FilterRule(
          allTagIds: ['t0'],
          anyTagIds: ['t0'],
          excludedTagIds: ['t0'],
        ),
        (_) => false,
      ),
    ];
    final reports = <Map<String, Object?>>[];
    for (final (name, rule, predicate) in scenarios) {
      final expected = {
        for (var n = 0; n < 10000; n++)
          if (predicate(n)) '$n',
      };
      final samples = <int>[];
      for (var run = 0; run < 25; run++) {
        // A rule update always invalidates both result caches; never time hits.
        final timer = Stopwatch()..start();
        final saving = library.updateFilter(
          rule: rule,
          order: LibrarySort.values[run % 4],
          reverse: run.isEven,
        );
        library.searchFilter(run.isEven ? '歌曲' : '歌手');
        final rows = library.filtered;
        timer.stop();
        await saving;
        final actual = rows.map((t) => t.song.id).toSet();
        if (actual.length != expected.length || !actual.containsAll(expected)) {
          throw StateError(
            '$name result differs from independent integer oracle',
          );
        }
        if (run >= 5) samples.add(timer.elapsedMicroseconds);
      }
      final ordered = [...samples]..sort();
      reports.add({
        'scenario': name,
        'rule': rule.encode(),
        'resultCount': expected.length,
        'samplesMicroseconds': samples,
        'warmFilterSearchSortP95Microseconds':
            ordered[(ordered.length * .95).ceil() - 1],
      });
    }
    return {
      'platform': Platform.operatingSystem,
      'mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'database': 'isolated temporary SQLite, background executor',
      'syntheticDatabaseSongs': 10000,
      'tags': 8,
      'realFilesScanned': 0,
      'initialDataLoadMicroseconds': load.elapsedMicroseconds,
      'measurement': 'cache invalidation, production rule evaluation, result search and sort; awaited persistence and widget rendering excluded',
      'warmupRunsPerScenario': 5,
      'samplesPerScenario': 20,
      'scenarios': reports,
    };
  } finally {
    await library.shutdown();
    await directory.delete(recursive: true);
  }
}
