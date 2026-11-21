import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'lan_sync_merge.dart';
import 'playlist_repository.dart';
import 'portable_paths.dart';

class SyncSnapshot {
  const SyncSnapshot(this.current, this.base, this.localIds);

  final SyncData current;
  final SyncData base;
  // Local UUID to the common UUID. Multiple entries can refer to the same song
  // when a previously unavailable placeholder has just been imported locally.
  final Map<String, String> localIds;
}

class LanSyncStore {
  LanSyncStore(this.db);

  final LibraryDatabase db;

  Future<String?> read(String key) async => (await (db.select(
    db.syncRecords,
  )..where((r) => r.key.equals(key))).getSingleOrNull())?.value;

  Future<void> write(String key, String value) => db
      .into(db.syncRecords)
      .insertOnConflictUpdate(SyncRecord(key: key, value: value));

  Future<SyncSnapshot> snapshot(String peer, SyncRows settings) =>
      db.transaction(() async {
        final raw = await read('peer:$peer');
        final saved = raw == null ? null : jsonDecode(raw) as SyncRow;
        final base = saved == null
            ? SyncData()
            : SyncData.decode(saved['base'] as SyncRow);
        final oldIds =
            (saved?['ids'] as SyncRow?)?.cast<String, String>() ?? const {};
        final data = SyncData();
        final ids = <String, String>{};
        final portable = <String, List<List<String>>>{};
        final available = <String>{};
        for (final row in await db.select(db.songLocations).get()) {
          if (row.available) available.add(row.songId);
          final folder = portableFolderName(row.root);
          if (folder == null) continue;
          final path = portableRelativePath(row.root, row.relativePath);
          (portable[row.songId] ??= []).add([folder, path]);
        }
        final songs = await db.select(db.songs).get();
        final physical = <String, SyncRow>{};
        for (final song in songs) {
          final paths = portable[song.id] ?? [];
          paths.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
          final row = {
            'name': song.name,
            'title': song.title,
            'artist': song.artist,
            'album': song.album,
            'size': song.size,
            'digest': song.fileSha256,
            'paths': paths,
          };
          final common = oldIds[song.id] ?? song.id;
          ids[song.id] = common;
          data['tracks'][common] = row;
          if (available.contains(song.id)) physical[song.id] = row;
        }
        final newPhysical = physical
          ..removeWhere((id, _) => oldIds.containsKey(id));
        final alreadyLinked = {for (final id in available) ?oldIds[id]};
        final unresolved = Map<String, SyncRow>.of(base['tracks'])
          ..removeWhere((id, _) => alreadyLinked.contains(id));
        final recovered = uniqueMusicMatches(
          syncTrackKeys(newPhysical),
          syncTrackKeys(unresolved),
        );
        final recoveredIds = recovered.values.toSet();
        for (final entry in recovered.entries) {
          final track = data['tracks'].remove(ids[entry.key])!;
          ids[entry.key] = entry.value;
          data['tracks'][entry.value] = track;
        }
        for (final song in songs) {
          if (song.identity != 'pending:${song.id}') continue;
          final common = ids[song.id]!;
          if (base['tracks'][common] case final old?
              when !recoveredIds.contains(common)) {
            data['tracks'][common] = old;
          }
        }
        for (final row in await db.select(db.tags).get()) {
          data['tags'][row.id] = row.toJson();
        }
        for (final row in await db.select(db.songTags).get()) {
          final song = ids[row.songId]!;
          data['songTags'][syncLink(song, row.tagId)] = {
            'songId': song,
            'tagId': row.tagId,
          };
        }
        final members = <String, Set<String>>{};
        final playlistRows = await (db.select(
          db.playlistSongs,
        )..orderBy([(row) => OrderingTerm.asc(row.position)])).get();
        for (final row in playlistRows) {
          (members[row.playlistId] ??= {}).add(ids[row.songId]!);
        }
        for (final row in await db.select(db.playlists).get()) {
          data['playlists'][row.id] = {
            ...row.toJson(),
            'members': members[row.id]?.toList() ?? <String>[],
          };
        }
        for (final row in await db.select(db.currentFilters).get()) {
          data['filters']['current'] = row.toJson();
        }
        data['settings'].addAll(settings);
        return SyncSnapshot(data, base, ids);
      });

