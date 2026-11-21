import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_repository.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/tag_repository.dart';

import 'library_test.dart' show FakeDocuments, entry;

class FailingFilterRepository extends FilterRepository {
  FailingFilterRepository(super.db);
  bool fail = true;
  @override
  Future<void> save(FilterPreferences preferences) async {
    if (fail) throw const FileSystemException('simulated full disk');
    await super.save(preferences);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final songs = <String, Set<String>>{
    '1': {'A', 'B'},
    '2': {'A', 'B', 'E'},
    '3': {'C'},
    '4': {'D', 'F'},
    '5': {},
    '6': {'A'},
  };
  Set<String> result(FilterRule rule) => rule.evaluate(songs.keys, songs);

  test('three-box formula with independent explicit expected sets', () {
    expect(
      result(
        FilterRule(
          allTagIds: ['A', 'B'],
          anyTagIds: ['C', 'D'],
          excludedTagIds: ['E', 'F'],
        ),
      ),
      {'1', '3'},
    );
    expect(result(FilterRule(allTagIds: ['A', 'B'])), {'1', '2'});
    expect(result(FilterRule(anyTagIds: ['C', 'D'])), {'3', '4'});
    expect(result(FilterRule(excludedTagIds: ['E', 'F'])), {
      '1',
      '3',
      '5',
      '6',
    });
    expect(result(FilterRule()), {'1', '2', '3', '4', '5', '6'});
    expect(result(FilterRule(allTagIds: ['A', 'C'])), isEmpty);
    expect(
      result(FilterRule(allTagIds: ['A'], excludedTagIds: ['A'])),
      isEmpty,
    );
    // A contradiction in one include operand does not invalidate the other.
    expect(
      result(
        FilterRule(allTagIds: ['A'], anyTagIds: ['C'], excludedTagIds: ['A']),
      ),
      {'3'},
    );
    expect(
      result(
        FilterRule(allTagIds: ['A'], anyTagIds: ['A'], excludedTagIds: ['E']),
      ),
      {'1', '6'},
    );
    expect(FilterRule(anyTagIds: ['A', 'A']).anyTagIds, {'A'});
    expect(() => FilterRule().allTagIds.add('A'), throwsUnsupportedError);
  });

  test('versioned encoding, pruning and invalid documents', () {
    final rule = FilterRule(
      allTagIds: ['B', 'A'],
      anyTagIds: ['A'],
      excludedTagIds: ['A'],
    );
    expect(FilterRule.decode(rule.encode()).encode(), rule.encode());
    expect(rule.without('A').referencedIds, {'B'});
    expect(rule.without('A').without('B').isEmpty, isTrue);
    for (final source in [
      'bad',
      '{}',
      '{"version":2}',
      '{"version":1,"allTagIds":[3],"anyTagIds":[],"excludedTagIds":[]}',
    ]) {
      expect(() => FilterRule.decode(source), throwsFormatException);
    }
  });

  for (final version in [1, 2]) {
    test(
      'v$version file migrates and reopens with all old data intact',
      () async {
        final dir = await Directory.systemTemp.createTemp('filter-migration-');
        final file = File('${dir.path}/library.sqlite');
        final baseline = jsonDecode(
          await File('docs/database-schema/v$version.json').readAsString(),
        ) as Map<String, dynamic>;
        final old = sqlite.sqlite3.open(file.path);
        final before = <String, List<Map<String, Object?>>>{};
        try {
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
            "INSERT INTO songs(id,identity,location,name) VALUES ('song','identity','/song','歌曲')",
          );
          old.execute("INSERT INTO library_roots(location) VALUES ('root')");
          old.execute(
            "INSERT INTO song_locations(song_id,root,location,relative_path) VALUES ('song','root','/song','song')",
          );
          if (version == 2) {
            old.execute(
              "INSERT INTO tags(id,name,name_key) VALUES ('A','标签','标签')",
            );
            old.execute(
              "INSERT INTO song_tags(song_id,tag_id) VALUES ('song','A')",
            );
          }
          for (final name in [
            'songs',
            'library_roots',
            'song_locations',
            if (version == 2) ...['tags', 'song_tags'],
          ]) {
            before[name] = old
                .select('SELECT * FROM $name')
                .map((row) => Map<String, Object?>.from(row))
                .toList();
          }
        } finally {
          old.close();
        }
        var db = LibraryDatabase(NativeDatabase(file));
        try {
          for (final entry in before.entries) {
            final columns = entry.value.first.keys.join(', ');
            expect(
              (await db.customSelect('SELECT $columns FROM ${entry.key}').get())
                  .map((row) => row.data)
                  .toList(),
              entry.value,
            );
          }
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            7,
          );
          final repository = FilterRepository(db);
          expect((await repository.load()).rule.isEmpty, isTrue);
          await repository.save(
            FilterPreferences(
              rule: FilterRule(anyTagIds: version == 2 ? ['A'] : []),
              sort: LibrarySort.artist,
              descending: true,
            ),
          );
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          await db.close();
          db = LibraryDatabase(NativeDatabase(file));
          final restored = await FilterRepository(db).load();
          expect(restored.sort, LibrarySort.artist);
          expect(restored.descending, isTrue);
          expect(restored.rule.anyTagIds, version == 2 ? {'A'} : isEmpty);
        } finally {
          await db.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }

  test('tag deletion prunes every box atomically; failed rule save rolls back deletion', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    try {
      final tags = TagRepository(db);
      final repository = FilterRepository(db);
      await tags.create('A');
      final id = (await tags.load()).tags.single.id;
      await repository.save(
        FilterPreferences(
          rule: FilterRule(
            allTagIds: [id],
            anyTagIds: [id],
            excludedTagIds: [id],
          ),
        ),
      );
      await db.customStatement(
        "CREATE TRIGGER fail_filter BEFORE UPDATE ON current_filters BEGIN SELECT RAISE(ABORT, 'simulated save failure'); END",
      );
      await expectLater(tags.delete(id), throwsA(anything));
      expect((await tags.load()).tags.single.id, id);
      expect((await repository.load()).rule.referencedIds, {id});
      await db.customStatement('DROP TRIGGER fail_filter');
      await tags.rename(id, 'Renamed');
      expect((await repository.load()).rule.referencedIds, {id});
      await tags.delete(id);
      expect((await repository.load()).rule.isEmpty, isTrue);
      expect((await tags.load()).tags, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('controller updates immediately, serializes saves, reports failure and recovers', () async {
    final access = FakeDocuments()..files['root'] = [entry('甲'), entry('乙')];
    final db = LibraryDatabase(NativeDatabase.memory());
    final repository = FailingFilterRepository(db);
    final library = LibraryController(db, access, filterStore: repository);
    try {
      await library.initialize();
      await library.scan();
      await library.createTag('A');
      final tag = library.tags.single.id;
      await library.changeSongTags(tag, [
        library.tracks.first.song.id,
      ], add: true);
      final saving = library.updateFilter(rule: FilterRule(allTagIds: [tag]));
      expect(library.filtered.length, 1);
      await saving;
      expect(library.filterSaveError, contains('未保存'));
      expect((await FilterRepository(db).load()).rule.isEmpty, isTrue);
      repository.fail = false;
      final first = library.updateFilter(rule: FilterRule(anyTagIds: [tag]));
      final last = library.updateFilter(
        rule: FilterRule(excludedTagIds: [tag]),
        order: LibrarySort.name,
        reverse: true,
      );
      await Future.wait([first, last]);
      expect(library.filterSaveError, isNull);
      expect((await FilterRepository(db).load()).rule.excludedTagIds, {tag});
      library.filter(text: 'independent');
      expect(library.visible, isEmpty);
      expect(library.filtered.length, 1);
      access.files['root'] = [];
      await library.scan();
      expect(library.filtered, isEmpty);
      access.files['root'] = [entry('甲'), entry('乙')];
      await library.scan();
      expect(library.filtered.length, 1);
      await library.deleteTag(tag);
      expect(library.filtered.length, 2);
      expect((await FilterRepository(db).load()).rule.isEmpty, isTrue);
    } finally {
      await library.shutdown();
    }
  });

  test('controller restores rule and sort after reopening but leaves result search empty', () async {
    final dir = await Directory.systemTemp.createTemp('filter-reopen-');
    final file = File('${dir.path}/library.sqlite');
    final access = FakeDocuments()..files['root'] = [entry('甲'), entry('乙')];
    var library = LibraryController(
      LibraryDatabase(NativeDatabase(file)),
      access,
    );
    try {
      await library.initialize();
      await library.scan();
      await library.createTag('A');
      final tag = library.tags.single.id;
      await library.changeSongTags(tag, [
        library.tracks.first.song.id,
      ], add: true);
      await library.updateFilter(
        rule: FilterRule(anyTagIds: [tag]),
        order: LibrarySort.album,
        reverse: true,
      );
      library.searchFilter('temporary search');
      await library.shutdown();
      library = LibraryController(
        LibraryDatabase(NativeDatabase(file)),
        access,
      );
      await library.initialize();
      expect(library.filterPreferences.rule.anyTagIds, {tag});
      expect(library.filterPreferences.sort, LibrarySort.album);
      expect(library.filterPreferences.descending, isTrue);
      expect(library.filterQuery, isEmpty);
      expect(library.filtered.length, 1);
    } finally {
      await library.shutdown();
      await dir.delete(recursive: true);
    }
  });

  test(
    'failed v2 migration leaves old version and tag relations intact',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'filter-failed-migration-',
      );
      final file = File('${dir.path}/library.sqlite');
      final baseline = jsonDecode(
        await File('docs/database-schema/v2.json').readAsString(),
      ) as Map<String, dynamic>;
      final old = sqlite.sqlite3.open(file.path);
      try {
        final ddl = [...baseline['schema'] as List]
          ..sort(
            (a, b) => (a['type'] == 'index' ? 1 : 0).compareTo(
              b['type'] == 'index' ? 1 : 0,
            ),
          );
        for (final row in ddl) {
          old.execute(row['sql'] as String);
        }
        old.execute('PRAGMA user_version = 2');
        old.execute(
          "INSERT INTO songs(id,identity,location,name) VALUES ('song','identity','/song','歌曲')",
        );
        old.execute(
          "INSERT INTO tags(id,name,name_key) VALUES ('tag','标签','标签')",
        );
        old.execute(
          "INSERT INTO song_tags(song_id,tag_id) VALUES ('song','tag')",
        );
      } finally {
        old.close();
      }
      final db = LibraryDatabase(
        NativeDatabase.opened(
          sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly),
        ),
      );
      try {
        await expectLater(db.select(db.songs).get(), throwsA(anything));
      } finally {
        await db.close();
      }
      final check = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        expect(check.select('PRAGMA user_version').single['user_version'], 2);
        expect(
          check.select('SELECT song_id,tag_id FROM song_tags').single.values,
          ['song', 'tag'],
        );
        expect(
          check.select(
            "SELECT name FROM sqlite_master WHERE name='current_filters'",
          ),
          isEmpty,
        );
      } finally {
        check.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('unknown stored rule is preserved and blocks results until explicit reset', () async {
    final db = LibraryDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO current_filters(id,rule_json) VALUES (1,'{\"version\":99}')",
    );
    final library = LibraryController(db, FakeDocuments());
    try {
      await library.initialize();
      expect(library.filterLoadError, isNotNull);
      expect(library.filtered, isEmpty);
      await library.updateFilter(rule: FilterRule());
      expect(
        (await db.select(db.currentFilters).getSingle()).ruleJson,
        '{"version":99}',
      );
      await library.updateFilter(rule: FilterRule(), reset: true);
      expect(library.filterLoadError, isNull);
      expect((await FilterRepository(db).load()).rule.isEmpty, isTrue);
    } finally {
      await library.shutdown();
    }
  });
}
