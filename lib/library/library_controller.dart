import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../playback/documents.dart';
import 'database.dart';
import 'library_backup.dart';
import 'library_relocation.dart';
import 'tag_repository.dart';
import 'filter_rule.dart';
import 'filter_repository.dart';
import 'playlist_repository.dart';
import 'scheduled_backup.dart';
import '../playback/playback_queue.dart';

export 'filter_rule.dart' show LibrarySort;

final libraryProvider = Provider<LibraryController?>((ref) => null);

class LibraryTrack {
  const LibraryTrack(this.song, this.location);
  final Song song;
  final String? location;
  bool get available => location != null;
  String get title =>
      song.title?.trim().isNotEmpty == true ? song.title! : song.name;
  ProbeTrack get probe => ProbeTrack(
    location: location ?? song.location,
    name: song.name,
    size: song.size,
    modified: song.modified,
  );
  QueueSong get queueSong => QueueSong(songId: song.id, track: probe);
}

class LibraryController extends ChangeNotifier {
  LibraryController(this.db, this.documents, {FilterRepository? filterStore})
    : tagsStore = TagRepository(db),
      playlistsStore = PlaylistRepository(db),
      filterStore = filterStore ?? FilterRepository(db);
  final LibraryDatabase db;
  final DocumentAccess documents;
  late final scheduledBackup = ScheduledLibraryBackup(db, documents);
  final TagRepository tagsStore;
  final PlaylistRepository playlistsStore;
  List<Playlist> playlists = [];
  Map<String, List<String>> playlistSongIds = {};
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
  final _filteredCache = <(LibrarySort, bool), List<LibraryTrack>>{};
  bool get filterSaving => _filterWritesPending > 0;

  List<LibraryTrack> get filterMatches => _matchedCache ??= List.unmodifiable(
    filterLoadError != null
        ? <LibraryTrack>[]
        : availableTracks.where(
            (t) => filterPreferences.rule.matches(
              tagIdsBySong[t.song.id] ?? const {},
            ),
          ),
  );

  List<LibraryTrack> get filtered => filterResults(
    order: filterPreferences.sort,
    descending: filterPreferences.descending,
  );

  List<LibraryTrack> filterResults({
    required LibrarySort order,
    required bool descending,
  }) {
    final key = (order, descending);
    if (_filteredCache[key] case final cached?) return cached;
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
    _sortTracks(rows, order, descending);
    return _filteredCache[key] = List.unmodifiable(rows);
  }

  void _invalidateFilter() {
    _matchedCache = null;
    _filteredCache.clear();
  }

  void searchFilter(String text) {
    filterQuery = text;
    _filteredCache.clear();
    _publish();
  }