  Future<int> apply({
    required String peer,
    required SyncSnapshot before,
    required SyncData after,
    required SyncRows settings,
    Map<String, String> remapped = const {},
  }) => db.transaction(() async {
    final latest = await snapshot(peer, settings);
    if (syncJson(latest.current.sections) !=
        syncJson(before.current.sections)) {
      throw const FormatException('本机数据在同步期间发生变化，请重新同步。');
    }
    final aliases = {
      for (final entry in before.localIds.entries)
        entry.key: remapped[entry.value] ?? entry.value,
    };
    final available = {
      for (final row in await db.select(db.songLocations).get())
        if (row.available) row.songId,
    };
    final local = <String, String>{};
    for (final entry in aliases.entries) {
      if (!local.containsKey(entry.value) || available.contains(entry.key)) {
        local[entry.value] = entry.key;
      }
    }

    final referenced = <String>{
      for (final row in after['songTags'].values) row['songId'] as String,
      for (final row in after['playlists'].values)
        ...(row['members'] as List).cast<String>(),
    };
    final roots = <String, List<LibraryRoot>>{};
    for (final row in await db.select(db.libraryRoots).get()) {
      final name = portableFolderName(row.location);
      if (name != null && !row.requiresReselection) {
        (roots[name] ??= []).add(row);
      }
    }
    for (final key in referenced) {
      if (local.containsKey(key)) continue;
      final track = after['tracks'][key];
      if (track == null) throw const FormatException('另一端的歌曲记录不完整');
      final id = const Uuid().v4();
      final identity = 'pending:$id';
      await db
          .into(db.songs)
          .insert(
            SongsCompanion.insert(
              id: id,
              identity: identity,
              location: identity,
              name: track['name'] as String,
              title: Value(track['title'] as String?),
              artist: Value(track['artist'] as String?),
              album: Value(track['album'] as String?),
              size: Value(track['size'] as int?),
              fileSha256: Value(track['digest'] as String?),
            ),
          );
      final positions = <String, Set<String>>{};
      for (final item in track['paths'] as List) {
        final [folder as String, path as String] = item as List;
        final candidates = roots[folder];
        if (candidates?.length == 1) {
          (positions[candidates!.single.location] ??= {}).add(path);
        }
      }
      for (final entry in positions.entries) {
        if (entry.value.length != 1) continue;
        await db
            .into(db.songLocations)
            .insert(
              SongLocationsCompanion.insert(
                songId: id,
                root: entry.key,
                location: identity,
                relativePath: entry.value.single,
                available: const Value(false),
              ),
            );
      }
      aliases[id] = key;
      local[key] = id;
    }

    await db.delete(db.playlistSongs).go();
    await db.delete(db.playlists).go();
    await db.delete(db.currentFilters).go();
    await db.delete(db.songTags).go();
    await db.delete(db.tags).go();
    await db.batch((batch) {
      batch.insertAll(db.tags, after['tags'].values.map(Tag.fromJson));
      batch.insertAll(
        db.songTags,
        after['songTags'].values.map(
          (row) => SongTag(
            songId: local[row['songId']]!,
            tagId: row['tagId'] as String,
          ),
        ),
      );
      batch.insertAll(
        db.currentFilters,
        after['filters'].values.map(CurrentFilter.fromJson),
      );
      batch.insertAll(
        db.playlists,
        after['playlists'].values.map(Playlist.fromJson),
      );
      batch.insertAll(db.playlistSongs, [
        for (final entry in after['playlists'].entries)
          for (final (index, song) in (entry.value['members'] as List).indexed)
            PlaylistSong(
              playlistId: entry.key,
              songId: local[song]!,
              position: index,
            ),
      ]);
    });
    await PlaylistRepository(db).ensureFavorites();
    await write(
      'peer:$peer',
      syncJson({'base': after.sections, 'ids': aliases}),
    );
    await write('lan-pending-settings', syncJson(after['settings']));
    return referenced.where((id) => !available.contains(local[id])).length;
  });

  Future<void> applyPendingSettings(
    Future<void> Function(SyncRows) apply,
  ) async {
    final pending = await read('lan-pending-settings');
    if (pending == null) return;
    await apply((jsonDecode(pending) as SyncRow).cast<String, SyncRow>());
    await (db.delete(
      db.syncRecords,
    )..where((row) => row.key.equals('lan-pending-settings'))).go();
  }
}
