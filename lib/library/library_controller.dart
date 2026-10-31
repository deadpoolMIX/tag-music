import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../playback/documents.dart';
import 'database.dart';
import 'tag_repository.dart';
import 'filter_rule.dart';
import 'filter_repository.dart';

export 'filter_rule.dart' show LibrarySort;

final libraryProvider = Provider<LibraryController?>((ref) => null);

class LibraryTrack {
  const LibraryTrack(this.song, this.location);
  final Song song;
  final String? location;
  bool get available => location != null;
  String get title =>
      song.title?.trim().isNotEmpty == true ? song.title! : song.name;
  ProbeTrack get probe =>
      ProbeTrack(location: location ?? song.location, name: song.name);
}

class LibraryController extends ChangeNotifier {
  LibraryController(this.db, this.documents, {FilterRepository? filterStore})
    : tagsStore = TagRepository(db),
      filterStore = filterStore ?? FilterRepository(db);
  final LibraryDatabase db;
  final DocumentAccess documents;
  final TagRepository tagsStore;
  final FilterRepository filterStore;
  FilterPreferences filterPreferences = FilterPreferences();
  String filterQuery = '';
  String? filterLoadError;
  String? filterSaveError;
  bool filterDeletingTag = false;
  int _filterWritesPending = 0;
  int _filterWriteRevision = 0;
  Future<void>? _filterWrites;
  List<LibraryTrack>? _matchedCache;
  List<LibraryTrack>? _filteredCache;
  bool get filterSaving => _filterWritesPending > 0;

  List<LibraryTrack> get filterMatches => _matchedCache ??= List.unmodifiable(
    filterLoadError != null
        ? <LibraryTrack>[]
        : tracks.where(
            (t) =>
                t.available &&
                filterPreferences.rule.matches(
                  tagIdsBySong[t.song.id] ?? const {},
                ),
          ),
  );

