import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'filter_rule.dart';
import 'playlist_repository.dart';
import 'portable_paths.dart';

part 'backup_delta.dart';
part 'backup_matching.dart';

const backupByteLimit = 64 * 1024 * 1024;
const _format = 'tag-music-library';
const _version = 1;

class LibraryBackup {
  const LibraryBackup({
    required this.songs,
    required this.roots,
    required this.locations,
    required this.tags,
    required this.songTags,
    required this.filters,
    required this.playlists,
    required this.playlistSongs,
    this.playCounts = const {},
  });

  final List<Song> songs;
  final List<LibraryRoot> roots;
  final List<SongLocation> locations;
  final List<Tag> tags;
  final List<SongTag> songTags;
  final List<CurrentFilter> filters;
  final List<Playlist> playlists;
  final List<PlaylistSong> playlistSongs;
  // A missing entry is from a snapshot created before playback counts existed.
  final Map<String, int> playCounts;

  static Future<LibraryBackup> _capture(LibraryDatabase db) async =>
      LibraryBackup(
        songs: await db.select(db.songs).get(),
        roots: await db.select(db.libraryRoots).get(),
        locations: await db.select(db.songLocations).get(),
        tags: await db.select(db.tags).get(),
        songTags: await db.select(db.songTags).get(),
        filters: await db.select(db.currentFilters).get(),
        playlists: await db.select(db.playlists).get(),
        playlistSongs: await db.select(db.playlistSongs).get(),
        playCounts: {
          for (final row in await db.select(db.songPlayCounts).get())
            row.songId: row.playCount,
        },
      );

  static Future<Uint8List> export(LibraryDatabase db) async =>
      _encode(await db.transaction(() => _capture(db)));

  static Future<LibraryBackup> decode(Uint8List bytes) async {
    if (bytes.length > backupByteLimit) {
      throw const FormatException('备份超过 64 MiB');
    }
    return Isolate.run(() => _decodeBackup(bytes));
  }

