import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'filter_repository.dart';
import 'filter_rule.dart';
import 'playlist_repository.dart';

class TagSnapshot {
  const TagSnapshot(this.tags, this.bySong);
  final List<Tag> tags;
  final Map<String, Set<String>> bySong;
}

class TagRepository {
  TagRepository(this.db);
  final LibraryDatabase db;

  static String normalize(String value) => value.trim();
  static String key(String value) => normalize(value).toLowerCase();

  Future<TagSnapshot> load() async {
    final tags = await db.select(db.tags).get();
    tags.sort((a, b) => a.nameKey.compareTo(b.nameKey));
    final links = await db.select(db.songTags).get();
    final bySong = <String, Set<String>>{};
    for (final link in links) {
      bySong.putIfAbsent(link.songId, () => <String>{}).add(link.tagId);
    }
    return TagSnapshot(List.unmodifiable(tags), bySong);
  }

  Future<void> _checkName(String name, {String? exceptId}) async {
    if (name.isEmpty) throw ArgumentError('标签名称不能为空');
    final existing = await (db.select(
      db.tags,
    )..where((t) => t.nameKey.equals(key(name)))).getSingleOrNull();
    if (existing != null && existing.id != exceptId) {
      throw ArgumentError('已有同名标签');
    }
  }

  Future<void> create(String input) async {
    final name = normalize(input);
    await _checkName(name);
    await db
        .into(db.tags)
        .insert(
          TagsCompanion.insert(
            id: const Uuid().v4(),
            name: name,
            nameKey: key(name),
          ),
        );
  }

  Future<void> rename(String id, String input) async {
    final name = normalize(input);
    await _checkName(name, exceptId: id);
    final changed = await (db.update(db.tags)..where((t) => t.id.equals(id)))
        .write(TagsCompanion(name: Value(name), nameKey: Value(key(name))));
    if (changed != 1) throw StateError('标签不存在');
  }

  Future<void> delete(String id, {FilterPreferences? currentFilter}) async {
    await db.transaction(() async {
      final filters = FilterRepository(db);
      final current = currentFilter ?? await filters.load();
      final smart =
          await (db.select(db.playlists)
                ..where((t) => t.kind.equals('smart'))
                ..orderBy([(t) => OrderingTerm.asc(t.nameKey)]))
              .get();
      // Decode every rule before deleting anything; unreadable rules cannot be
      // assumed to have no reference to the tag.
      final affected = <String, FilterPreferences>{};
      for (final list in smart) {
        final preferences = PlaylistRepository.preferences(list);
        if (preferences.rule.referencedIds.contains(id)) {
          affected[list.id] = preferences.without(id);
        }
      }
      final changed = await (db.delete(
        db.tags,
      )..where((t) => t.id.equals(id))).go();
      if (changed != 1) throw StateError('标签不存在');
      await filters.save(current.without(id));
      for (final entry in affected.entries) {
        await (db.update(
          db.playlists,
        )..where((t) => t.id.equals(entry.key))).write(
          PlaylistsCompanion(ruleJson: Value(entry.value.rule.encode())),
        );
      }
    });
  }

  Future<void> changeSongs(
    String tagId,
    Iterable<String> songIds, {
    required bool add,
  }) async {
    final ids = songIds.toSet();
    if (ids.isEmpty) return;
    await db.transaction(() async {
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.id.equals(tagId))).getSingleOrNull();
      if (tag == null) throw StateError('标签不存在');
      for (final songId in ids) {
        if (add) {
          await db.customStatement(
            'INSERT OR IGNORE INTO song_tags (song_id, tag_id) VALUES (?, ?)',
            [songId, tagId],
          );
        } else {
          await db.customStatement(
            'DELETE FROM song_tags WHERE song_id = ? AND tag_id = ?',
            [songId, tagId],
          );
        }
      }
    });
  }
}
