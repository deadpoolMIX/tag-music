import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/tag_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device synthetic 10000-song tag query benchmark', (
    tester,
  ) async {
    // This isolated database never opens the user's library or audio files.
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('tag-music-r3-');
      final db = LibraryDatabase(
        NativeDatabase.createInBackground(
          File('${directory.path}/tags.sqlite'),
        ),
      );
      try {
        await db.customStatement(
          "INSERT INTO tags (id, name, name_key) VALUES ('tag', '收藏', '收藏')",
        );
        await db.transaction(() async {
          // Recursive SQL avoids timing fixture generation over platform calls.
          await db.customStatement('''
            WITH RECURSIVE numbers(n) AS (
              SELECT 0 UNION ALL SELECT n + 1 FROM numbers WHERE n < 9999
            )
            INSERT INTO songs (id, identity, location, name)
            SELECT CAST(n AS TEXT), CAST(n AS TEXT), '/synthetic/' || n,
                   '合成歌曲' || n FROM numbers
          ''');
          await db.customStatement(
            "INSERT INTO song_tags (song_id, tag_id) SELECT id, 'tag' FROM songs",
          );
        });
        final repository = TagRepository(db);
        final samples = <int>[];
        for (var i = 0; i < 25; i++) {
          final timer = Stopwatch()..start();
          final snapshot = await repository.load();
          timer.stop();
          expect(snapshot.bySong.length, 10000);
          expect(
            snapshot.bySong.values.every((ids) => ids.contains('tag')),
            isTrue,
          );
          if (i >= 5) samples.add(timer.elapsedMicroseconds);
        }
        final ordered = [...samples]..sort();
        final p95 = ordered[(ordered.length * .95).ceil() - 1];
        final report = <String, dynamic>{
          'platform': Platform.operatingSystem,
          'mode': kReleaseMode
              ? 'release'
              : kProfileMode
              ? 'profile'
              : 'debug',
          'database': 'isolated temporary SQLite, background executor',
          'syntheticDatabaseSongs': 10000,
          'taggedSongs': 10000,
          'realFilesScanned': 0,
          'warmupRuns': 5,
          'samplesMicroseconds': samples,
          'warmTagLoadP95Microseconds': p95,
        };
        binding.reportData = report;
        debugPrint('R3_TAG_BENCHMARK ${jsonEncode(report)}');
        expect(p95, lessThan(Platform.isAndroid ? 1000000 : 500000));
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    });
  });
}
