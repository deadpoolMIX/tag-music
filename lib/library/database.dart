import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Songs extends Table {
  TextColumn get id => text()();
  TextColumn get identity => text().unique()();
  TextColumn get location => text()();
  TextColumn get name => text()();
  IntColumn get size => integer().nullable()();
  IntColumn get modified => integer().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get metadataError => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class LibraryRoots extends Table {
  TextColumn get location => text()();
  BoolColumn get accessible => boolean().withDefault(const Constant(true))();
  TextColumn get status => text().withDefault(const Constant('尚未扫描'))();
  IntColumn get scannedAt => integer().nullable()();
  @override
  Set<Column> get primaryKey => {location};
}

class SongLocations extends Table {
  TextColumn get songId => text().references(Songs, #id)();
  TextColumn get root => text().references(LibraryRoots, #location)();
  TextColumn get location => text()();
  TextColumn get relativePath => text()();
  BoolColumn get available => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {songId, root};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameKey => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class SongTags extends Table {
  TextColumn get songId =>
      text().references(Songs, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {songId, tagId};
}

class CurrentFilters extends Table {
  IntColumn get id => integer()
      .withDefault(const Constant(1))
      .check(const CustomExpression<bool>('"id" = 1'))();
  TextColumn get ruleJson => text()();
  TextColumn get sortOrder => text().withDefault(const Constant('title'))();
  BoolColumn get descending => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [Songs, LibraryRoots, SongLocations, Tags, SongTags, CurrentFilters],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'tag_music_library',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ),
      );
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX song_tags_tag_id_idx ON song_tags (tag_id)',
      );
    },
    onUpgrade: (m, from, to) async {
      if ((from == 1 || from == 2) && to == 3) {
        if (from == 1) {
          await m.createTable(tags);
          await m.createTable(songTags);
          await customStatement(
            'CREATE INDEX song_tags_tag_id_idx ON song_tags (tag_id)',
          );
        }
        await m.createTable(currentFilters);
        return;
      }
      throw StateError('不支持的数据库升级 $from → $to');
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
