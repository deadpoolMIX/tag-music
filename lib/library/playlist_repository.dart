import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class PlaylistSnapshot {
  const PlaylistSnapshot(this.playlists, this.songIds);
  final List<Playlist> playlists;
  final Map<String, List<String>> songIds;
}

/// Regular playlists contain stable song IDs, including unavailable songs.
/// All membership rewrites are transactional, so order is never partially saved.
class PlaylistRepository {
  PlaylistRepository(this.db);
  final LibraryDatabase db;

  Future<PlaylistSnapshot> load() async => db.transaction(() async {
    final lists = await (db.select(
      db.playlists,
    )..orderBy([(t) => OrderingTerm.asc(t.nameKey)])).get();
    final links = await (db.select(
      db.playlistSongs,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final byPlaylist = <String, List<String>>{};
    for (final row in links) {
      byPlaylist.putIfAbsent(row.playlistId, () => []).add(row.songId);
    }
    return PlaylistSnapshot(
      List.unmodifiable(lists),
      Map.unmodifiable({
        for (final entry in byPlaylist.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
    );
  });

  Future<String> create(String input, Iterable<String> songs) async {
    final ids = songs
        .toSet()
        .toList(); // insertion order: first occurrence wins.
    return db.transaction(() async {
      final name = await _checkName(input);
      final id = const Uuid().v4();
      await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: id,
              name: name,
              nameKey: name.toLowerCase(),
              kind: 'regular',
            ),
          );
      await _writeSongs(id, ids);
      return id;
    });
  }

  Future<String> _checkName(String input, {String? exceptId}) async {
    final name = input.trim();
    if (name.isEmpty) throw ArgumentError('歌单名称不能为空');
    final existing = await (db.select(
      db.playlists,
    )..where((t) => t.nameKey.equals(name.toLowerCase()))).getSingleOrNull();
    if (existing != null && existing.id != exceptId) {
      throw ArgumentError('已有同名歌单');
    }
    return name;
  }

  Future<void> rename(String id, String input) => db.transaction(() async {
    final name = await _checkName(input, exceptId: id);
    final changed =
        await (db.update(db.playlists)..where((t) => t.id.equals(id))).write(
          PlaylistsCompanion(
            name: Value(name),
            nameKey: Value(name.toLowerCase()),
          ),
        );
    if (changed != 1) throw StateError('歌单不存在');
  });

  Future<void> delete(String id) async {
    final changed = await (db.delete(
      db.playlists,
    )..where((t) => t.id.equals(id))).go();
    if (changed != 1) throw StateError('歌单不存在');
  }

  Future<List<String>> _regularSongs(String id) async {
    final list = await (db.select(
      db.playlists,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (list == null) throw StateError('歌单不存在');
    if (list.kind != 'regular') throw StateError('智能歌单不能手动编辑歌曲');
    final rows =
        await (db.select(db.playlistSongs)
              ..where((t) => t.playlistId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return rows.map((r) => r.songId).toList();
  }

  Future<void> add(String id, Iterable<String> songs) {
    final added = songs.toList();
    return db.transaction(() async {
      final ids = (await _regularSongs(id)).toSet()..addAll(added);
      await _writeSongs(id, ids.toList());
    });
  }

  Future<void> remove(String id, Iterable<String> songs) {
    final removed = songs.toSet();
    return db.transaction(() async {
      final ids = await _regularSongs(id);
      await _writeSongs(
        id,
        ids.where((song) => !removed.contains(song)).toList(),
      );
    });
  }

  Future<void> reorder(String id, List<String> orderedIds) {
    final ordered = List<String>.of(orderedIds);
    return db.transaction(() async {
      final old = (await _regularSongs(id)).toSet();
      if (old.length != ordered.length ||
          ordered.toSet().length != ordered.length ||
          !old.containsAll(ordered)) {
        throw ArgumentError('歌曲列表已变化，请重新排序');
      }
      await _writeSongs(id, ordered);
    });
  }

  Future<void> _writeSongs(String id, List<String> ids) async {
    // Deleting first also avoids transient UNIQUE(position) conflicts on swaps.
    await (db.delete(
      db.playlistSongs,
    )..where((t) => t.playlistId.equals(id))).go();
    await db.batch((batch) {
      for (var i = 0; i < ids.length; i++) {
        batch.insert(
          db.playlistSongs,
          PlaylistSongsCompanion.insert(
            playlistId: id,
            songId: ids[i],
            position: i,
          ),
        );
      }
    });
  }
}
