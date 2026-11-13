import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';

import 'library_test.dart' show FakeDocuments;

const _legacySongs = [
  Song(
    id: 'b',
    identity: 'b',
    location: '/b',
    name: 'SAME.mp3',
    title: 'alpha',
    artist: 'x',
    album: 'B',
    modified: 10,
  ),
  Song(
    id: 'a',
    identity: 'a',
    location: '/a',
    name: 'SAME.mp3',
    title: 'ALPHA',
    artist: 'X',
    album: 'b',
    modified: 10,
  ),
  Song(id: 'c', identity: 'c', location: '/c', name: 'a.mp3', title: 'beta'),
  Song(
    id: 'd',
    identity: 'd',
    location: '/d',
    name: 'Z.mp3',
    artist: 'A',
    album: 'A',
    modified: 20,
  ),
];

Future<void> _seed(LibraryDatabase db, Iterable<Song> songs) async {
  await db.customStatement(
    "INSERT INTO library_roots(location) VALUES ('root')",
  );
  for (final song in songs) {
    await db.into(db.songs).insert(song.toCompanion(false));
    await db.customStatement(
      'INSERT INTO song_locations(song_id,root,location,relative_path) VALUES (?, ?, ?, ?)',
      [song.id, 'root', song.location, song.name],
    );
  }
}

List<String> _ids(Iterable<LibraryTrack> rows) =>
    rows.map((t) => t.song.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('modified direction leaves unknown last and equal times stable across reloads', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    final library = LibraryController(db, FakeDocuments());
    try {
      await _seed(db, [
        ..._legacySongs,
        const Song(id: 'e', identity: 'e', location: '/e', name: 'a.mp3'),
        const Song(
          id: 'f',
          identity: 'f',
          location: '/f',
          name: 'zero',
          modified: 0,
        ),
        const Song(
          id: 'g',
          identity: 'g',
          location: '/g',
          name: 'negative',
          modified: -1,
        ),
      ]);
      await library.initialize();
      expect(library.sort, LibrarySort.modified);
      expect(library.descending, isTrue);
      expect(FilterPreferences().sort, LibrarySort.title);
      expect(FilterPreferences().descending, isFalse);
      for (var round = 0; round < 3; round++) {
        await library.reload();
        library.tracks = library.tracks.reversed.toList();
        library.filter(reverse: true);
        expect(_ids(library.visible), ['d', 'a', 'b', 'f', 'g', 'c', 'e']);
        expect(
          _ids(
            library.selectedTracks(
              library.tracks.map((t) => t.song.id).toSet(),
            ),
          ),
          _ids(library.visible),
        );
        library.filter(reverse: false);
        expect(_ids(library.visible), ['g', 'f', 'a', 'b', 'd', 'c', 'e']);
      }
    } finally {
      await library.shutdown();
    }
  });

  const expected = {
    'title': ['a', 'b', 'c', 'd'],
    'artist': ['c', 'd', 'a', 'b'],
    'album': ['c', 'd', 'a', 'b'],
    'name': ['c', 'a', 'b', 'd'],
  };
  for (final wire in expected.keys) {
    for (final descending in [false, true]) {
      test(
        'legacy raw $wire/$descending filter and smart records survive edit and reopen',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'tagmusic-r6-sort-',
          );
          final file = File('${directory.path}/legacy.sqlite');
          var library = LibraryController(
            LibraryDatabase(NativeDatabase(file)),
            FakeDocuments(),
          );
          try {
            final db = library.db;
            await _seed(db, _legacySongs);
            const rule =
                '{"version":1,"allTagIds":[],"anyTagIds":[],"excludedTagIds":[]}';
            await db.customStatement(
              'INSERT INTO current_filters(id,rule_json,sort_order,descending) VALUES (1,?,?,?)',
              [rule, wire, descending ? 1 : 0],
            );
            await db.customStatement(
              "INSERT INTO playlists(id,name,name_key,kind,rule_json,sort_order,descending) VALUES ('old','Old','old','smart',?,?,?)",
              [rule, wire, descending ? 1 : 0],
            );
            await library.initialize();
            final wanted = descending
                ? expected[wire]!.reversed.toList()
                : expected[wire]!;
            expect(library.filterPreferences.sort.name, wire);
            expect(_ids(library.filtered), wanted);
            expect(_ids(library.playlistTracks('old')), wanted);
            final before = await db
                .customSelect('SELECT * FROM current_filters')
                .getSingle();
            final beforeSmart = await db
                .customSelect("SELECT * FROM playlists WHERE id='old'")
                .getSingle();
            // Reading and abandoning an editor, and homepage sorting, write neither record.
            library.smartPreferences(library.playlists.single);
            library.filter(order: LibrarySort.artist, reverse: !descending);
            expect(
              (await db
                      .customSelect('SELECT * FROM current_filters')
                      .getSingle())
                  .data,
              before.data,
            );
            expect(
              (await db
                      .customSelect("SELECT * FROM playlists WHERE id='old'")
                      .getSingle())
                  .data,
              beforeSmart.data,
            );
            await library.updateFilter(rule: FilterRule());
            await library.editSmartPlaylist(
              'old',
              library.smartPreferences(library.playlists.single),
            );
            final regular = await library.createPlaylist('Regular', [
              'd',
              'b',
              'c',
              'a',
            ]);
            expect(_ids(library.playlistTracks(regular)), ['d', 'b', 'c', 'a']);
            await library.shutdown();
            library = LibraryController(
              LibraryDatabase(NativeDatabase(file)),
              FakeDocuments(),
            );
            await library.initialize();
            expect(library.filterPreferences.sort.name, wire);
            expect(library.filterPreferences.descending, descending);
            expect(_ids(library.filtered), wanted);
            expect(_ids(library.playlistTracks('old')), wanted);
            expect(_ids(library.playlistTracks(regular)), ['d', 'b', 'c', 'a']);
          } finally {
            await library.shutdown();
            await directory.delete(recursive: true);
          }
        },
      );
    }
  }

  test(
    'explicit modified wire round trips; unknown wire remains fail closed',
    () async {
      final db = LibraryDatabase(NativeDatabase.memory());
      final library = LibraryController(db, FakeDocuments());
      try {
        await library.initialize();
        final preferences = FilterPreferences(
          sort: LibrarySort.modified,
          descending: true,
        );
        await library.filterStore.save(preferences);
        expect((await library.filterStore.load()).sort, LibrarySort.modified);
        final smart = await library.createSmartPlaylist(
          'Modified',
          preferences,
        );
        expect(
          library.smartPreferences(library.playlists.single).sort,
          LibrarySort.modified,
        );
        await db.customStatement(
          "UPDATE current_filters SET sort_order='future'",
        );
        await expectLater(library.filterStore.load(), throwsFormatException);
        await db.customStatement(
          "UPDATE playlists SET sort_order='future' WHERE id=?",
          [smart],
        );
        await library.reloadPlaylists();
        expect(() => library.playlistTracks(smart), throwsFormatException);
      } finally {
        await library.shutdown();
      }
    },
  );
}
