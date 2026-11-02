import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/playlist_repository.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_queue.dart';

const _size = 10000;
const _warmups = 5;
const _runs = 25;
const _queueCases = [
  'replace',
  'batchAdd',
  'removeMiddle',
  'removeCurrent',
  'reorder',
  'shuffleModeConstruction',
  'shuffleNextRound',
];

int queueSongChecksum(Iterable<String> ids) => ids.fold(
  0,
  (sum, id) => (sum * 31 + (id == 'base' ? 0 : int.parse(id) + 1)) % 2147483647,
);

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

bool _same(Iterable<String> actual, Iterable<String> expected) =>
    listEquals(actual.toList(), expected.toList());

Map<String, Object?> _timings(String name, List<int> samples) {
  final sorted = [...samples]..sort();
  return {
    'scenario': name,
    'samplesMicroseconds': samples,
    'p95Microseconds': sorted[(sorted.length * .95).ceil() - 1],
    'invariantRunsVerified': _runs,
  };
}

/// Production state machine and repository; no player or user database opened.
/// Fixture setup and all invariant checks are outside timed intervals.
Future<Map<String, Object?>> runQueueBenchmark() async {
  final songs = [
    for (var n = 0; n < _size; n++)
      QueueSong(
        songId: '$n',
        track: ProbeTrack(location: 'synthetic://$n', name: '$n.flac'),
      ),
  ];
  final ids = [for (var n = 0; n < _size; n++) '$n'];
  final queueReports = <Map<String, Object?>>[];
  for (final name in _queueCases) {
    final samples = <int>[];
    final currentIds = <String>[];
    late PlaybackQueue queue;
    late List<String> expected;
    for (var run = 0; run < _runs; run++) {
      queue = PlaybackQueue(random: Random(20261102 + run));
      expected = [...ids];
      if (name == 'batchAdd') {
        queue.replace([
          const QueueSong(
            songId: 'base',
            track: ProbeTrack(location: 'synthetic://base', name: 'base.flac'),
          ),
        ], 0);
        expected.insert(0, 'base');
      } else if (name != 'replace') {
        queue.replace(songs, 0);
      }
      if (name == 'shuffleModeConstruction') {
        queue.setMode(PlaybackMode.sequential);
      }
      if (name == 'shuffleNextRound') {
        final visited = {queue.current!.song.songId};
        for (var i = 1; i < _size; i++) {
          _check(
            visited.add(queue.next()!.song.songId),
            'Shuffle repeated before round ended',
          );
        }
        _check(
          visited.length == _size && visited.containsAll(ids),
          'Shuffle round membership differs',
        );
      }
      final ordered = queue.entries
          .map((e) => e.entryId)
          .toList()
          .reversed
          .toList();
      final middle = name == 'removeMiddle'
          ? queue.entries[_size ~/ 2].entryId
          : null;
      final current = queue.current?.entryId;
      final timer = Stopwatch()..start();
      switch (name) {
        case 'replace':
          queue.replace(songs, 0);
        case 'batchAdd':
          queue.add(songs);
        case 'removeMiddle':
          queue.remove(middle!);
        case 'removeCurrent':
          queue.remove(current!);
        case 'reorder':
          queue.reorder(ordered);
        case 'shuffleModeConstruction':
          queue.setMode(PlaybackMode.shuffle);
        case 'shuffleNextRound':
          queue.next();
      }
      timer.stop();
      if (run >= _warmups) samples.add(timer.elapsedMicroseconds);
      if (name == 'removeMiddle') expected.removeAt(_size ~/ 2);
      if (name == 'removeCurrent') expected.removeAt(0);
      if (name == 'reorder') expected = expected.reversed.toList();
      _check(
        _same(queue.entries.map((e) => e.song.songId), expected),
        '$name order/membership differs',
      );
      _check(
        queue.entries.map((e) => e.entryId).toSet().length == expected.length,
        '$name entry IDs are not unique',
      );
      final expectedCurrent = name == 'batchAdd'
          ? 'base'
          : name == 'removeCurrent'
          ? '1'
          : '0';
      final selected = queue.current!.song.songId;
      _check(
        name == 'shuffleNextRound'
            ? ids.contains(selected)
            : selected == expectedCurrent,
        '$name current identity differs',
      );
      final expectedPending = name == 'batchAdd'
          ? queue.entries.skip(1).map((e) => e.entryId)
          : <String>[];
      _check(
        _same(queue.priorityIds, expectedPending),
        '$name priority order differs',
      );
      currentIds.add(selected);
    }
    queueReports.add({
      ..._timings(name, samples),
      'resultEntries': queue.entries.length,
      'uniqueEntryIds': queue.entries.map((e) => e.entryId).toSet().length,
      'pendingEntries': queue.priorityIds.length,
      'orderedSongChecksum': queueSongChecksum(
        queue.entries.map((e) => e.song.songId),
      ),
      'currentSongIds': currentIds,
    });
  }

  final directory = await Directory.systemTemp.createTemp('tag-music-r5-');
  final db = LibraryDatabase(
    NativeDatabase.createInBackground(
      File(path.join(directory.path, 'playlists.sqlite')),
    ),
  );
  try {
    final fixtureTimer = Stopwatch()..start();
    await db.customStatement('''
      WITH RECURSIVE numbers(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM numbers WHERE n < 9999)
      INSERT INTO songs(id,identity,location,name)
      SELECT CAST(n AS TEXT), CAST(n AS TEXT), '/synthetic/' || n, '歌曲' || n FROM numbers
    ''');
    fixtureTimer.stop();
    final store = PlaylistRepository(db);
    final saves = <int>[];
    final loads = <int>[];
    for (var run = 0; run < _runs; run++) {
      final save = Stopwatch()..start();
      final id = await store.create('队列$run', [...ids, ...ids.take(1000)]);
      save.stop();
      final load = Stopwatch()..start();
      final snapshot = await store.load();
      load.stop();
      _check(
        snapshot.playlists.length == 1 &&
            snapshot.playlists.single.kind == 'regular',
        'Playlist row differs',
      );
      _check(_same(snapshot.songIds[id]!, ids), 'Playlist dedup/order differs');
      if (run >= _warmups) {
        saves.add(save.elapsedMicroseconds);
        loads.add(load.elapsedMicroseconds);
      }
      await store.delete(id);
    }
    _check(
      (await db.customSelect('PRAGMA foreign_key_check').get()).isEmpty,
      'Playlist foreign key violation',
    );
    final schema = (await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version');
    _check(schema == 4, 'Unexpected database version');
    return {
      'round': 'R5',
      'platform': Platform.operatingSystem,
      'mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'build': const int.fromEnvironment('QUEUE_BENCHMARK_BUILD'),
      'revision': const String.fromEnvironment(
        'QUEUE_BENCHMARK_REVISION',
        defaultValue: 'host-test',
      ),
      'database': 'isolated temporary SQLite, background executor',
      'schemaVersion': schema,
      'syntheticDatabaseSongs': _size,
      'realFilesScanned': 0,
      'warmupRunsPerScenario': _warmups,
      'samplesPerScenario': _runs - _warmups,
      'fixtureSetupMicroseconds': fixtureTimer.elapsedMicroseconds,
      'measurement': 'Queue state operations only, including UUID creation for replace/add. Setup, membership checks, player/FD and UI excluded. Playlist save/load include awaited transactions and are reported separately without queue time limits.',
      'queueScenarios': queueReports,
      'playlistScenarios': [
        {
          ..._timings('playlistSave', saves),
          'inputSongs': 11000,
          'resultSongs': _size,
          'orderedSongChecksum': queueSongChecksum(ids),
        },
        {
          ..._timings('playlistLoad', loads),
          'resultSongs': _size,
          'orderedSongChecksum': queueSongChecksum(ids),
        },
      ],
    };
  } finally {
    await db.close();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final target = await directory.resolveSymbolicLinks();
    if (!path.isWithin(tempRoot, target) ||
        !path.basename(target).startsWith('tag-music-r5-')) {
      throw StateError(
        'Refusing cleanup outside the benchmark temporary directory',
      );
    }
    await Directory(target).delete(recursive: true);
  }
}
