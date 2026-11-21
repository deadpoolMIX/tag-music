part of 'library_backup.dart';

class BackupMatch {
  const BackupMatch(this.backup, this.directories, this.matchedSongs);

  final LibraryBackup backup;
  final Map<String, String> directories;
  final int matchedSongs;
}

Future<BackupMatch> previewBackupMatch(
  LibraryBackup backup,
  LibraryDatabase db,
) => db.transaction(
  () async => matchBackup(backup, await LibraryBackup._capture(db), db),
);

Future<BackupMatch> matchBackup(
  LibraryBackup incoming,
  LibraryBackup local,
  LibraryDatabase db,
) async {
  final localRoots = {
    for (final root in local.roots)
      if (!root.requiresReselection) root.location: root,
  };
  Map<String, List<SongLocation>> group(Iterable<SongLocation> rows) {
    final grouped = <String, List<SongLocation>>{};
    for (final row in rows) {
      (grouped[row.root] ??= []).add(row);
    }
    return grouped;
  }

  final oldGroups = group(incoming.locations);
  final localGroups = group(
    local.locations.where(
      (row) => row.available && localRoots[row.root]?.accessible == true,
    ),
  );
  final oldSongs = {for (final song in incoming.songs) song.id: song};
  final localSongs = {for (final song in local.songs) song.id: song};
  final directories = <String, String>{};
  final remembered = {
    for (final row in await (db.select(
      db.syncRecords,
    )..where((r) => r.key.like('restore-root:%'))).get())
      row.key.substring('restore-root:'.length): row.value,
  };
  Map<String, Set<String>> keys(
    List<SongLocation> rows,
    Map<String, Song> songs,
  ) {
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final song = songs[row.songId]!;
      final rel = portableRelativePath(row.root, row.relativePath);
      final set = result[row.songId] ??= {};
      set.add(jsonEncode([rel, song.size]));
      if (song.fileSha256 case final digest?) set.add('sha256:$digest');
    }
    return result;
  }

  final oldKeys = {
    for (final e in oldGroups.entries) e.key: keys(e.value, oldSongs),
  };
  final localKeys = {
    for (final e in localGroups.entries) e.key: keys(e.value, localSongs),
  };
  final directoryCandidates = <String, List<String>>{};
  final reverse = <String, int>{};
  for (final root in incoming.roots) {
    final source = root.location;
    if (localRoots.containsKey(source)) {
      directories[source] = source;
      continue;
    }
    final label = portableFolderName(source);
    final candidates = directoryCandidates[source] = [];
    final saved = remembered[source];
    final refs = oldKeys[source];
    if (saved != null && localRoots.containsKey(saved)) {
      candidates.add(saved);
    } else if (label != null && refs != null) {
      for (final entry in localKeys.entries) {
        if (portableFolderName(entry.key) != label) continue;
        final overlap = uniqueMusicMatches(refs, entry.value).length;
        final smaller = refs.length < entry.value.length
            ? refs.length
            : entry.value.length;
        if (overlap > 0 &&
            overlap * 2 >= smaller &&
            (overlap >= 3 || overlap == smaller)) {
          candidates.add(entry.key);
        }
      }
    }
    for (final target in candidates) {
      reverse.update(target, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  for (final entry in directoryCandidates.entries) {
    final candidates = entry.value;
    if (candidates.length == 1 &&
        reverse[candidates.single] == 1 &&
        !directories.containsValue(candidates.single)) {
      directories[entry.key] = candidates.single;
    }
  }

  final locations = <SongLocation>[];
  final replacements = <String, Song>{};
  final claimed = <String, String>{};
  for (final entry in oldGroups.entries) {
    final source = entry.key;
    final target = directories[source] ?? source;
    final existing = {
      for (final row in localGroups[target] ?? <SongLocation>[])
        row.songId: row,
    };
    final matches = directories.containsKey(source)
        ? uniqueMusicMatches(oldKeys[source]!, localKeys[target] ?? const {})
        : const <String, String>{};
    final exact = {for (final row in existing.values) row.location: row};
    for (final row in entry.value) {
      final same = target == source ? exact[row.location] : null;
      final localRow =
          same != null &&
              localSongs[same.songId]?.identity ==
                  oldSongs[row.songId]?.identity
          ? same
          : existing[matches[row.songId]];
      final oldReplacement = replacements[row.songId];
      if (localRow != null &&
          (claimed[localRow.songId] ?? row.songId) == row.songId &&
          (oldReplacement == null || localRow.songId == oldReplacement.id)) {
        final song = localSongs[localRow.songId]!;
        replacements[row.songId] = song;
        claimed[song.id] = row.songId;
        locations.add(localRow.copyWith(songId: row.songId));
      } else {
        locations.add(row.copyWith(root: target, available: false));
      }
    }
  }
  return BackupMatch(
    LibraryBackup(
      songs: [
        for (final song in incoming.songs)
          replacements[song.id]?.copyWith(id: song.id) ??
              song.copyWith(identity: 'pending:${song.id}'),
      ],
      roots: [
        for (final root in incoming.roots)
          localRoots[directories[root.location]] ??
              root.copyWith(
                accessible: false,
                requiresReselection: true,
                status: '等待重新定位',
                scannedAt: const Value(null),
              ),
      ],
      locations: locations,
      tags: incoming.tags,
      songTags: incoming.songTags,
      filters: incoming.filters,
      playlists: incoming.playlists,
      playlistSongs: incoming.playlistSongs,
      playCounts: incoming.playCounts,
    ),
    directories,
    replacements.length,
  );
}
