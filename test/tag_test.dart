import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/tag_repository.dart';

import 'library_test.dart' show FakeDocuments, entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'v1 file upgrades to current schema without changing songs or locations',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tag-music-tag-upgrade-',
      );
      final file = File('${dir.path}/library.sqlite');
      final baseline = jsonDecode(
        await File('docs/database-schema/v1.json').readAsString(),
      ) as Map<String, dynamic>;
      final old = sqlite.sqlite3.open(file.path);
      try {
        for (final row in baseline['schema'] as List<dynamic>) {
          old.execute((row as Map<String, dynamic>)['sql'] as String);
        }
        old.execute('PRAGMA user_version = 1');
        old.execute(
          "INSERT INTO songs (id, identity, location, name) VALUES ('stable-id', 'old-song', '/old.mp3', 'old.mp3')",
        );
        old.execute("INSERT INTO library_roots (location) VALUES ('old-root')");
        old.execute(
          "INSERT INTO song_locations (song_id, root, location, relative_path) VALUES ('stable-id', 'old-root', '/old.mp3', 'old.mp3')",
        );
      } finally {
        old.close();
      }
      final db = LibraryDatabase(NativeDatabase(file));
      try {
        expect((await db.select(db.songs).get()).single.id, 'stable-id');
        expect(
          (await db.select(db.songLocations).get()).single.songId,
          'stable-id',
        );
        expect((await db.select(db.tags).get()), isEmpty);
        final tags = TagRepository(db);
        await tags.create(' Rock ');
        final tag = (await tags.load()).tags.single;
        await tags.changeSongs(tag.id, ['stable-id'], add: true);
        expect((await tags.load()).bySong['stable-id'], {tag.id});
        expect(
          (await db.customSelect('PRAGMA foreign_key_check').get()),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          3,
        );
      } finally {
        await db.close();
      }
      final reopened = LibraryDatabase(NativeDatabase(file));
      try {
        expect(
          (await reopened.select(reopened.songs).get()).single.id,
          'stable-id',
        );
        expect(
          (await reopened.select(reopened.songTags).get()).single.songId,
          'stable-id',
        );
      } finally {
        await reopened.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'tag names, bulk changes and deletion preserve relationship integrity',
    () async {
      final db = LibraryDatabase(NativeDatabase.memory());
      final tags = TagRepository(db);
      try {
        for (final id in ['one', 'two']) {
          await db.customStatement(
            'INSERT INTO songs (id, identity, location, name) VALUES (?, ?, ?, ?)',
            [id, id, '/$id.mp3', '$id.mp3'],
          );
        }
        await tags.create(' Rock ');
        final id = (await tags.load()).tags.single.id;
        expect((await tags.load()).tags.single.name, 'Rock');
        await expectLater(tags.create('rock'), throwsArgumentError);
        await expectLater(tags.create('  '), throwsArgumentError);
        await tags.changeSongs(id, ['one', 'two', 'one'], add: true);
        await tags.changeSongs(id, ['one'], add: true);
        expect((await db.select(db.songTags).get()).length, 2);
        await tags.rename(id, ' ROCK ');
        expect((await tags.load()).tags.single.name, 'ROCK');
        await tags.changeSongs(id, ['one'], add: false);
        expect((await tags.load()).bySong['one'], isNull);
        await expectLater(
          tags.changeSongs(id, ['one', 'missing'], add: true),
          throwsA(isA<Exception>()),
        );
        expect(
          (await tags.load()).bySong['one'],
          isNull,
          reason: 'failed bulk add must roll back all links',
        );
        await tags.delete(id);
        expect((await db.select(db.songTags).get()), isEmpty);
        expect((await db.select(db.songs).get()).length, 2);
        expect(
          (await db.customSelect('PRAGMA foreign_key_check').get()),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );

  test('missing and rescanned songs keep tags and stable IDs', () async {
    final access = FakeDocuments()..files['root'] = [entry('tagged')];
    final library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      access,
    );
    try {
      await library.initialize();
      await library.scan();
      final songId = library.tracks.single.song.id;
      await library.createTag('收藏');
      final tagId = library.tags.single.id;
      await library.changeSongTags(tagId, [songId], add: true);
      access.files['root'] = [];
      await library.scan();
      expect(library.tracks.single.available, isFalse);
      expect(library.tagsForSong(songId), {tagId});
      expect(library.countForTag(tagId), 1);
      access.files['root'] = [entry('tagged')];
      await library.scan();
      expect(library.tracks.single.song.id, songId);
      expect(library.tracks.single.available, isTrue);
      expect(library.tagsForSong(songId), {tagId});
    } finally {
      await library.shutdown();
    }
  });

  test('failed read-only v1 upgrade leaves the old database intact', () async {
    final dir = await Directory.systemTemp.createTemp('tag-music-readonly-');
    final file = File('${dir.path}/library.sqlite');
    final baseline = jsonDecode(
      await File('docs/database-schema/v1.json').readAsString(),
    ) as Map<String, dynamic>;
    final old = sqlite.sqlite3.open(file.path);
    for (final row in baseline['schema'] as List<dynamic>) {
      old.execute((row as Map<String, dynamic>)['sql'] as String);
    }
    old.execute('PRAGMA user_version = 1');
    old.execute(
      "INSERT INTO songs (id, identity, location, name) VALUES ('kept', 'kept', '/kept', 'kept')",
    );
    old.close();
    final readOnly = LibraryDatabase(
      NativeDatabase.opened(
        sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly),
      ),
    );
    try {
      await expectLater(
        readOnly.select(readOnly.songs).get(),
        throwsA(anything),
      );
    } finally {
      await readOnly.close();
    }
    final unchanged = sqlite.sqlite3.open(
      file.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      expect(unchanged.select('PRAGMA user_version').single.values.single, 1);
      expect(unchanged.select('SELECT id FROM songs').single['id'], 'kept');
      expect(
        unchanged.select(
          "SELECT name FROM sqlite_master WHERE name = 'song_tags'",
        ),
        isEmpty,
      );
    } finally {
      unchanged.close();
      await dir.delete(recursive: true);
    }
  });

  test('10000-song warm tag query benchmark', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    try {
      await db.customStatement(
        "INSERT INTO tags (id, name, name_key) VALUES ('tag', '收藏', '收藏')",
      );
      await db.transaction(() async {
        for (var i = 0; i < 10000; i++) {
          await db.customStatement(
            'INSERT INTO songs (id, identity, location, name) VALUES (?, ?, ?, ?)',
            ['$i', '$i', '/$i', '$i'],
          );
          await db.customStatement(
            "INSERT INTO song_tags (song_id, tag_id) VALUES (?, 'tag')",
            ['$i'],
          );
        }
      });
      final repo = TagRepository(db);
      final samples = <int>[];
      for (var i = 0; i < 25; i++) {
        final timer = Stopwatch()..start();
        final result = await repo.load();
        timer.stop();
        expect(result.bySong.length, 10000);
        if (i >= 5) samples.add(timer.elapsedMicroseconds);
      }
      samples.sort();
      final p95 = samples[(samples.length * .95).ceil() - 1];
      final limit = Platform.isAndroid ? 1000000 : 500000;
      expect(p95, lessThan(limit));
      final report = Platform.environment['TAG_MUSIC_TAG_REPORT'];
      if (report != null) {
        await File(report).writeAsString(
          jsonEncode({
            'platform': Platform.operatingSystem,
            'syntheticDatabaseSongs': 10000,
            'taggedSongs': 10000,
            'warmTagLoadP95Microseconds': p95,
            'samples': samples,
          }),
        );
      }
    } finally {
      await db.close();
    }
  });
}
