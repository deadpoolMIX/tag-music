import 'dart:io';

import 'package:drift/drift.dart';

import '../playback/documents.dart';
import 'database.dart';

typedef RelocationProgress = void Function(int processed);
typedef Cancelled = bool Function();

class RelocationMatch {
  const RelocationMatch(this.song, this.file, this.reason, {this.digest});
  final Song song;
  final ScannedFile file;
  final String reason;
  final String? digest;
}

class DirectoryRelocation {
  const DirectoryRelocation({
    required this.oldRoot,
    required this.newRoot,
    required this.matches,
    required this.unmatched,
  });

  final String oldRoot, newRoot;
  final List<RelocationMatch> matches;
  final List<SongLocation> unmatched;
}

class LibraryRelocation {
  const LibraryRelocation(this.db, this.documents);
  final LibraryDatabase db;
  final DocumentAccess documents;

  Future<(int, int)> saveBaselines({
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) async {
    final roots = {
      for (final root in await db.select(db.libraryRoots).get())
        if (root.accessible && !root.requiresReselection) root.location,
    };
    final locations = {
      for (final row in await db.select(db.songLocations).get())
        if (row.available && roots.contains(row.root)) row.songId: row.location,
    };
    final pending = await (db.select(
      db.songs,
    )..where((song) => song.fileSha256.isNull())).get();
    var saved = 0;
    var failed = 0;
    final staged = <Song, String>{};
    Future<void> flush() async {
      await db.batch((batch) {
        for (final entry in staged.entries) {
          batch.update(
            db.songs,
            SongsCompanion(fileSha256: Value(entry.value)),
            where: (row) => row.id.equals(entry.key.id),
          );
        }
      });
      saved += staged.length;
      staged.clear();
    }

    for (final song in pending) {
      if (cancelled()) break;
      final location = locations[song.id];
      if (location == null) continue;
      final digest = await _digest(
        ProbeTrack(
          location: location,
          name: song.name,
          size: song.size,
          modified: song.modified,
        ),
      );
      if (cancelled()) break;
      if (digest != null) {
        staged[song] = digest;
        if (staged.length >= 16) await flush();
      } else {
        failed++;
      }
      progress(saved + failed + staged.length);
    }
    if (staged.isNotEmpty) await flush();
    return (saved, failed);
  }

  Future<String?> _digest(ProbeTrack track) async {
    try {
      return await documents.musicHash(track);
    } catch (_) {
      return null;
    }
  }

  Future<List<ScannedFile>> listFiles(
    String root, {
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) async {
    final files = <String, ScannedFile>{};
    await for (final file in documents.scan(root, cancelled: cancelled)) {
      files.putIfAbsent(file.identity, () => file);
      if (files.length % 16 == 0) progress(files.length);
    }
    return files.values.toList();
  }

  Future<DirectoryRelocation> previewDirectory(
    String oldRoot,
    String newRoot, {
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) async {
    final oldRows = await (db.select(
      db.songLocations,
    )..where((row) => row.root.equals(oldRoot))).get();
    final songs = await db.select(db.songs).get();
    final byId = {for (final song in songs) song.id: song};
    final byIdentity = {for (final song in songs) song.identity: song.id};
    final files = await listFiles(
      newRoot,
      cancelled: cancelled,
      progress: progress,
    );
    final processed = files.length;
    final byPath = <String, List<ScannedFile>>{};
    final oldPathCounts = <String, int>{};
    final oldWasDesktop = !oldRoot.startsWith('content://');
    final byFileIdentity = {for (final file in files) file.identity: file};
    for (final file in files) {
      (byPath[_relativeKey(file.relativePath, desktop: !documents.android)] ??=
              [])
          .add(file);
    }
    for (final row in oldRows) {
      oldPathCounts.update(
        _relativeKey(row.relativePath, desktop: oldWasDesktop),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final matches = <String, RelocationMatch>{};
    final used = <String>{};
    bool eligible(Song song, ScannedFile file) =>
        byIdentity[file.identity] == null ||
        byIdentity[file.identity] == song.id;
    void match(Song song, ScannedFile file, String reason, {String? digest}) {
      matches[song.id] = RelocationMatch(song, file, reason, digest: digest);
      used.add(file.identity);
    }

    for (final row in oldRows) {
      final song = byId[row.songId]!;
      final file = byFileIdentity[song.identity];
      if (file != null) match(song, file, '原文件位置');
    }
    for (final row in oldRows) {
      if (matches.containsKey(row.songId)) continue;
      final key = _relativeKey(row.relativePath, desktop: oldWasDesktop);
      final samePath = byPath[key];
      if (oldPathCounts[key] != 1 || samePath?.length != 1) continue;
      final song = byId[row.songId]!;
      final file = samePath!.single;
      if (!used.contains(file.identity) && eligible(song, file)) {
        final changed =
            song.size != null && file.size != null && song.size != file.size;
        match(song, file, changed ? '相对路径一致，文件大小不同' : '相对路径一致');
      }
    }

    final sourcesByDigest = <String, List<Song>>{};
    final sizes = <int?>{};
    for (final row in oldRows) {
      final song = byId[row.songId]!;
      final digest = song.fileSha256;
      if (digest != null && !matches.containsKey(song.id)) {
        (sourcesByDigest[digest] ??= []).add(song);
        sizes.add(song.size);
      }
    }
    if (sourcesByDigest.values.any((sources) => sources.length == 1)) {
      final byDigest = <String, List<ScannedFile>>{};
      var hashed = 0;
      for (final file in files) {
        if (cancelled()) break;
        if (used.contains(file.identity) ||
            (file.size != null &&
                !sizes.contains(null) &&
                !sizes.contains(file.size))) {
          continue;
        }
        final digest = await _digest(file.probe);
        if (cancelled()) break;
        if (sourcesByDigest.containsKey(digest)) {
          (byDigest[digest!] ??= []).add(file);
        }
        progress(processed + ++hashed);
      }
      for (final entry in sourcesByDigest.entries) {
        final candidates = byDigest[entry.key];
        if (entry.value.length != 1 || candidates?.length != 1) continue;
        final song = entry.value.single;
        final file = candidates!.single;
        if (eligible(song, file)) {
          match(song, file, 'SHA-256 一致', digest: entry.key);
        }
      }
    }
    final ordered = matches.values.toList()
      ..sort((a, b) => a.file.relativePath.compareTo(b.file.relativePath));
    return DirectoryRelocation(
      oldRoot: oldRoot,
      newRoot: newRoot,
      matches: ordered,
      unmatched: oldRows
          .where((row) => !matches.containsKey(row.songId))
          .toList(),
    );
  }

  String _relativeKey(String relative, {required bool desktop}) {
    final normalized = desktop ? relative.replaceAll('\\', '/') : relative;
    return !documents.android && Platform.isWindows
        ? normalized.toLowerCase()
        : normalized;
  }

  Future<bool> applyDirectory(
    DirectoryRelocation plan, {
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) => _apply(
    plan.newRoot,
    plan.matches,
    directory: plan,
    cancelled: cancelled,
    progress: progress,
  );

  Future<bool> applySingle(
    String root,
    Song song,
    ScannedFile file, {
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) => _apply(
    root,
    [RelocationMatch(song, file, '手动选择')],
    cancelled: cancelled,
    progress: progress,
  );

  Future<bool> _apply(
    String root,
    List<RelocationMatch> matches, {
    DirectoryRelocation? directory,
    required Cancelled cancelled,
    required RelocationProgress progress,
  }) async {
    if (matches.isEmpty) return false;
    final identities = {for (final match in matches) match.file.identity};
    final files = <String, ScannedFile>{};
    await for (final file in documents.scan(root, cancelled: cancelled)) {
      if (identities.contains(file.identity)) files[file.identity] = file;
    }
    if (cancelled()) return false;
    final songs = <Song>[];
    final occupied = {
      for (final song in await db.select(db.songs).get())
        song.identity: song.id,
    };
    for (final match in matches) {
      if (cancelled()) return false;
      final old = match.song;
      final file = match.file;
      final latest = files[file.identity];
      if (latest == null ||
          latest.location != file.location ||
          latest.relativePath != file.relativePath ||
          latest.size != file.size ||
          latest.modified != file.modified) {
        throw const FileSystemException('目标文件已变化，请重新预览');
      }
      final holder = occupied[file.identity];
      if (holder != null && holder != old.id) {
        throw StateError('该文件已关联到另一条歌曲记录');
      }
      if (match.digest != null &&
          (file.size == null || file.modified == null) &&
          await _digest(file.probe) != match.digest) {
        throw const FileSystemException('目标文件已变化，请重新预览');
      }
      songs.add(await _relocatedSong(match));
      if (songs.length % 16 == 0) progress(songs.length);
    }
    if (cancelled()) return false;
    await documents.persistMusicDirectory(root);
    if (directory != null && directory.oldRoot != root) {
      await documents.forgetDirectory(directory.oldRoot);
    }
    await db.transaction(() async {
      await db
          .into(db.libraryRoots)
          .insertOnConflictUpdate(
            LibraryRootsCompanion.insert(
              location: root,
              accessible: const Value(true),
              requiresReselection: const Value(false),
              status: Value(directory == null ? '已关联歌曲' : '已重新定位'),
            ),
          );
      if (directory != null) {
        final old = directory.oldRoot;
        await (db.update(db.songLocations)
              ..where((row) => row.root.equals(old)))
            .write(const SongLocationsCompanion(available: Value(false)));
        if (old != root) {
          await db
              .into(db.syncRecords)
              .insertOnConflictUpdate(
                SyncRecord(key: 'restore-root:$old', value: root),
              );
          await db.batch((batch) {
            for (final match in matches) {
              batch.deleteWhere(
                db.songLocations,
                (row) =>
                    row.root.equals(old) & row.songId.equals(match.song.id),
              );
            }
          });
          if (directory.unmatched.isEmpty) {
            await (db.delete(
              db.libraryRoots,
            )..where((row) => row.location.equals(old))).go();
          } else {
            await (db.update(
              db.libraryRoots,
            )..where((row) => row.location.equals(old))).write(
              const LibraryRootsCompanion(
                accessible: Value(false),
                requiresReselection: Value(true),
                status: Value('仍有歌曲待重新定位'),
              ),
            );
          }
        }
      }
      await db.batch((batch) {
        for (var index = 0; index < songs.length; index++) {
          final song = songs[index];
          final match = matches[index];
          final file = match.file;
          if (song.identity != match.song.identity) {
            batch.update(
              db.songLocations,
              const SongLocationsCompanion(available: Value(false)),
              where: (row) => row.songId.equals(song.id),
            );
          }
          batch.replace(db.songs, song);
          batch.insert(
            db.songLocations,
            SongLocationsCompanion.insert(
              songId: song.id,
              root: root,
              location: file.location,
              relativePath: file.relativePath,
            ),
            onConflict: DoUpdate(
              (_) => SongLocationsCompanion(
                available: const Value(true),
                location: Value(file.location),
                relativePath: Value(file.relativePath),
              ),
            ),
          );
        }
      });
    });
    return true;
  }

  Future<Song> _relocatedSong(RelocationMatch match) async {
    final old = match.song;
    final file = match.file;
    final statMatches =
        old.identity == file.identity &&
        file.size != null &&
        file.modified != null &&
        file.size == old.size &&
        file.modified == old.modified;
    final sameContent = match.digest != null || statMatches;
    var song = old.copyWith(
      identity: file.identity,
      location: file.location,
      name: file.name,
      size: Value(file.size),
      modified: Value(file.modified),
      fileSha256: Value(match.digest ?? (statMatches ? old.fileSha256 : null)),
    );
    if (sameContent && old.metadataError == null) return song;
    try {
      final data = await documents.metadata(file.probe);
      song = song.copyWith(
        title: Value(data.title),
        artist: Value(data.artist),
        album: Value(data.album),
        durationMs: Value(data.duration?.inMilliseconds),
        metadataError: const Value(null),
      );
    } catch (error) {
      song = song.copyWith(metadataError: Value('元数据不可读：$error'));
    }
    return song;
  }
}
