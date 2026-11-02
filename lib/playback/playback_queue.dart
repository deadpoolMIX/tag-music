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
  final List<String> _remaining = [];
  final Set<String> _visited = {};
  final List<String> _history = [];
  int _historyIndex = -1;
  String? _currentId;
  // Priority detours must not move the resume point of the ordinary sequence.
  String? _baseId;
  PlaybackMode _mode = PlaybackMode.shuffle;

  List<QueueEntry> get entries => UnmodifiableListView(_entries);
  List<String> get priorityIds => UnmodifiableListView(_priority);
  PlaybackMode get mode => _mode;
  int get index => _entries.indexWhere((e) => e.entryId == _currentId);
  QueueEntry? get current => index < 0 ? null : _entries[index];
  bool get canPrevious => _mode == PlaybackMode.shuffle
      ? _historyIndex > 0
      : index > 0 || (_wraps && _entries.isNotEmpty);
  bool get canNext =>
      _entries.isNotEmpty &&
      (_mode != PlaybackMode.sequential ||
          _priority.isNotEmpty ||
          _linearCandidates(const {}).isNotEmpty);
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
    _remaining.clear();
    _visited.clear();
    _history.clear();
    _historyIndex = -1;
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
    _history
      ..clear()
      ..addAll([?_currentId]);
    _historyIndex = _history.length - 1;
    final priority = _priority.toSet();
    _remaining
      ..clear()
      ..addAll(
        _entries
            .map((e) => e.entryId)
            .where((id) => id != _currentId && !priority.contains(id)),
      )
      ..shuffle(_random);
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
    return _choose(entryId, base: !_priority.contains(entryId));
  }

  QueueEntry _choose(String id, {required bool base, bool record = true}) {
    _currentId = id;
    if (base) _baseId = id;
    _priority.remove(id);
    _remaining.remove(id);
    _visited.add(id);
    if (record) {
      if (_historyIndex + 1 < _history.length) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(id);
      // Bound continuous playback history to two queue-lengths. No stale IDs
      // or unbounded session growth; navigation within history adds no visits.
      final limit = _entries.isEmpty ? 2 : _entries.length * 2;
      final excess = _history.length - limit;
      if (excess > 0) _history.removeRange(0, excess);
      _historyIndex = _history.length - 1;
    }
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
    if (_mode == PlaybackMode.shuffle) {
      while (_historyIndex + 1 < _history.length) {
        final id = _history[++_historyIndex];
        if (!excluded.contains(id)) {
          return _choose(id, base: false, record: false);
        }
      }
    }
    final priority = _priority
        .where((id) => !excluded.contains(id))
        .firstOrNull;
    if (priority != null) return _choose(priority, base: false);
    if (_mode == PlaybackMode.shuffle) {
      var candidates = _remaining.where((id) => !excluded.contains(id));
      if (candidates.isEmpty) {
        _visited.clear();
        _remaining
          ..clear()
          ..addAll(_entries.map((e) => e.entryId))
          ..shuffle(_random);
        candidates = _remaining.where((id) => !excluded.contains(id));
      }
      final id = candidates.firstOrNull;
      return id == null ? null : _choose(id, base: true);
    }
    var candidates = _linearCandidates(excluded);
    if (candidates.isEmpty && _wraps) {
      _visited.clear();
      candidates = _entries
          .map((e) => e.entryId)
          .where((id) => !excluded.contains(id))
          .toList();
    }
    return candidates.isEmpty ? null : _choose(candidates.first, base: true);
  }

  QueueEntry? previous() {
    if (!canPrevious) return null;
    if (_mode == PlaybackMode.shuffle) {
      return _choose(_history[--_historyIndex], base: false, record: false);
    }
    final target = index > 0 ? index - 1 : _entries.length - 1;
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
  }

  /// Removing current selects its displayed successor, else predecessor.
  /// The caller preserves play/pause intent and releases the old media.
  void remove(String entryId) {
    final at = _entries.indexWhere((e) => e.entryId == entryId);
    if (at < 0) return;
    final wasCurrent = _currentId == entryId;
    _entries.removeAt(at);
    _priority.remove(entryId);
    _remaining.remove(entryId);
    _visited.remove(entryId);
    final beforeCursor = _history
        .take(_historyIndex + 1)
        .where((id) => id != entryId)
        .length;
    _history.removeWhere((id) => id == entryId);
    _historyIndex = beforeCursor - 1;
    if (_entries.isEmpty) {
      clear();
      return;
    }
    if (_baseId == entryId) {
      _baseId = at == 0 ? null : _entries[at - 1].entryId;
    }
    if (wasCurrent) {
      final id = _entries[min(at, _entries.length - 1)].entryId;
      _choose(id, base: !_priority.contains(id));
    }
  }
}