  List<LibraryTrack> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    final needle = filterQuery.trim().toLowerCase();
    final rows = filterMatches
        .where(
          (t) =>
              needle.isEmpty ||
              [
                t.title,
                t.song.name,
                t.song.artist ?? '',
                t.song.album ?? '',
              ].any((value) => value.toLowerCase().contains(needle)),
        )
        .toList();
    _sortTracks(rows, filterPreferences.sort, filterPreferences.descending);
    return _filteredCache = List.unmodifiable(rows);
  }

  void _invalidateFilter() {
    _matchedCache = null;
    _filteredCache = null;
  }

  void searchFilter(String text) {
    filterQuery = text;
    _filteredCache = null;
    _publish();
  }

  Future<void> updateFilter({
    FilterRule? rule,
    LibrarySort? order,
    bool? reverse,
    bool reset = false,
  }) {
    if (filterDeletingTag || (filterLoadError != null && !reset)) {
      return Future.value();
    }
    filterPreferences = FilterPreferences(
      rule: rule ?? filterPreferences.rule,
      sort: order ?? filterPreferences.sort,
      descending: reverse ?? filterPreferences.descending,
    );
    filterLoadError = null;
    _invalidateFilter();
    final preferences = filterPreferences;
    final revision = ++_filterWriteRevision;
    _filterWritesPending++;
    _publish();
    final previous = _filterWrites;
    return _filterWrites = () async {
      if (previous != null) await previous;
      try {
        await filterStore.save(preferences);
        if (revision == _filterWriteRevision) filterSaveError = null;
      } catch (error) {
        if (revision == _filterWriteRevision) filterSaveError = '筛选未保存：$error';
      } finally {
        _filterWritesPending--;
        if (_filterWritesPending == 0) _filterWrites = null;
        _publish();
      }
    }();
  }

  List<LibraryTrack> tracks = [];
  List<LibraryRoot> roots = [];
  List<Tag> tags = [];
  Map<String, Set<String>> tagIdsBySong = {};
  Map<String, int> tagCounts = {};
  String query = '';
  LibrarySort sort = LibrarySort.title;
  bool descending = false;
  bool showMissing = true;
  bool scanning = false;
  bool choosing = false;
  bool _cancelled = false;
  bool _closed = false;
  int discovered = 0;
  int metadataReads = 0;
  String? scanningRoot;
  String? message;
  Future<void>? _scanTask;
  List<LibraryTrack>? _visibleCache;

  List<LibraryTrack> get visible {
    if (_visibleCache != null) return _visibleCache!;
    final needle = query.trim().toLowerCase();
    final rows = tracks
        .where(
          (t) =>
              (showMissing || t.available) &&
              (needle.isEmpty ||
                  [
                    t.title,
                    t.song.name,
                    t.song.artist ?? '',
                    t.song.album ?? '',
                  ].any((v) => v.toLowerCase().contains(needle))),
        )
        .toList();
    _sortTracks(rows, sort, descending);
    return _visibleCache = List.unmodifiable(rows);
  }

  void _sortTracks(List<LibraryTrack> rows, LibrarySort sort, bool descending) {
    String value(LibraryTrack t) => switch (sort) {
      LibrarySort.title => t.title,
      LibrarySort.artist => t.song.artist ?? '',
      LibrarySort.album => t.song.album ?? '',
      LibrarySort.name => t.song.name,
    };
    rows.sort((a, b) {
      var result = value(a).toLowerCase().compareTo(value(b).toLowerCase());
      if (result == 0) result = a.song.name.compareTo(b.song.name);
      if (result == 0) result = a.song.id.compareTo(b.song.id);
      return descending ? -result : result;
    });
  }

  void _publish() {
    if (!_closed) notifyListeners();
  }

  void filter({
    String? text,
    LibrarySort? order,
    bool? reverse,
    bool? missing,
  }) {
    query = text ?? query;
    sort = order ?? sort;
    descending = reverse ?? descending;
    showMissing = missing ?? showMissing;
    _visibleCache = null;
    _publish();
  }

  Future<void> initialize() async {
    // Import R1 directory bookmarks once; no audio is opened at startup.
    for (final root in await documents.roots()) {
      await _addRoot(root);
    }
    await reload();
    try {
      filterPreferences = await filterStore.load();
      if (!tags
          .map((t) => t.id)
          .toSet()
          .containsAll(filterPreferences.rule.referencedIds)) {
        throw const FormatException('筛选引用的标签不存在');
      }
    } catch (error) {
      filterLoadError = '无法读取筛选：$error';
    }
    _invalidateFilter();
    _publish();
  }

  Set<String> tagsForSong(String songId) =>
      Set.unmodifiable(tagIdsBySong[songId] ?? const <String>{});

  int countForTag(String tagId) => tagCounts[tagId] ?? 0;

  List<LibraryTrack> tracksForTag(String tagId) => List.unmodifiable(
    tracks.where(
      (track) => tagIdsBySong[track.song.id]?.contains(tagId) == true,
    ),
  );

  Future<void> reloadTags() async {
    final snapshot = await tagsStore.load();
    tags = snapshot.tags;
    tagIdsBySong = snapshot.bySong;
    tagCounts = _countTags(snapshot.bySong);
    _invalidateFilter();
    _publish();
  }

  Future<void> createTag(String name) async {
    await tagsStore.create(name);
    await reloadTags();
  }

  Future<void> renameTag(String id, String name) async {
    await tagsStore.rename(id, name);
    await reloadTags();
  }

  Future<void> deleteTag(String id) async {
    if (filterDeletingTag) throw StateError('正在删除标签');
    filterDeletingTag = true;
    _publish();
    try {
      await _filterWrites;
      // Do not overwrite an unreadable rule with a default during deletion.
      await tagsStore.delete(
        id,
        currentFilter: filterLoadError == null ? filterPreferences : null,
      );
      filterPreferences = filterPreferences.without(id);
      if (filterLoadError == null) filterSaveError = null;
      await reloadTags();
    } finally {
      filterDeletingTag = false;
      _publish();
    }
  }

  Future<void> changeSongTags(
    String tagId,
    Iterable<String> songIds, {
    required bool add,
  }) async {
    await tagsStore.changeSongs(tagId, songIds, add: add);
    await reloadTags();
  }

  Future<void> _addRoot(String root) => db
      .into(db.libraryRoots)
      .insert(
        LibraryRootsCompanion.insert(location: root),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> reload() async {
    roots = await db.select(db.libraryRoots).get();
    final songs = await db.select(db.songs).get();
    final locations = await (db.select(
      db.songLocations,
    )..where((r) => r.available.equals(true))).get();
    final bySong = <String, String>{};
    final unavailableRoots = roots
        .where((r) => !r.accessible)
        .map((r) => r.location)
        .toSet();
    for (final row in locations) {
      if (!unavailableRoots.contains(row.root)) {
        bySong.putIfAbsent(row.songId, () => row.location);
      }
    }
    tracks = [for (final song in songs) LibraryTrack(song, bySong[song.id])];
    _visibleCache = null;
    final tagSnapshot = await tagsStore.load();
    tags = tagSnapshot.tags;
    tagIdsBySong = tagSnapshot.bySong;
    tagCounts = _countTags(tagSnapshot.bySong);
    _invalidateFilter();
    _publish();
  }

  Map<String, int> _countTags(Map<String, Set<String>> bySong) {
    final counts = <String, int>{};
    for (final ids in bySong.values) {
      for (final id in ids) {
        counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  Future<void> chooseDirectory() async {
    if (scanning || choosing) return;
    choosing = true;
    _publish();
    String? root;
    try {
      root = await documents.pickDirectory();
      if (root != null) {
        await _addRoot(root);
        await reload();
      }
    } catch (e) {
      message = '目录选择失败：$e';
    } finally {
      choosing = false;
      _publish();
    }
    if (root != null) await scan([root]);
  }

  void cancelScan() {
    if (scanning) {
      _cancelled = true;
      message = '正在取消，已提交的目录仍保留…';
      _publish();
    }
  }

  Future<void> scan([List<String>? selected]) {
    if (scanning || choosing) return Future.value();
    return _scanTask = _scan(selected ?? roots.map((r) => r.location).toList());
  }

  Future<void> _scan(List<String> selected) async {
    scanning = true;
    _cancelled = false;
    discovered = 0;
    metadataReads = 0;
    message = null;
    _publish();
    var failures = 0;
    try {
      for (final root in selected) {
        if (_cancelled) break;
        scanningRoot = root;
        await _addRoot(root);
        try {
          final existing = {for (final t in tracks) t.song.identity: t.song};
          final staged = <String, (ScannedFile, Song)>{};
          await for (final file in documents.scan(
            root,
            cancelled: () => _cancelled,
          )) {
            if (_cancelled) break;
            discovered++;
            final old = existing[file.identity];
            Song song;
            if (old != null &&
                old.metadataError == null &&
                file.size != null &&
                file.modified != null &&
                old.size == file.size &&
                old.modified == file.modified) {
              song = old.copyWith(name: file.name, location: file.location);
            } else {
              TrackMetadata? metadata;
              String? failure;
              try {
                metadataReads++;
                metadata = await documents.metadata(file.probe);
              } catch (e) {
                failure = '元数据不可读：$e';
              }
              if (_cancelled) break;
              song = Song(
                id: old?.id ?? const Uuid().v4(),
                identity: file.identity,
                location: file.location,
                name: file.name,
                size: file.size,
                modified: file.modified,
                title: failure == null ? metadata?.title : old?.title,
                artist: failure == null ? metadata?.artist : old?.artist,
                album: failure == null ? metadata?.album : old?.album,
                durationMs: failure == null
                    ? metadata?.duration?.inMilliseconds
                    : old?.durationMs,
                metadataError: failure,
              );
            }
            staged[file.identity] = (file, song);
            if (discovered % 10 == 0) _publish();
          }
          if (_cancelled) break;
          // Atomic per root: interrupted enumeration never marks unseen files missing.
          await db.transaction(() async {
            await (db.update(db.songLocations)
                  ..where((r) => r.root.equals(root)))
                .write(const SongLocationsCompanion(available: Value(false)));
            await db.batch((batch) {
              for (final (file, song) in staged.values) {
                batch.insert(
                  db.songs,
                  song,
                  onConflict: DoUpdate((_) => song.toCompanion(false)),
                );
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
            await (db.update(
              db.libraryRoots,
            )..where((r) => r.location.equals(root))).write(
              LibraryRootsCompanion(
                accessible: const Value(true),
                status: const Value('扫描完成'),
                scannedAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );
          });
          await reload();
        } catch (e) {
          failures++;
          await (db.update(
            db.libraryRoots,
          )..where((r) => r.location.equals(root))).write(
            LibraryRootsCompanion(
              accessible: const Value(false),
              status: Value('不可访问，已保留原曲库：$e'),
            ),
          );
        }
      }
      message = _cancelled
          ? '扫描已取消；未完成目录的原曲库保持不变。'
          : '扫描结束：发现 $discovered 首，读取元数据 $metadataReads 首，失败目录 $failures 个。';
    } catch (e) {
      message = '扫描失败，已保留原曲库：$e';
    } finally {
      scanning = false;
      scanningRoot = null;
      try {
        await reload();
      } catch (e) {
        message = '曲库读取失败，扫描已停止：$e';
      }
      _publish();
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    _cancelled = true;
    await _scanTask;
    await _filterWrites;
    await db.close();
    super.dispose();
  }
}
