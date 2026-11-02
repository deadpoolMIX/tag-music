import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_repository.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/playlist_repository.dart';
import 'package:tag_music/playback/playback_queue.dart';

import 'library_test.dart' show FakeDocuments, entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryController library;
  late FakeDocuments access;
  late Map<String, String> songs;
  late Map<String, String> tags;
  Directory? temporary;
  setUp(() async {
    access = FakeDocuments()
      ..files['root'] = [entry('A'), entry('B'), entry('C')];
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      access,
    );
    await library.initialize();
    await library.scan();
    for (final name in ['X', 'Y', 'Z']) {
      await library.createTag(name);
    }
    songs = {for (final t in library.tracks) t.song.identity: t.song.id};
    tags = {for (final t in library.tags) t.name: t.id};
    await library.changeSongTags(tags['X']!, [
      songs['A']!,
      songs['B']!,
    ], add: true);
    await library.changeSongTags(tags['Y']!, [songs['B']!], add: true);
    await library.changeSongTags(tags['Z']!, [songs['C']!], add: true);
  });
  tearDown(() async {
    await library.shutdown();
    final directory = temporary;
    if (directory != null) {
      final tempRoot = Directory.systemTemp.absolute.path;
      if (!directory.absolute.path.startsWith(
        '$tempRoot${Platform.pathSeparator}tag-music-r5-smart-',
      )) {
        throw StateError('Unexpected temporary directory');
      }
      await directory.delete(recursive: true);
      temporary = null;
    }
  });

  FilterPreferences prefs({
    Iterable<String> all = const [],
    Iterable<String> any = const [],
    Iterable<String> excluded = const [],
    bool descending = false,
  }) => FilterPreferences(
    rule: FilterRule(allTagIds: all, anyTagIds: any, excludedTagIds: excluded),
    sort: LibrarySort.name,
    descending: descending,
  );
  Playlist list(String id) => library.playlists.singleWhere((p) => p.id == id);
  List<String> members(String id) =>
      library.playlistTracks(id).map((t) => t.song.identity).toList();

  test('file database reopen restores smart rules/sort and songs but no search text', () async {
    await library.shutdown();
    temporary = await Directory.systemTemp.createTemp('tag-music-r5-smart-');
    final file = File('${temporary!.path}/library.sqlite');
    library = LibraryController(LibraryDatabase(NativeDatabase(file)), access);
    await library.initialize();
    await library.scan();
    await library.createTag('Persisted');
    final tag = library.tags.single.id;
    final song = library.tracks
        .singleWhere((t) => t.song.identity == 'B')
        .song
        .id;
    await library.changeSongTags(tag, [song], add: true);
    final id = await library.createSmartPlaylist(
      'Saved',
      prefs(all: [tag], descending: true),
    );
    library.searchFilter('not persisted');
    await library.shutdown();
    library = LibraryController(LibraryDatabase(NativeDatabase(file)), access);
    await library.initialize();
    expect(members(id), ['B']);
    expect(library.filterQuery, isEmpty);
    final preferences = library.smartPreferences(list(id));
    expect(preferences.rule.allTagIds, {tag});
    expect(preferences.sort, LibrarySort.name);
    expect(preferences.descending, isTrue);
    expect(library.playlistSongIds[id], isNull);
  });

  test(
    'independent versioned rules/sort survive reload, rename and shared names',
    () async {
      await library.updateFilter(rule: FilterRule(anyTagIds: [tags['Z']!]));
      library.searchFilter('never stored');
      final id = await library.createSmartPlaylist(
        ' Dynamic ',
        prefs(all: [tags['X']!], descending: true),
      );
      expect(list(id).name, 'Dynamic');
      expect(list(id).ruleJson, contains('"version":1'));
      expect(members(id), ['B', 'A']);
      expect(await library.db.select(library.db.playlistSongs).get(), isEmpty);
      await library.reload();
      expect(members(id), ['B', 'A']);
      expect(
        library.filtered,
        isEmpty,
      ); // the unrelated current search is still active
      await expectLater(
        library.createPlaylist('dynamic', []),
        throwsArgumentError,
      );
      await expectLater(
        library.createSmartPlaylist('DYNAMIC', prefs()),
        throwsArgumentError,
      );
      await library.renamePlaylist(id, 'Renamed');
      await library.editSmartPlaylist(id, prefs(any: [tags['Z']!]));
      expect(members(id), ['C']);
      expect(library.filterPreferences.rule.anyTagIds, {tags['Z']});
      final persisted = await FilterRepository(library.db).load();
      expect(persisted.rule.anyTagIds, {tags['Z']});
      expect(
        (await library.db.select(library.db.currentFilters).getSingle())
            .ruleJson,
        isNot(contains('never stored')),
      );
    },
  );

  test('tag/library changes recompute available songs, leaving playback snapshot intact', () async {
    final id = await library.createSmartPlaylist(
      'Dynamic',
      prefs(all: [tags['X']!]),
    );
    final queue = PlaybackQueue()
      ..replace(library.playlistTracks(id).map((t) => t.queueSong).toList(), 0);
    final entries = queue.entries.map((e) => e.entryId).toList();
    await library.changeSongTags(tags['X']!, [songs['C']!], add: true);
    expect(members(id), ['A', 'B', 'C']);
    await library.changeSongTags(tags['X']!, [songs['A']!], add: false);
    expect(members(id), ['B', 'C']);
    access.files['root'] = [entry('A'), entry('C')];
    await library.scan();
    expect(members(id), ['C']);
    access.files['root'] = [entry('A'), entry('B'), entry('C')];
    await library.scan();
    expect(members(id), ['B', 'C']);
    await library.deletePlaylist(id);
    expect(queue.entries.map((e) => e.entryId), entries);
    expect(queue.entries.map((e) => e.song.songId), [songs['A'], songs['B']]);
  });

  test('delete preview and transaction prune all boxes across current and multiple smart rules', () async {
    final x = tags['X']!;
    await library.updateFilter(rule: FilterRule(allTagIds: [x]));
    final expanded = await library.createSmartPlaylist(
      'Expanded',
      prefs(all: [x]),
    );
    final shrunk = await library.createSmartPlaylist(
      'Shrunk',
      prefs(any: [x, tags['Z']!]),
    );
    final overlap = await library.createSmartPlaylist(
      'Overlap',
      prefs(all: [x], any: [x], excluded: [x]),
    );
    final unaffected = await library.createSmartPlaylist(
      'Other',
      prefs(any: [tags['Y']!]),
    );
    final originalOther = list(unaffected).ruleJson;
    final queue = PlaybackQueue()
      ..replace(
        library.playlistTracks(expanded).map((t) => t.queueSong).toList(),
        0,
      );
    final entryIds = queue.entries.map((e) => e.entryId).toList();
    expect(library.tagDeletionEffects(x), [
      '当前筛选：2 → 3 首（全部具备）',
      '智能歌单“Expanded”：2 → 3 首（全部具备）',
      '智能歌单“Overlap”：0 → 3 首（全部具备、任一具备、排除标签）',
      '智能歌单“Shrunk”：3 → 1 首（任一具备）',
    ]);
    var inconsistentSnapshots = 0;
    library.addListener(() {
      final knownTags = library.tags.map((t) => t.id).toSet();
      for (final saved in library.playlists.where((p) => p.kind == 'smart')) {
        if (!knownTags.containsAll(
          PlaylistRepository.preferences(saved).rule.referencedIds,
        )) {
          inconsistentSnapshots++;
        }
      }
    });
    await library.deleteTag(x);
    expect(inconsistentSnapshots, 0);
    expect(library.filterPreferences.rule.isEmpty, isTrue);
    expect((await FilterRepository(library.db).load()).rule.isEmpty, isTrue);
    for (final id in [expanded, shrunk, overlap]) {
      expect(
        library.smartPreferences(list(id)).rule.referencedIds,
        isNot(contains(x)),
      );
    }
    expect(members(expanded), ['A', 'B', 'C']);
    expect(members(shrunk), ['C']);
    expect(members(overlap), ['A', 'B', 'C']);
    expect(list(unaffected).ruleJson, originalOther);
    expect(
      await (library.db.select(
        library.db.songTags,
      )..where((t) => t.tagId.equals(x))).get(),
      isEmpty,
    );
    expect(queue.entries.map((e) => e.entryId), entryIds);
    expect(queue.entries.map((e) => e.song.songId), [songs['A'], songs['B']]);
  });

  test('late failure rolls back tag, song links, current filter and every smart rule', () async {
    final x = tags['X']!;
    final rule = prefs(all: [x]);
    await library.updateFilter(rule: rule.rule, order: rule.sort);
    final a = await library.createSmartPlaylist('First', rule);
    final b = await library.createSmartPlaylist('Last', rule);
    final before = {for (final p in library.playlists) p.id: p.ruleJson};
    await library.db.customStatement(
      "CREATE TRIGGER fail_smart_update BEFORE UPDATE ON playlists WHEN OLD.id = '$b' BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END",
    );
    await expectLater(library.deleteTag(x), throwsA(isA<Exception>()));
    expect(library.filterDeletingTag, isFalse);
    final persisted = await library.playlistsStore.load();
    expect({for (final p in persisted.playlists) p.id: p.ruleJson}, before);
    expect((await FilterRepository(library.db).load()).rule.allTagIds, {x});
    expect(
      (await library.db.select(library.db.tags).get()).map((t) => t.id),
      contains(x),
    );
    expect(
      (await (library.db.select(
        library.db.songTags,
      )..where((t) => t.tagId.equals(x))).get()).length,
      2,
    );
    expect(members(a), ['A', 'B']);
    expect(members(b), ['A', 'B']);
    await library.db.customStatement('DROP TRIGGER fail_smart_update');
    await library.deleteTag(x);
    expect(members(a), ['A', 'B', 'C']);
  });

  test('invalid/unknown rules fail closed and stale tag writes cannot restore dangling references', () async {
    final x = tags['X']!;
    final stale = prefs(all: [x]);
    final id = await library.createSmartPlaylist('Smart', stale);
    await library.db.customStatement(
      'UPDATE playlists SET rule_json = ? WHERE id = ?',
      ['{"version":99}', id],
    );
    await library.reloadPlaylists();
    expect(() => members(id), throwsFormatException);
    expect(() => library.tagDeletionEffects(x), throwsFormatException);
    await expectLater(library.deleteTag(x), throwsFormatException);
    expect(library.tags.map((t) => t.id), contains(x));
    // Explicit edit can repair a damaged rule; it never changes the current filter.
    await library.editSmartPlaylist(id, stale);
    await library.deleteTag(x);
    await expectLater(
      library.editSmartPlaylist(id, stale),
      throwsFormatException,
    );
    await expectLater(
      library.createSmartPlaylist('Stale', stale),
      throwsFormatException,
    );
    expect(members(id), ['A', 'B', 'C']);
  });

  test('queued current-filter writes and concurrent smart edit cannot restore a deleted tag', () async {
    final x = tags['X']!;
    final id = await library.createSmartPlaylist('Concurrent', prefs(all: [x]));
    final first = library.updateFilter(rule: FilterRule(allTagIds: [x]));
    final last = library.updateFilter(rule: FilterRule(excludedTagIds: [x]));
    final deletion = library.deleteTag(x);
    expect(library.filterDeletingTag, isTrue);
    final ignored = library.updateFilter(rule: FilterRule(anyTagIds: [x]));
    final edit = library
        .editSmartPlaylist(id, prefs(any: [x]))
        .onError<FormatException>((_, _) {});
    await Future.wait([first, last, deletion, ignored, edit]);
    await library.reloadPlaylists();
    expect(library.filterPreferences.rule.isEmpty, isTrue);
    expect((await FilterRepository(library.db).load()).rule.isEmpty, isTrue);
    expect(library.smartPreferences(list(id)).rule.isEmpty, isTrue);
    expect(library.tags.map((t) => t.id), isNot(contains(x)));
    expect(library.filterSaving, isFalse);
  });

  test('smart edit is transactional, validates kind and does not silently replace invalid sort', () async {
    final normal = await library.createPlaylist('Regular', []);
    await expectLater(
      library.editSmartPlaylist(normal, prefs()),
      throwsStateError,
    );
    final id = await library.createSmartPlaylist('Smart', prefs());
    final before = list(id).ruleJson;
    await library.db.customStatement(
      "CREATE TRIGGER fail_smart_edit BEFORE UPDATE ON playlists BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    await expectLater(
      library.editSmartPlaylist(id, prefs(any: [tags['Y']!])),
      throwsA(isA<Exception>()),
    );
    expect(
      (await library.playlistsStore.load()).playlists
          .singleWhere((p) => p.id == id)
          .ruleJson,
      before,
    );
    await library.db.customStatement('DROP TRIGGER fail_smart_edit');
    await library.db.customStatement(
      'UPDATE playlists SET sort_order = ? WHERE id = ?',
      ['unknown', id],
    );
    await library.reloadPlaylists();
    expect(
      () => PlaylistRepository.preferences(list(id)),
      throwsFormatException,
    );
  });
}
