import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';

import '../library_test.dart' show FakeDocuments;

/// Raw host/test-VM observations only. No UI or Release latency is inferred.
Future<Map<String, Object?>> runR6LibraryBenchmark() async {
  final directory = await Directory.systemTemp.createTemp('tagmusic-r6-query-');
  final db = LibraryDatabase(
    NativeDatabase(File('${directory.path}/synthetic.sqlite')),
  );
  final library = LibraryController(db, FakeDocuments());
  try {
    await db.customStatement(
      "INSERT INTO library_roots(location) VALUES ('synthetic')",
    );
    await db.customStatement('''
      WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL SELECT n+1 FROM numbers WHERE n<9999)
      INSERT INTO songs(id,identity,location,name,title,artist,album,modified)
      SELECT printf('%05d',n),printf('%05d',n),'/synthetic/'||n,printf('file%05d.flac',n),'歌曲'||n,
        CASE WHEN n%100=0 THEN NULL ELSE '歌手'||(n%100) END,
        CASE WHEN n%100=0 THEN NULL ELSE '专辑'||(n%1000) END,
        CASE WHEN n%100=0 THEN NULL ELSE n%1000 END FROM numbers
    ''');
    await db.customStatement(
      "INSERT INTO song_locations(song_id,root,location,relative_path) SELECT id,'synthetic',location,name FROM songs",
    );
    final load = Stopwatch()..start();
    await library.initialize();
    load.stop();
    final scenes = <Map<String, Object?>>[];
    List<String> oracle(
      LibrarySort order,
      bool reverse, {
      bool search = false,
    }) {
      final numbers = [
        for (var n = 0; n < 10000; n++)
          if (!search || '歌曲$n'.contains('歌曲9')) n,
      ];
      numbers.sort((a, b) {
        int compare;
        if (order == LibrarySort.modified) {
          final unknownA = a % 100 == 0, unknownB = b % 100 == 0;
          if (unknownA != unknownB) return unknownA ? 1 : -1;
          compare = unknownA ? 0 : (a % 1000).compareTo(b % 1000);
          if (compare != 0) return reverse ? -compare : compare;
          return a.compareTo(b);
        }
        final first = order == LibrarySort.title
            ? '歌曲$a'
            : a % 100 == 0
            ? ''
            : '歌手${a % 100}';
        final second = order == LibrarySort.title
            ? '歌曲$b'
            : b % 100 == 0
            ? ''
            : '歌手${b % 100}';
        compare = first.compareTo(second);
        if (compare == 0) compare = a.compareTo(b);
        return reverse ? -compare : compare;
      });
      return numbers.map((n) => n.toString().padLeft(5, '0')).toList();
    }

    void measure(
      String scenario,
      LibrarySort order,
      bool reverse,
      bool cached,
    ) {
      final expected = oracle(order, reverse, search: scenario == 'search');
      final samples = <int>[], memory = <int>[];
      final observations = <Map<String, Object?>>[];
      for (var run = 0; run < 25; run++) {
        List<LibraryTrack> read() => scenario == 'search'
            ? library.searchTracks('歌曲9', order: order, descending: reverse)
            : library.visible;
        if (scenario == 'search') {
          library.tracks = List.of(
            library.tracks,
          ); // new data revision, outside measured call
        } else {
          library.filter(text: '', order: order, reverse: reverse);
        }
        if (cached) read();
        final timer = Stopwatch()..start();
        final result = read();
        timer.stop();
        final rss = ProcessInfo.currentRss;
        final ids = result.map((t) => t.song.id).toList();
        if (!listEquals(ids, expected)) {
          throw StateError(
            '$scenario/$order/$reverse/$cached membership/order mismatch',
          );
        }
        if (run >= 5) {
          samples.add(timer.elapsedMicroseconds);
          memory.add(rss);
          observations.add({
            'run': run - 5,
            'count': ids.length,
            'first': ids.first,
            'last': ids.last,
            'oracleVerified': true,
          });
        }
      }
      scenes.add({
        'scenario': scenario,
        'sort': order.name,
        'descending': reverse,
        'cache': cached ? 'hit' : 'cold',
        'performanceType': 'synthetic-database',
        'unit': 'microseconds',
        'warmupCount': 5,
        'samples': samples,
        'memorySamplesBytes': memory,
        'observations': observations,
      });
    }

    for (final order in [
      LibrarySort.title,
      LibrarySort.artist,
      LibrarySort.modified,
    ]) {
      for (final reverse in [false, true]) {
        for (final cached in [false, true]) {
          measure('sort', order, reverse, cached);
        }
      }
    }
    for (final cached in [false, true]) {
      measure('search', LibrarySort.modified, true, cached);
    }
    return {
      'schemaVersion': 1,
      'round': 'R6',
      'observationContext': 'host flutter test Dart VM; synthetic database, no real files or device UI',
      'platform': Platform.operatingSystem,
      'mode': 'debug',
      'os': Platform.operatingSystemVersion,
      'revision':
          Platform.environment['TAG_MUSIC_R6_REVISION'] ??
          'unidentified-working-tree',
      'syntheticDatabaseSongs': 10000,
      'realFilesScanned': 0,
      'seed': 0,
      'generator': 'R6-order2-v1',
      'initialLoadMicroseconds': load.elapsedMicroseconds,
      'method': 'Production visible/searchTracks call only; data reset/cache prime, SQLite construction, membership oracle and RSS observation excluded from Stopwatch. RSS is same-process currentRss immediately after each call. 5 warmups + 20 unmodified-order samples per subscene.',
      'scenes': scenes,
      'locateStatus':
          'notMeasured: requires authorized real application instrumentation',
      'acceptance': 'incomplete-not-accepted; raw subscenes must retain host/test-VM identity when sealed into r6-performance.py partial report',
    };
  } finally {
    await library.shutdown();
    await directory.delete(recursive: true);
  }
}
