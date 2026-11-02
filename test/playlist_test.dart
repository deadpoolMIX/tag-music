import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_repository.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/playlist_repository.dart';
import 'package:tag_music/playback/playback_queue.dart';

import 'library_test.dart' show FakeDocuments, entry;

class FailPlaylistMigration extends Migrator {
  FailPlaylistMigration(super.database);
  @override
  Future<void> createTable(TableInfo table) {
    if (table.actualTableName == 'playlist_songs') {
      throw const FileSystemException('simulated late migration write failure');
    }
    return super.createTable(table);
  }
}

class FailingMigrationDatabase extends LibraryDatabase {
  FailingMigrationDatabase(super.executor);
  @override
  Migrator createMigrator() => FailPlaylistMigration(this);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('regular playlist storage', () {
    late LibraryDatabase db;
    late PlaylistRepository store;
    setUp(() async {
      db = LibraryDatabase(NativeDatabase.memory());
      store = PlaylistRepository(db);
      for (final id in ['a', 'b', 'c']) {
        await db
            .into(db.songs)
            .insert(
              SongsCompanion.insert(
                id: id,
                identity: id,
                location: '/$id',
                name: '$id.mp3',
              ),
            );
      }
    });
    tearDown(() => db.close());

    test('empty lists, UUID membership deduplication, ordered add/remove/reorder and cascade', () async {
      final id = await store.create('  我的歌单  ', []);
      expect((await store.load()).playlists.single.name, '我的歌单');
      expect((await store.load()).songIds[id], isNull);
      await store.add(id, ['b', 'a', 'b']);
      await store.add(id, ['a', 'c', 'c']);
      expect((await store.load()).songIds[id], ['b', 'a', 'c']);
      await store.reorder(id, ['c', 'b', 'a']);
      await store.remove(id, ['b', 'unknown', 'b']);
      expect((await store.load()).songIds[id], ['c', 'a']);
      expect((await db.select(db.playlistSongs).get()).map((r) => r.position), [
        0,
        1,
      ]);
      await store.rename(id, 'Renamed');
      expect((await store.load()).playlists.single.name, 'Renamed');
      await store.delete(id);
      expect((await store.load()).playlists, isEmpty);
      expect(await db.select(db.playlistSongs).get(), isEmpty);
      expect(await db.select(db.songs).get(), hasLength(3));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test(
      'names are trimmed and case-insensitively unique across playlist kinds',
      () async {
        final id = await store.create(' Mix ', []);
        await expectLater(store.create('mix', []), throwsArgumentError);
        await expectLater(store.create('   ', []), throwsArgumentError);
        await store.rename(id, ' MIX ');
        await db.customStatement(
          "INSERT INTO playlists(id,name,name_key,kind,rule_json) VALUES ('smart','Smart','smart','smart',?)",
          [FilterRule().encode()],
        );
        await expectLater(store.rename(id, ' SMART '), throwsArgumentError);
        await expectLater(store.create('sMaRt', []), throwsArgumentError);
        await expectLater(store.add('smart', ['a']), throwsStateError);
        expect((await store.load()).playlists, hasLength(2));
        for (final operation in [
          store.rename('missing', 'x'),
          store.delete('missing'),
          store.add('missing', ['a']),
        ]) {
          await expectLater(operation, throwsStateError);
        }
      },
    );

    test('invalid song IDs roll back create and batch add without partial membership', () async {
      await expectLater(
        store.create('bad', ['a', 'missing']),
        throwsA(anything),
      );
      expect((await store.load()).playlists, isEmpty);
      final id = await store.create('good', ['c', 'a']);
      await expectLater(store.add(id, ['b', 'missing']), throwsA(anything));
      expect((await store.load()).songIds[id], ['c', 'a']);
      await expectLater(store.reorder(id, ['c', 'c']), throwsArgumentError);
      await expectLater(store.reorder(id, ['a']), throwsArgumentError);
      expect((await store.load()).songIds[id], ['c', 'a']);
    });

    test('failure after deletion during reorder/remove rolls the entire rewrite back', () async {
      final id = await store.create('atomic', ['a', 'b', 'c']);
      await db.customStatement(
        "CREATE TRIGGER reject_playlist_insert BEFORE INSERT ON playlist_songs WHEN NEW.song_id = 'b' BEGIN SELECT RAISE(ABORT, 'simulated full disk'); END",
      );
      await expectLater(store.reorder(id, ['c', 'b', 'a']), throwsA(anything));
      expect((await store.load()).songIds[id], ['a', 'b', 'c']);
      await expectLater(store.remove(id, ['a']), throwsA(anything));
      expect((await store.load()).songIds[id], ['a', 'b', 'c']);
      await db.customStatement('DROP TRIGGER reject_playlist_insert');
      await store.reorder(id, ['c', 'b', 'a']);
      expect((await store.load()).songIds[id], ['c', 'b', 'a']);
    });

    test(
      'database rejects duplicate positions, orphan songs and invalid kinds',
      () async {
        final id = await store.create('constraints', ['a']);
        await expectLater(
          db.customStatement('INSERT INTO playlist_songs VALUES (?, ?, ?)', [
            id,
            'b',
            0,
          ]),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('INSERT INTO playlist_songs VALUES (?, ?, ?)', [
            id,
            'b',
            -1,
          ]),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement('INSERT INTO playlist_songs VALUES (?, ?, ?)', [
            id,
            'missing',
            1,
          ]),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "INSERT INTO playlists(id,name,name_key,kind) VALUES ('bad','bad','bad','queue')",
          ),
          throwsA(anything),
        );
        expect((await store.load()).songIds[id], ['a']);
      },
    );

    test('lost songs stay ordered across rescans and playlist edits leave existing queue intact', () async {
      final access = FakeDocuments()..files['root'] = [entry('甲'), entry('乙')];
      final library = LibraryController(db, access);
      await library.initialize();
      await library.scan();
      final tracks = ['甲', '乙']
          .map(
            (name) =>
                library.tracks.singleWhere((t) => t.song.identity == name),
          )
          .toList();
      final ids = tracks.map((t) => t.song.id).toList();
      final id = await library.createPlaylist('saved queue', [
        ids[1],
        ids[0],
        ids[1],
      ]);
      final queue = PlaybackQueue()
        ..replace([
          tracks[1].queueSong,
          tracks[0].queueSong,
          tracks[1].queueSong,
        ], 1);
      final entryIds = queue.entries.map((e) => e.entryId).toList();
      access.files['root'] = [entry('甲')];
      await library.scan();
      expect(library.playlistTracks(id).map((t) => t.song.id), [
        ids[1],
        ids[0],
      ]);
      expect(library.playlistTracks(id).first.available, isFalse);
      await library.reorderPlaylist(id, [ids[0], ids[1]]);
      await library.removePlaylistSongs(id, [ids[0]]);
      await library.deletePlaylist(id);
      expect(queue.entries.map((e) => e.entryId), entryIds);
      expect(queue.entries.map((e) => e.song.songId), [ids[1], ids[0], ids[1]]);
      // This controller shares the test-owned DB; disposal must not close it twice.
      library.dispose();
    });
  });

  for (final version in [1, 2, 3]) {
    test(
      'v$version migration preserves exact old rows, reopens and supports playlists',
      () async {
        final dir = await Directory.systemTemp.createTemp('playlist-upgrade-');
        final file = File('${dir.path}/library.sqlite');
        final before = <String, List<Map<String, Object?>>>{};
        final old = sqlite.sqlite3.open(file.path);
        try {
          final baseline = jsonDecode(
            await File('docs/database-schema/v$version.json').readAsString(),
          ) as Map<String, dynamic>;
          final rows = [...baseline['schema'] as List]
            ..sort(
              (a, b) => (a['type'] == 'index' ? 1 : 0).compareTo(
                b['type'] == 'index' ? 1 : 0,
              ),
            );
          for (final row in rows) {
            old.execute(row['sql'] as String);
          }
          old.execute('PRAGMA user_version = $version');
          old.execute(
            "INSERT INTO songs(id,identity,location,name,title) VALUES ('stable','identity','content://old/document/song','曲目','标题')",
          );
          old.execute(
            "INSERT INTO library_roots(location,accessible,status) VALUES ('content://root',0,'旧目录失联')",
          );
          old.execute(
            "INSERT INTO song_locations(song_id,root,location,relative_path,available) VALUES ('stable','content://root','content://old/document/song','歌曲.mp3',0)",
          );
          if (version >= 2) {
            old.execute(
              "INSERT INTO tags(id,name,name_key) VALUES ('tag','标签','标签')",
            );
            old.execute(
              "INSERT INTO song_tags(song_id,tag_id) VALUES ('stable','tag')",
            );
          }
          if (version >= 3) {
            old.execute(
              'INSERT INTO current_filters(id,rule_json,sort_order,descending) VALUES (1,?,\'album\',1)',
              [
                FilterRule(allTagIds: ['tag']).encode(),
              ],
            );
          }
          for (final name in [
            'songs',
            'library_roots',
            'song_locations',
            if (version >= 2) ...['tags', 'song_tags'],
            if (version >= 3) 'current_filters',
          ]) {
            before[name] = old
                .select('SELECT * FROM $name')
                .map((r) => Map<String, Object?>.from(r))
                .toList();
          }
        } finally {
          old.close();
        }
        var migrated = LibraryDatabase(NativeDatabase(file));
        try {
          for (final name in before.keys) {
            expect(
              (await migrated.customSelect('SELECT * FROM $name').get()).map(
                (r) => r.data,
              ),
              before[name],
            );
          }
          expect(
            (await migrated.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            4,
          );
          expect(
            await migrated.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          if (version == 3) {
            final filter = await FilterRepository(migrated).load();
            expect(filter.rule.allTagIds, {'tag'});
            expect(filter.sort, LibrarySort.album);
            expect(filter.descending, isTrue);
          }
          final id = await PlaylistRepository(migrated)
              .create('持久歌单', ['stable', 'stable']);
          await migrated.close();
          migrated = LibraryDatabase(NativeDatabase(file));
          expect((await PlaylistRepository(migrated).load()).songIds[id], [
            'stable',
          ]);
          expect(
            (await migrated.select(migrated.songs).get()).single.id,
            'stable',
          );
          final ddl = await migrated
              .customSelect(
                "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type,name",
              )
              .get();
          final baseline = jsonDecode(
            await File('docs/database-schema/v4.json').readAsString(),
          );
          expect(ddl.map((r) => r.data).toList(), baseline['schema']);
        } finally {
          await migrated.close();
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'failed v$version migration rolls back newly created tables and version',
      () async {
        final dir = await Directory.systemTemp.createTemp('playlist-rollback-');
        final file = File('${dir.path}/library.sqlite');
        final old = sqlite.sqlite3.open(file.path);
        late List<Map<String, Object?>> beforeSchema;
        try {
          final baseline = jsonDecode(
            await File('docs/database-schema/v$version.json').readAsString(),
          );
          final ddl = [...baseline['schema'] as List]
            ..sort(
              (a, b) => (a['type'] == 'index' ? 1 : 0).compareTo(
                b['type'] == 'index' ? 1 : 0,
              ),
            );
          for (final row in ddl) {
            old.execute(row['sql'] as String);
          }
          old.execute('PRAGMA user_version = $version');
          old.execute(
            "INSERT INTO songs(id,identity,location,name) VALUES ('stable','identity','/old','old')",
          );
          old.execute("INSERT INTO library_roots(location) VALUES ('root')");
          old.execute(
            "INSERT INTO song_locations(song_id,root,location,relative_path) VALUES ('stable','root','/old','old')",
          );
          if (version >= 2) {
            old.execute(
              "INSERT INTO tags(id,name,name_key) VALUES ('tag','标签','标签')",
            );
            old.execute(
              "INSERT INTO song_tags(song_id,tag_id) VALUES ('stable','tag')",
            );
          }
          if (version == 3) {
            old.execute(
              'INSERT INTO current_filters(id,rule_json) VALUES (1,?)',
              [
                FilterRule(anyTagIds: ['tag']).encode(),
              ],
            );
          }
          beforeSchema = old
              .select(
                'SELECT type,name,sql FROM sqlite_master ORDER BY type,name',
              )
              .map((r) => Map<String, Object?>.from(r))
              .toList();
        } finally {
          old.close();
        }
        final failed = FailingMigrationDatabase(NativeDatabase(file));
        try {
          await expectLater(
            failed.select(failed.songs).get(),
            throwsA(anything),
          );
        } finally {
          await failed.close();
        }
        final check = sqlite.sqlite3.open(file.path);
        try {
          expect(
            check.select('PRAGMA user_version').single['user_version'],
            version,
          );
          expect(check.select('SELECT id FROM songs').single['id'], 'stable');
          expect(
            check
                .select('SELECT song_id,root FROM song_locations')
                .single
                .values,
            ['stable', 'root'],
          );
          if (version >= 2) {
            expect(
              check
                  .select('SELECT song_id,tag_id FROM song_tags')
                  .single
                  .values,
              ['stable', 'tag'],
            );
          }
          if (version == 3) {
            expect(
              check
                  .select('SELECT rule_json FROM current_filters')
                  .single['rule_json'],
              FilterRule(anyTagIds: ['tag']).encode(),
            );
          }
          expect(
            check
                .select(
                  'SELECT type,name,sql FROM sqlite_master ORDER BY type,name',
                )
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
            beforeSchema,
          );
          expect(
            check.select(
              "SELECT name FROM sqlite_master WHERE name='playlists'",
            ),
            isEmpty,
          );
          if (version == 1) {
            expect(
              check.select("SELECT name FROM sqlite_master WHERE name='tags'"),
              isEmpty,
            );
          }
          if (version < 3) {
            expect(
              check.select(
                "SELECT name FROM sqlite_master WHERE name='current_filters'",
              ),
              isEmpty,
            );
          }
          expect(
            check.select(
              "SELECT name FROM sqlite_master WHERE name='playlist_songs'",
            ),
            isEmpty,
          );
        } finally {
          check.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