  Future<void> restore(
    LibraryDatabase db, {
    required File recoveryFile,
    required bool trustedLocations,
  }) => db.transaction(() async {
    final current = await _capture(db);
    final match = trustedLocations
        ? null
        : await matchBackup(this, current, db);
    final restored = match?.backup ?? this;
    final restoredCounts = <SongPlayCount>[];
    for (final song in songs) {
      final count = playCounts[song.id] ?? current.playCounts[song.id] ?? 0;
      if (count > 0) {
        restoredCounts.add(SongPlayCount(songId: song.id, playCount: count));
      }
    }

    await db.delete(db.playlistSongs).go();
    await db.delete(db.playlists).go();
    await db.delete(db.currentFilters).go();
    await db.delete(db.songTags).go();
    await db.delete(db.tags).go();
    await db.delete(db.songLocations).go();
    await db.delete(db.libraryRoots).go();
    await db.delete(db.songs).go();

    await db.batch((batch) {
      batch.insertAll(db.songs, restored.songs);
      batch.insertAll(db.songPlayCounts, restoredCounts);
      batch.insertAll(db.libraryRoots, restored.roots);
      batch.insertAll(db.songLocations, restored.locations);
      batch.insertAll(db.tags, tags);
      batch.insertAll(db.songTags, songTags);
      batch.insertAll(db.currentFilters, filters);
      batch.insertAll(db.playlists, playlists);
      batch.insertAll(db.playlistSongs, playlistSongs);
    });
    if (match != null) {
      await db.batch((batch) {
        for (final entry in match.directories.entries) {
          if (entry.key != entry.value) {
            batch.insert(
              db.syncRecords,
              SyncRecord(key: 'restore-root:${entry.key}', value: entry.value),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
    }
    if (!trustedLocations) await PlaylistRepository(db).ensureFavorites();
    // Write the recovery file before SQLite commits. A storage failure rolls
    // back all SQL changes and leaves the previous recovery file intact.
    await writeBackupFile(recoveryFile, await _encode(current));
  });
}

Future<File> recoveryBackupFile() async => File(
  p.join(
    (await getApplicationSupportDirectory()).path,
    'before-restore.tagmusic',
  ),
);

Future<void> writeBackupFile(File target, Uint8List bytes) async {
  final temporary = File('${target.path}.${const Uuid().v4()}.tmp');
  await temporary.create(exclusive: true);
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<Uint8List> readBackupFile(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (builder.length + chunk.length > backupByteLimit) {
      throw const FormatException('备份超过 64 MiB');
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<Uint8List> _encode(LibraryBackup backup) =>
    Isolate.run(() => _encodeBackup(backup));

Uint8List _encodeBackup(LibraryBackup backup) {
  final data = <String, dynamic>{
    'songs': backup.songs
        .map(
          (row) => {
            ...row.toJson(),
            'playCount': backup.playCounts[row.id] ?? 0,
          },
        )
        .toList(),
    'roots': backup.roots.map((row) => row.toJson()).toList(),
    'locations': backup.locations.map((row) => row.toJson()).toList(),
    'tags': backup.tags.map((row) => row.toJson()).toList(),
    'songTags': backup.songTags.map((row) => row.toJson()).toList(),
    'filters': backup.filters.map((row) => row.toJson()).toList(),
    'playlists': backup.playlists.map((row) => row.toJson()).toList(),
    'playlistSongs': backup.playlistSongs.map((row) => row.toJson()).toList(),
  };
  for (final entry in data.entries) {
    final rows = entry.value as List<Map<String, dynamic>>;
    rows.sort((a, b) => _rowKey(entry.key, a).compareTo(_rowKey(entry.key, b)));
  }
  return _encodePackage(_format, data);
}

LibraryBackup _decodeBackup(Uint8List bytes) {
  try {
    final package = _readPackage(bytes);
    if (package.format == _incrementFormat) {
      throw const FormatException('请使用「从备份文件夹恢复」打开增量备份。');
    }
    if (package.format != _format) {
      throw const FormatException('请选择 Tag Music 备份文件');
    }
    final data = package.data;
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (data[key] as List)
            .map((item) => parse(item as Map<String, dynamic>))
            .toList();
    final playCounts = <String, int>{};
    for (final row in (data['songs'] as List).cast<Map<String, dynamic>>()) {
      if (!row.containsKey('playCount')) continue;
      final count = row['playCount'];
      if (count is! int || count < 0) {
        throw const FormatException('备份的播放次数无效');
      }
      playCounts[row['id'] as String] = count;
    }
    final backup = LibraryBackup(
      songs: rows('songs', Song.fromJson),
      roots: rows('roots', LibraryRoot.fromJson),
      locations: rows('locations', SongLocation.fromJson),
      tags: rows('tags', Tag.fromJson),
      songTags: rows('songTags', SongTag.fromJson),
      filters: rows('filters', CurrentFilter.fromJson),
      playlists: rows('playlists', Playlist.fromJson),
      playlistSongs: rows('playlistSongs', PlaylistSong.fromJson),
      playCounts: playCounts,
    );
    final tags = {for (final row in backup.tags) row.id};
    for (final row in backup.filters) {
      if (!LibrarySort.values.any((sort) => sort.name == row.sortOrder) ||
          !tags.containsAll(FilterRule.decode(row.ruleJson).referencedIds)) {
        throw const FormatException('备份的筛选配置损坏');
      }
    }
    final regular = <String>{};
    for (final row in backup.playlists) {
      if (row.kind == 'regular') {
        regular.add(row.id);
      } else if (!tags.containsAll(
        PlaylistRepository.preferences(row).rule.referencedIds,
      )) {
        throw const FormatException('备份的智能歌单配置损坏');
      }
    }
    if (backup.playlistSongs.any((row) => !regular.contains(row.playlistId))) {
      throw const FormatException('备份的普通歌单配置损坏');
    }
    return backup;
  } on TypeError {
    throw const FormatException('备份的数据结构损坏');
  }
}