  Future<void> updateFilter({
    FilterRule? rule,
    LibrarySort? order,
    bool? reverse,
    bool reset = false,
  }) {
    if (restoringBackup ||
        filterDeletingTag ||
        (filterLoadError != null && !reset)) {
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
  List<LibraryTrack>? _availabilitySource;
  Map<String, LibraryTrack> _availableById = const {};
  Map<String, LibraryTrack> get _availableTracksById {
    if (!identical(_availabilitySource, tracks)) {
      _availabilitySource = tracks;
      _availableById = {
        for (final track in tracks)
          if (track.available) track.song.id: track,
      };
    }
    return _availableById;
  }

  Iterable<LibraryTrack> get availableTracks => _availableTracksById.values;
  List<LibraryRoot> roots = [];
  List<Tag> tags = [];
  Map<String, Set<String>> tagIdsBySong = {};
  Map<String, int> tagCounts = {};
  String query = '';
  LibrarySort sort = LibrarySort.modified;
  bool descending = true;
  bool showMissing = false;
  bool scanning = false;
  bool choosing = false;
  bool restoringBackup = false;
  bool relocating = false;
  bool hashingBaselines = false;
  bool baselineCancelling = false;
  int baselineProcessed = 0;
  bool get directoryBusy =>
      scanning ||
      choosing ||
      restoringBackup ||
      relocating ||
      hashingBaselines ||
      _removeTask != null;
  bool _cancelled = false;
  bool _closed = false;
  int discovered = 0;
  int metadataReads = 0;
  String? scanningRoot;
  String? _message;
  String? get message => _message;
  Timer? _messageTimer;
  Future<void>? _scanTask;
  Future<bool>? _removeTask;
  Future<bool>? _restoreTask;
  Future<void>? _relocationTask;
  Future<void>? _baselineTask;
  Future<void>? _baselineCancellation;
  List<LibraryTrack>? _visibleCache;

  void _setMessage(String? value, {bool transient = false}) {
    _messageTimer?.cancel();
    _message = value;
    if (value != null && transient && !_closed) {
      _messageTimer = Timer(const Duration(seconds: 4), () {
        _message = null;
        _publish();
      });
    }
  }

  List<LibraryTrack> get visible {
    if (_visibleCache != null) return _visibleCache!;
    final needle = query.trim().toLowerCase();
    final rows =
        (showMissing
                ? tracks.where((track) => !track.available)
                : availableTracks)
            .where(
              (t) =>
                  needle.isEmpty ||
                  [
                    t.title,
                    t.song.name,
                    t.song.artist ?? '',
                    t.song.album ?? '',
                  ].any((v) => v.toLowerCase().contains(needle)),
            )
            .toList();
    _sortTracks(rows, sort, descending);
    return _visibleCache = List.unmodifiable(rows);
  }

  List<LibraryTrack> selectedTracks(Set<String> ids) {
    final rows = availableTracks.where((t) => ids.contains(t.song.id)).toList();
    _sortTracks(rows, sort, descending);
    return rows;
  }

  /// A full-library snapshot, independent of all page and persisted filters.
  /// Cache by the data snapshot, never by playback notifications.
  List<LibraryTrack>? _searchSource;
  final _searchResults = <(String, LibrarySort, bool), List<LibraryTrack>>{};

  List<LibraryTrack> searchTracks(
    String text, {
    LibrarySort order = LibrarySort.modified,
    bool descending = true,
  }) {
    final needle = text.trim().toLowerCase();
    if (!identical(_searchSource, tracks)) {
      _searchResults.clear();
      _searchSource = tracks;
    }
    final key = (needle, order, descending);
    if (_searchResults[key] case final cached?) return cached;
    final rows = availableTracks
        .where(
          (t) =>
              needle.isEmpty ||
              [
                t.title,
                t.song.name,
                t.song.artist ?? '',
                t.song.album ?? '',
              ].any((v) => v.toLowerCase().contains(needle)),
        )
        .toList();
    _sortTracks(rows, order, descending);
    if (_searchResults.length >= 8) {
      _searchResults.remove(_searchResults.keys.first);
    }
    return _searchResults[key] = List.unmodifiable(rows);
  }

  void _sortTracks(List<LibraryTrack> rows, LibrarySort sort, bool descending) {
    if (sort == LibrarySort.modified) {
      rows.sort((a, b) {
        final left = a.song.modified;
        final right = b.song.modified;
        if (left == null && right != null) return 1;
        if (right == null && left != null) return -1;
        final time = left == null ? 0 : left.compareTo(right!);
        if (time != 0) return descending ? -time : time;
        final name = a.song.name.compareTo(b.song.name);
        return name != 0 ? name : a.song.id.compareTo(b.song.id);
      });
      return;
    }
    String value(LibraryTrack t) => switch (sort) {
      LibrarySort.title => t.title,
      LibrarySort.artist => t.song.artist ?? '',
      LibrarySort.album => t.song.album ?? '',
      LibrarySort.name => t.song.name,
      LibrarySort.modified => throw StateError('handled above'),
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
    // Import legacy directory bookmarks; no audio is opened at startup.
    for (final root in await documents.roots()) {
      await _addRoot(root);
    }
    await playlistsStore.ensureFavorites();
    await reload();
    await _loadFilter();
  }

  Future<void> _loadFilter() async {
    filterLoadError = null;
    filterSaveError = null;
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

  Future<bool> restoreBackup(
    LibraryBackup backup,
    File recoveryFile, {
    required bool trustedLocations,
  }) {
    if (_closed || directoryBusy || filterDeletingTag) {
      throw StateError('请等待当前曲库操作结束');
    }
    restoringBackup = true;
    final task = _restoreBackup(backup, recoveryFile, trustedLocations);
    _restoreTask = task;
    _publish();
    return task;
  }

  Future<bool> _restoreBackup(
    LibraryBackup backup,
    File recoveryFile,
    bool trustedLocations,
  ) async {
    try {
      await _filterWrites;
      // All current bookmarks have already been imported into the database.
      // Clearing the legacy cache prevents old directories returning on restart.
      await documents.clearDirectoryBookmarks();
      await backup.restore(
        db,
        recoveryFile: recoveryFile,
        trustedLocations: trustedLocations,
      );
      try {
        await reload(publish: false);
        await _loadFilter();
        return true;
      } catch (error, stack) {
        debugPrint('备份已恢复，重新加载曲库失败：$error\n$stack');
        return false;
      }
    } finally {
      restoringBackup = false;
      _restoreTask = null;
      _publish();
    }
  }

  Future<void> runRelocation(
    Future<void> Function(LibraryRelocation relocation) work,
  ) {
    if (_closed || directoryBusy) {
      throw StateError('请等待当前曲库操作结束');
    }
    relocating = true;
    final task = _runRelocation(work);
    _relocationTask = task;
    _publish();
    return task;
  }

  Future<void> _runRelocation(
    Future<void> Function(LibraryRelocation relocation) work,
  ) async {
    try {
      await work(LibraryRelocation(db, documents));
      await reload();
    } finally {
      relocating = false;
      _relocationTask = null;
      _publish();
    }
  }

  void startBaselines() {
    if (_closed || directoryBusy) return;
    hashingBaselines = true;
    baselineProcessed = 0;
    _setMessage(null);
    _baselineTask = _saveBaselines();
    _publish();
  }

  Future<void> _saveBaselines() async {
    try {
      final (saved, failed) = await LibraryRelocation(db, documents)
          .saveBaselines(
            cancelled: () => baselineCancelling,
            progress: (count) {
              baselineProcessed = count;
              if (count % 16 == 0) _publish();
            },
          );
      await reload(publish: false);
      _setMessage(
        '${baselineCancelling ? '已取消。' : ''}新增保存 $saved 首指纹。'
        '${failed == 0 ? '' : '另有 $failed 首未能读取。'}',
        transient: true,
      );
    } catch (error, stack) {
      debugPrint('保存歌曲指纹失败：$error\n$stack');
      _setMessage('保存指纹失败，请检查存储空间后重试。', transient: true);
    } finally {
      await _baselineCancellation;
      hashingBaselines = false;
      baselineCancelling = false;
      _baselineCancellation = null;
      _baselineTask = null;
      _publish();
    }
  }

  void cancelBaselines() {
    if (!hashingBaselines || baselineCancelling) return;
    baselineCancelling = true;
    _baselineCancellation = documents.cancelMusicHash().catchError(
      (Object error) => debugPrint('取消歌曲指纹读取：$error'),
    );
    _publish();
  }

  Set<String> tagsForSong(String songId) =>
      Set.unmodifiable(tagIdsBySong[songId] ?? const <String>{});

  LibraryTrack? availableTrack(String songId) => _availableTracksById[songId];

  ProbeTrack? resolveSong(String songId) => availableTrack(songId)?.probe;

  List<LibraryTrack> playlistTracks(String id) {
    final list = playlists.where((p) => p.id == id).firstOrNull;
    if (list?.kind == 'smart') {
      return matchingTracks(smartPreferences(list!));
    }
    final byId = _availableTracksById;
    return List.unmodifiable([
      for (final songId in playlistSongIds[id] ?? const <String>[])
        ?byId[songId],
    ]);
  }

  FilterPreferences smartPreferences(Playlist list) {
    final preferences = PlaylistRepository.preferences(list);
    if (!tags
        .map((t) => t.id)
        .toSet()
        .containsAll(preferences.rule.referencedIds)) {
      throw const FormatException('智能歌单引用的标签不存在');
    }
    return preferences;
  }

  List<LibraryTrack> matchingTracks(FilterPreferences preferences) {
    final rows = availableTracks
        .where(
          (t) => preferences.rule.matches(tagIdsBySong[t.song.id] ?? const {}),
        )
        .toList();
    _sortTracks(rows, preferences.sort, preferences.descending);
    return List.unmodifiable(rows);
  }

  Future<String> createSmartPlaylist(
    String name,
    FilterPreferences preferences,
  ) async {
    final id = await playlistsStore.createSmart(name, preferences);
    await reloadPlaylists();
    return id;
  }

  Future<void> editSmartPlaylist(
    String id,
    FilterPreferences preferences,
  ) async {
    await playlistsStore.editSmart(id, preferences);
    await reloadPlaylists();
  }

  /// Compare actual available membership, including the loss of song-tag links.
  /// Preview fails closed if any stored rule is unreadable.
  List<String> tagDeletionEffects(String id) {
    if (filterLoadError != null) throw StateError(filterLoadError!);
    final rules = <String, FilterPreferences>{
      '当前筛选': filterPreferences,
      for (final list in playlists.where((p) => p.kind == 'smart'))
        '智能歌单“${list.name}”': smartPreferences(list),
    };
    return [
      for (final entry in rules.entries)
        if (entry.value.rule.referencedIds.contains(id))
          _tagRuleEffect(entry.key, entry.value.rule, id),
    ];
  }

  String _tagRuleEffect(String name, FilterRule rule, String id) {
    final next = rule.without(id);
    var before = 0;
    var after = 0;
    for (final track in availableTracks) {
      final tags = tagIdsBySong[track.song.id] ?? const <String>{};
      if (rule.matches(tags)) before++;
      if (next.matches({...tags}..remove(id))) after++;
    }
    final boxes = [
      if (rule.allTagIds.contains(id)) '全部具备',
      if (rule.anyTagIds.contains(id)) '任一具备',
      if (rule.excludedTagIds.contains(id)) '排除标签',
    ];
    return '$name：$before → $after 首（${boxes.join('、')}）';
  }

  Future<void> reloadPlaylists() async {
    final snapshot = await playlistsStore.load();
    playlists = snapshot.playlists;
    playlistSongIds = snapshot.songIds;
    _publish();
  }

  Future<String> createPlaylist(String name, Iterable<String> songIds) async {
    final id = await playlistsStore.create(name, songIds);
    await reloadPlaylists();
    return id;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await playlistsStore.rename(id, name);
    await reloadPlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    await playlistsStore.delete(id);
    await reloadPlaylists();
  }

  Future<void> addPlaylistSongs(String id, Iterable<String> songs) async {
    await playlistsStore.add(id, songs);
    await reloadPlaylists();
  }

  Future<void> addSongsToPlaylists(
    Iterable<String> ids,
    Iterable<String> songs,
  ) async {
    await playlistsStore.addToMany(ids, songs);
    await reloadPlaylists();
  }

  bool isFavorite(String songId) {
    final favorite = playlists
        .where(
          (list) =>
              list.kind == 'regular' && list.nameKey == favoritesPlaylistName,
        )
        .firstOrNull;
    return favorite != null &&
        playlistSongIds[favorite.id]?.contains(songId) == true;
  }

  Future<void> toggleFavorite(String songId) async {
    await playlistsStore.toggleFavorite(songId);
    await reloadPlaylists();
  }

  Future<void> removePlaylistSongs(String id, Iterable<String> songs) async {
    await playlistsStore.remove(id, songs);
    await reloadPlaylists();
  }

  Future<void> reorderPlaylist(String id, List<String> ordered) async {
    final saved = playlistSongIds[id] ?? const <String>[];
    final moved = ordered.toSet();
    if (moved.length != ordered.length || !saved.toSet().containsAll(moved)) {
      throw ArgumentError('歌曲列表已变化，请重新排序');
    }
    // Keep hidden songs in their saved slots so they reappear in the playlist.
    var index = 0;
    await playlistsStore.reorder(id, [
      for (final songId in saved)
        moved.contains(songId) ? ordered[index++] : songId,
    ]);
    await reloadPlaylists();
  }

  int countForTag(String tagId) => tagCounts[tagId] ?? 0;

  List<LibraryTrack> tracksForTag(String tagId) => List.unmodifiable(
    availableTracks.where(
      (track) => tagIdsBySong[track.song.id]?.contains(tagId) == true,
    ),
  );

  Future<void> reloadTags({bool withPlaylists = false}) async {
    final snapshot = await tagsStore.load();
    final saved = withPlaylists ? await playlistsStore.load() : null;
    tags = snapshot.tags;
    tagIdsBySong = snapshot.bySong;
    tagCounts = _countTags(snapshot.bySong);
    if (saved != null) {
      playlists = saved.playlists;
      playlistSongIds = saved.songIds;
    }
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
      // Publish pruned rules and tags together, avoiding an intermediate frame
      // in which a valid saved rule appears to reference a missing tag.
      await reloadTags(withPlaylists: true);
    } finally {
      filterDeletingTag = false;
      _publish();
    }
  }

  Future<void> changeSongTags(
    String tagId,
    Iterable<String> songIds, {
    required bool add,
  }) => editSongTags(
    songIds,
    add: add ? {tagId} : const {},
    remove: add ? const {} : {tagId},
  );

  Future<void> editSongTags(
    Iterable<String> songIds, {
    required Set<String> add,
    required Set<String> remove,
  }) async {
    if (add.isEmpty && remove.isEmpty) return;
    await tagsStore.editSongs(songIds, add: add, remove: remove);
    await reloadTags();
  }

  Future<void> _addRoot(String root) => db
      .into(db.libraryRoots)
      .insert(
        LibraryRootsCompanion.insert(location: root),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> reload({bool publish = true}) async {
    final nextRoots = await db.select(db.libraryRoots).get();
    final songs = await db.select(db.songs).get();
    final locations = await (db.select(
      db.songLocations,
    )..where((r) => r.available.equals(true))).get();
    final bySong = <String, String>{};
    final unavailableRoots = nextRoots
        .where((r) => !r.accessible)
        .map((r) => r.location)
        .toSet();
    for (final row in locations) {
      if (!unavailableRoots.contains(row.root)) {
        bySong.putIfAbsent(row.songId, () => row.location);
      }
    }
    final tagSnapshot = await tagsStore.load();
    final playlistSnapshot = await playlistsStore.load();
    roots = nextRoots;
    tracks = [for (final song in songs) LibraryTrack(song, bySong[song.id])];
    _visibleCache = null;
    tags = tagSnapshot.tags;
    tagIdsBySong = tagSnapshot.bySong;
    tagCounts = _countTags(tagSnapshot.bySong);
    playlists = playlistSnapshot.playlists;
    playlistSongIds = playlistSnapshot.songIds;
    _invalidateFilter();
    if (publish) _publish();
  }

  Map<String, int> _countTags(Map<String, Set<String>> bySong) {
    final counts = <String, int>{};
    for (final songId in _availableTracksById.keys) {
      for (final id in bySong[songId] ?? const <String>{}) {
        counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  Future<void> chooseDirectory() async {
    if (_closed || directoryBusy) return;
    choosing = true;
    _publish();
    String? root;
    try {
      root = await documents.pickDirectory();
      if (root != null) {
        if (roots.any(
          (row) => row.location == root && row.requiresReselection,
        )) {
          _setMessage('这个目录已在列表中，请在管理目录中点“重新定位”。');
          return;
        }
        await _addRoot(root);
        await reload();
      }
    } catch (e) {
      _setMessage('目录选择失败：$e', transient: true);
    } finally {
      choosing = false;
      _publish();
    }
    if (root != null) await scan([root]);
  }

  Future<bool> removeDirectory(String root) {
    if (_closed ||
        directoryBusy ||
        !roots.any((directory) => directory.location == root)) {
      return Future.value(false);
    }
    final task = _removeDirectory(root);
    _removeTask = task;
    _publish();
    return task;
  }

  Future<bool> _removeDirectory(String root) async {
    try {
      // Clear the legacy bookmark first so initialization cannot reimport it.
      // The database still holds the directory if the transaction fails.
      await documents.forgetDirectory(root);
      await db.transaction(() async {
        await (db.delete(
          db.songLocations,
        )..where((row) => row.root.equals(root))).go();
        await (db.delete(
          db.libraryRoots,
        )..where((row) => row.location.equals(root))).go();
      });
      _setMessage(null);
      await reload();
      return true;
    } catch (_) {
      _setMessage('目录列表更新失败，请重试。', transient: true);
      return false;
    } finally {
      _removeTask = null;
      _publish();
    }
  }

  void cancelScan() {
    if (scanning) {
      _cancelled = true;
      _setMessage('正在取消，已提交的目录仍保留…');
      _publish();
    }
  }

  Future<void> scan([List<String>? selected]) {
    if (_closed || directoryBusy) return Future.value();
    final pending = {
      for (final root in roots)
        if (root.requiresReselection) root.location,
    };
    final targets = (selected ?? roots.map((root) => root.location))
        .where((root) => !pending.contains(root))
        .toList();
    if (targets.isEmpty) return Future.value();
    return _scanTask = _scan(targets);
  }

  Future<void> _scan(List<String> selected) async {
    scanning = true;
    _cancelled = false;
    discovered = 0;
    metadataReads = 0;
    _setMessage(null);
    _publish();
    var failures = 0;
    String? result;
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
                fileSha256:
                    old != null &&
                        file.size != null &&
                        file.modified != null &&
                        old.size == file.size &&
                        old.modified == file.modified
                    ? old.fileSha256
                    : null,
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
      result = _cancelled
          ? '扫描已取消；未完成目录的原曲库保持不变。'
          : '扫描结束：发现 $discovered 首，读取元数据 $metadataReads 首，失败目录 $failures 个。';
    } catch (e) {
      result = '扫描失败，已保留原曲库：$e';
    } finally {
      scanningRoot = null;
      try {
        await reload();
      } catch (e) {
        result = '曲库读取失败，扫描已停止：$e';
      }
      scanning = false;
      _setMessage(result, transient: true);
      _publish();
    }
  }

  Future<void> shutdown() async {
    _closed = true;
    _cancelled = true;
    _messageTimer?.cancel();
    cancelBaselines();
    await _scanTask;
    await _removeTask;
    await _restoreTask;
    await _relocationTask;
    await _baselineTask;
    await _filterWrites;
    await scheduledBackup.close();
    await db.close();
    super.dispose();
  }
}
