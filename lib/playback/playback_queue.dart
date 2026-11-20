import 'dart:collection';
import 'dart:math';

import 'package:uuid/uuid.dart';

import 'documents.dart';

enum PlaybackMode { sequential, repeatAll, repeatOne, shuffle }

/// A library UUID plus display/location snapshot. Location is resolved again
/// before opening; membership does not follow later library/filter changes.
class QueueSong {
  const QueueSong({required this.songId, required this.track});
  final String songId;
  final ProbeTrack track;
}

class QueueEntry {
  QueueEntry(this.song) : entryId = const Uuid().v4();
  final String entryId;
  final QueueSong song;
}

/// In-memory traversal only. No player, database, file handles or timers.
class PlaybackQueue {
  PlaybackQueue({Random? random}) : _random = random ?? Random();
  final Random _random;
  List<QueueEntry> _entries = [];
  final List<String> _priority = [];
  final Set<String> _visited = {};
  String? _currentId;
  // Priority detours must not move the resume point of the ordinary sequence.
  String? _baseId;
  PlaybackMode _mode = PlaybackMode.shuffle;

  List<QueueEntry> get entries => UnmodifiableListView(_entries);
  List<String> get priorityIds => UnmodifiableListView(_priority);
  PlaybackMode get mode => _mode;
  int get index => _entries.indexWhere((e) => e.entryId == _currentId);
  QueueEntry? get current => index < 0 ? null : _entries[index];
  bool get canPrevious => _entries.isNotEmpty;
  bool get canNext => _entries.isNotEmpty;
  bool get _wraps =>
      _mode == PlaybackMode.repeatAll || _mode == PlaybackMode.repeatOne;

  void replace(List<QueueSong> songs, int target) {
    if (songs.isNotEmpty && (target < 0 || target >= songs.length)) {
      throw RangeError.index(target, songs);
    }
    clear();
    _entries = songs.map(QueueEntry.new).toList();
    if (_entries.isEmpty) return;
    _currentId = _entries[target].entryId;
    _baseId = _currentId;
    _resetTraversal();
  }

  void clear() {
    _entries = [];
    _currentId = null;
    _baseId = null;
    _priority.clear();
    _visited.clear();
  }

  void setMode(PlaybackMode value) {
    if (_mode == value) return;
    _mode = value;
    _baseId = _currentId;
    _resetTraversal();
  }

  void _resetTraversal() {
    _visited
      ..clear()
      ..addAll([?_currentId]);
    if (_mode == PlaybackMode.shuffle && current != null) {
      final selected = current!;
      final pending = {for (final entry in _entries) entry.entryId: entry};
      final priority = _priority.toSet();
      final rest =
          _entries
              .where(
                (entry) =>
                    entry.entryId != selected.entryId &&
                    !priority.contains(entry.entryId),
              )
              .toList()
            ..shuffle(_random);
      _entries = [selected, ..._priority.map((id) => pending[id]!), ...rest];
    }
  }

  /// Insert behind the existing FIFO priority block, never in front of it.
  void add(List<QueueSong> songs) {
    if (songs.isEmpty) return;
    final added = songs.map(QueueEntry.new).toList();
    if (_entries.isEmpty) {
      _entries = added;
      _currentId = added.first.entryId;
      _baseId = _currentId;
      _priority.addAll(added.skip(1).map((e) => e.entryId));
      _resetTraversal();
      return;
    }
    final positions = {
      for (var i = 0; i < _entries.length; i++) _entries[i].entryId: i,
    };
    final after = _priority.fold(
      index,
      (int at, id) => max(at, positions[id]!),
    );
    _entries.insertAll(after + 1, added);
    _priority.addAll(added.map((e) => e.entryId));
  }

  QueueEntry? select(String entryId) {
    if (!_entries.any((e) => e.entryId == entryId)) return null;
    return _choose(
      entryId,
      base: _mode == PlaybackMode.shuffle || !_priority.contains(entryId),
    );
  }

  QueueEntry _choose(String id, {required bool base}) {
    _currentId = id;
    if (base) _baseId = id;
    _priority.remove(id);
    _visited.add(id);
    return current!;
  }

  List<String> _linearCandidates(Set<String> excluded) {
    final anchor = _entries.indexWhere((e) => e.entryId == _baseId);
    return _entries
        .skip(anchor + 1)
        .map((e) => e.entryId)
        .where(
          (id) =>
              (_currentId == _baseId || !_visited.contains(id)) &&
              !excluded.contains(id),
        )
        .toList();
  }

  QueueEntry? next({bool natural = false, Set<String> excluded = const {}}) {
    if (_entries.isEmpty) return null;
    if (natural &&
        _mode == PlaybackMode.repeatOne &&
        _currentId != null &&
        !excluded.contains(_currentId)) {
      return current;
    }
    final priority = _priority
        .where((id) => !excluded.contains(id))
        .firstOrNull;
    if (_mode != PlaybackMode.shuffle && priority != null) {
      return _choose(priority, base: false);
    }
    var candidates = _linearCandidates(excluded);
    if (candidates.isEmpty && (_wraps || _mode == PlaybackMode.shuffle)) {
      _visited.clear();
      if (_mode == PlaybackMode.shuffle) _entries.shuffle(_random);
      candidates = _entries
          .map((e) => e.entryId)
          .where((id) => !excluded.contains(id))
          .toList();
    }
    return candidates.isEmpty ? null : _choose(candidates.first, base: true);
  }

  // The transport buttons follow the displayed order, including its seam.
  QueueEntry? nextManual() => _step(1);

  QueueEntry? previous() => _step(-1);

  QueueEntry? _step(int direction) {
    if (_entries.isEmpty) return null;
    final target = (index + direction) % _entries.length;
    return _choose(_entries[target].entryId, base: true);
  }

  void reorder(List<String> orderedIds) {
    final byId = {for (final e in _entries) e.entryId: e};
    if (orderedIds.length != byId.length ||
        orderedIds.toSet().length != byId.length ||
        !orderedIds.every(byId.containsKey)) {
      throw ArgumentError('重排必须包含每个现有条目一次');
    }
    _entries = orderedIds.map((id) => byId[id]!).toList();
    final pending = _priority.toSet();
    _priority
      ..clear()
      ..addAll(orderedIds.where(pending.contains));
    if (_mode == PlaybackMode.shuffle) {
      _baseId = _currentId;
      _visited
        ..clear()
        ..addAll([?_currentId]);
    }
  }

  /// Removing current selects its displayed successor, else predecessor.
  /// The caller preserves play/pause intent and releases the old media.
  void remove(String entryId) {
    final at = _entries.indexWhere((e) => e.entryId == entryId);
    if (at < 0) return;
    final wasCurrent = _currentId == entryId;
    _entries.removeAt(at);
    _priority.remove(entryId);
    _visited.remove(entryId);
    if (_entries.isEmpty) {
      clear();
      return;
    }
    if (_baseId == entryId) {
      _baseId = at == 0 ? null : _entries[at - 1].entryId;
    }
    if (wasCurrent) {
      final id = _entries[min(at, _entries.length - 1)].entryId;
      _choose(
        id,
        base: _mode == PlaybackMode.shuffle || !_priority.contains(id),
      );
    }
  }
}
