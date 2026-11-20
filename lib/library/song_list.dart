import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fast_scrollbar.dart';
import '../core/reorder_handle.dart';
import '../playback/playback_controller.dart';
import 'library_controller.dart';

import 'track_cover.dart';
import 'song_information.dart';
import 'playlist_actions.dart';
import 'tags_page.dart';

/// Every owner supplies its complete ordered membership, separately from search.
/// Selection and scrolling belong to this mounted page, never the controller.
class SongList extends StatefulWidget {
  const SongList({
    required this.library,
    required this.playback,
    required this.source,
    required this.rows,
    this.enabled = true,
    this.reordering = false,
    this.onReorder,
    this.onRemove,
    this.scope = 'library',
    this.emptyText = '没有匹配的歌曲',
    this.onLocated,
    this.resetScrollKey,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  final List<LibraryTrack> source;
  final List<LibraryTrack> rows;
  final bool enabled;
  final bool reordering;
  final void Function(int, int)? onReorder;
  final Future<void> Function(Set<String>)? onRemove;
  final String scope;
  final String emptyText;

  /// A query change can reset scrolling without discarding hidden selections.
  final Object? resetScrollKey;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  /// Optional real-application observation; widget virtual time is not a device sample.
  final void Function(String songId, int elapsedMicroseconds)? onLocated;
  @override
  State<SongList> createState() => _SongListState();
}

class _SongListState extends State<SongList> {
  final _scroll = ScrollController();
  final _selectionFocus = FocusNode(debugLabel: 'song-list-selection');
  final _selected = <String>{};
  bool _selecting = false;
  String? _highlight;
  Timer? _timer;
  int _locateToken = 0;
  String? _currentId;
  late Map<String, int> _indices;

  @override
  void initState() {
    super.initState();
    _indexRows();
  }

  void _indexRows() {
    _indices = {
      for (var i = 0; i < widget.rows.length; i++) widget.rows[i].song.id: i,
    };
  }

  @override
  void didUpdateWidget(SongList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.reordering && widget.reordering) {
      // Reordering and selection are exclusive modes. In particular, a held
      // drag handle must not be claimed by the row's long-press recognizer.
      _selected.clear();
      _selecting = false;
    }
    final members = widget.source.map((t) => t.song.id).toSet();
    _selected.removeWhere((id) => !members.contains(id));
    final rowsChanged = !identical(oldWidget.rows, widget.rows);
    final resetScroll = oldWidget.resetScrollKey != widget.resetScrollKey;
    if (rowsChanged) {
      _indexRows();
    }
    if (rowsChanged || resetScroll) {
      _invalidateLocate();
    }
    if (resetScroll) {
      final token = _locateToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && token == _locateToken && _scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }
  }

  void _invalidateLocate() {
    _locateToken++;
    _timer?.cancel();
    _highlight = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _selectionFocus.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      _selecting = true;
      if (!_selected.add(id)) _selected.remove(id);
    });
    _selectionFocus.requestFocus();
  }

  void _exitSelection() => setState(() {
    _selected.clear();
    _selecting = false;
  });

  List<LibraryTrack> _snapshot() => List.unmodifiable(
    widget.source.where((t) => _selected.contains(t.song.id)),
  );

  double _extent(BuildContext context) {
    double height(double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: '歌曲Ag',
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: size),
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final result = painter.height;
      painter.dispose();
      return result;
    }

    return math.max(60, math.max(48, height(16) + height(12) + 12));
  }

  Future<void> _locate(String id, double extent) async {
    final index = _indices[id];
    if (index == null || !_scroll.hasClients) return;
    final token = ++_locateToken;
    final elapsed = Stopwatch()..start();
    _timer?.cancel();
    await _scroll.animateTo(
      (index * extent).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    if (!mounted ||
        token != _locateToken ||
        widget.playback.currentSongId != id) {
      return;
    }
    setState(() => _highlight = id);
    await WidgetsBinding.instance.endOfFrame;
    elapsed.stop();
    if (!mounted ||
        token != _locateToken ||
        widget.playback.currentSongId != id) {
      return;
    }
    widget.onLocated?.call(id, elapsed.elapsedMicroseconds);
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  Widget _toolbar(double maxHeight) {
    final visibleIds = widget.rows.map((t) => t.song.id).toSet();
    final visibleSelected = _selected.where(visibleIds.contains).length;
    final hiddenSelected = _selected.length - visibleSelected;
    final unavailable = _snapshot().where((t) => !t.available).length;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text('已选 ${_selected.length} 首'),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _exitSelection,
                    icon: const Icon(Icons.close),
                    label: const Text('退出多选'),
                  ),
                ],
              ),
              if (hiddenSelected > 0 || unavailable > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    [
                      if (hiddenSelected > 0)
                        '当前结果已选 $visibleSelected 首，另有 $hiddenSelected 首在当前结果外。',
                      if (unavailable > 0) '已选中 $unavailable 首失联歌曲，加入队列时会跳过。',
                    ].join(' '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Tooltip(
                      message: '全选当前结果，保留其他结果中的选择',
                      child: TextButton(
                        onPressed:
                            !widget.enabled ||
                                visibleSelected == visibleIds.length
                            ? null
                            : () =>
                                  setState(() => _selected.addAll(visibleIds)),
                        child: const Text('全选'),
                      ),
                    ),
                    TextButton(
                      onPressed: !widget.enabled || visibleSelected == 0
                          ? null
                          : () =>
                                setState(() => _selected.removeAll(visibleIds)),
                      child: const Text('取消当前结果选择'),
                    ),
                    TextButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      child: const Text('清空选择'),
                    ),
                    TextButton(
                      key: const ValueKey('batch-tags'),
                      onPressed: !widget.enabled || _selected.isEmpty
                          ? null
                          : () {
                              final snapshot = _snapshot();
                              showTagActions(
                                context,
                                widget.library,
                                snapshot.map((t) => t.song.id).toSet(),
                              );
                            },
                      child: const Text('批量编辑标签'),
                    ),
                    TextButton(
                      key: ValueKey('enqueue-${widget.scope}-selected'),
                      onPressed:
                          !widget.enabled ||
                              !_snapshot().any((t) => t.available)
                          ? null
                          : () {
                              final snapshot = _snapshot()
                                  .where((t) => t.available)
                                  .map((t) => t.queueSong)
                                  .toList();
                              widget.playback.addToQueue(snapshot);
                            },
                      child: const Text('加入队列'),
                    ),
                    TextButton(
                      key: const ValueKey('batch-add-playlist'),
                      onPressed: !widget.enabled || _selected.isEmpty
                          ? null
                          : () {
                              final ids = _snapshot()
                                  .map((t) => t.song.id)
                                  .toList();
                              addToPlaylist(context, widget.library, ids);
                            },
                      child: const Text('添加到歌单'),
                    ),
                    TextButton(
                      onPressed: !widget.enabled || _selected.isEmpty
                          ? null
                          : () {
                              final ids = _snapshot()
                                  .map((t) => t.song.id)
                                  .toList();
                              savePlaylist(context, widget.library, ids);
                            },
                      child: const Text('保存歌单'),
                    ),
                    if (widget.onRemove != null)
                      TextButton(
                        onPressed: !widget.enabled || _selected.isEmpty
                            ? null
                            : () {
                                final ids = _snapshot()
                                    .map((t) => t.song.id)
                                    .toSet();
                                widget.onRemove!(ids);
                              },
                        child: const Text('移除所选歌曲'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.playback,
    builder: (context, _) {
      final current = widget.playback.currentSongId;
      if (_currentId != current) {
        _invalidateLocate();
        _currentId = current;
      }
      final extent = _extent(context);
      final canLocate = current != null && _indices.containsKey(current);
      Widget row(BuildContext context, int index) {
        final track = widget.rows[index];
        return SongRow(
          key: ValueKey(
            widget.scope == 'library' || widget.scope == 'search'
                ? track.song.id
                : '${widget.scope}-song-${track.song.id}',
          ),
          track: track,
          library: widget.library,
          playback: widget.playback,
          selected: _selecting && _selected.contains(track.song.id),
          selecting: _selecting,
          highlighted: _highlight == track.song.id,
          enabled: widget.enabled,
          extent: extent,
          reorderIndex: widget.reordering && !_selecting ? index : null,
          queueKey: ValueKey('enqueue-${widget.scope}-${track.song.id}'),
          onSelect: () => _toggle(track.song.id),
          onTap: () {
            if (_selecting) {
              _toggle(track.song.id);
              return;
            }
            final snapshot = widget.rows
                .where((t) => t.available)
                .map((t) => t.queueSong)
                .toList();
            final target = snapshot.indexWhere(
              (t) => t.songId == track.song.id,
            );
            if (target >= 0) widget.playback.playSongs(snapshot, target);
          },
        );
      }

      return CallbackShortcuts(
        bindings: {
          if (_selecting)
            const SingleActivator(LogicalKeyboardKey.escape): _exitSelection,
        },
        child: Focus(
          focusNode: _selectionFocus,
          skipTraversal: true,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                if (_selecting) _toolbar(constraints.maxHeight * .45),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, listConstraints) {
                      final desktop =
                          Theme.of(context).platform == TargetPlatform.windows;
                      final reordering =
                          widget.reordering &&
                          !_selecting &&
                          widget.onReorder != null;
                      final rowsHeight = widget.rows.length * extent;
                      final showRail = desktop
                          ? rowsHeight + (reordering ? 0 : 64) >
                                listConstraints.maxHeight
                          : rowsHeight > listConstraints.maxHeight * 1.75;
                      // The edge can reuse the row's outer padding without
                      // covering the menu or reorder handle.
                      final gutter = showRail ? FastScrollbar.gutter : 0.0;
                      final scrollKey = PageStorageKey((
                        widget.scope,
                        widget.key,
                      ));

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.rows.isEmpty)
                            Center(child: Text(widget.emptyText))
                          else
                            CoverScrollRegion(
                              cache: widget.playback.documents.coverCache,
                              child: FastScrollbar(
                                controller: _scroll,
                                visible: showRail,
                                child: reordering
                                    ? ReorderableListView.builder(
                                        key: scrollKey,
                                        scrollController: _scroll,
                                        keyboardDismissBehavior:
                                            widget.keyboardDismissBehavior,
                                        itemExtent: extent,
                                        buildDefaultDragHandles: false,
                                        itemCount: widget.rows.length,
                                        padding: EdgeInsets.only(right: gutter),
                                        itemBuilder: row,
                                        onReorderItem: widget.onReorder!,
                                      )
                                    : ListView.builder(
                                        key: scrollKey,
                                        controller: _scroll,
                                        keyboardDismissBehavior:
                                            widget.keyboardDismissBehavior,
                                        itemExtent: extent,
                                        itemCount: widget.rows.length,
                                        padding: EdgeInsets.only(
                                          right: gutter,
                                          bottom: 64,
                                        ),
                                        itemBuilder: row,
                                      ),
                              ),
                            ),
                          Positioned(
                            right: 12 + gutter,
                            bottom: 12,
                            child: Opacity(
                              opacity: .85,
                              child: IconButton.filledTonal(
                                key: const ValueKey('locate-current-song'),
                                tooltip: '定位当前歌曲',
                                onPressed: canLocate
                                    ? () => _locate(current, extent)
                                    : null,
                                icon: const Icon(Icons.my_location),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class SongRow extends StatelessWidget {
  const SongRow({
    required this.track,
    required this.library,
    required this.playback,
    required this.onTap,
    required this.onSelect,
    this.selected = false,
    this.selecting = false,
    this.highlighted = false,
    this.enabled = true,
    this.extent = 60,
    this.reorderIndex,
    this.queueKey,
    super.key,
  });
  final LibraryTrack track;
  final LibraryController library;
  final PlaybackController playback;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final bool selected, selecting, highlighted, enabled;
  final double extent;
  final int? reorderIndex;
  final Key? queueKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playing = playback.currentSongId == track.song.id;
    final canSelect = enabled && reorderIndex == null;
    return Material(
      key: highlighted ? ValueKey('located-${track.song.id}') : null,
      color: highlighted || selected
          ? scheme.secondaryContainer
          : Colors.transparent,
      child: GestureDetector(
        onSecondaryTap: canSelect ? onSelect : null,
        child: InkWell(
          onLongPress: canSelect ? onSelect : null,
          onTap: canSelect && (selecting || track.available) ? onTap : null,
          child: SizedBox(
            height: extent,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 8,
                right: FastScrollbar.rowEndPadding,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: selecting
                        ? Checkbox(
                            value: selected,
                            onChanged: enabled ? (_) => onSelect() : null,
                            semanticLabel: '选择${track.title}',
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TrackCover(
                              key: ValueKey((
                                track.song.id,
                                track.location,
                                track.song.size,
                                track.song.modified,
                              )),
                              documents: playback.documents,
                              track: track.probe,
                              size: 44,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                            color: playing ? scheme.primary : null,
                          ),
                        ),
                        Text(
                          '${track.song.artist?.trim().isNotEmpty == true ? track.song.artist : '未知歌手'}－${track.song.album?.trim().isNotEmpty == true ? track.song.album : '未知专辑'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!track.available)
                    Tooltip(
                      message: '文件失联 · 记录仍保留',
                      child: Icon(
                        Icons.link_off,
                        size: 16,
                        color: scheme.error,
                      ),
                    ),
                  if (playing)
                    Icon(Icons.graphic_eq, size: 16, color: scheme.primary),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      key: queueKey,
                      tooltip: '加入队列',
                      onPressed: enabled && track.available
                          ? () => playback.addToQueue([track.queueSong])
                          : null,
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: PopupMenuButton<String>(
                      tooltip: '歌曲操作',
                      enabled: enabled,
                      onSelected: (value) {
                        if (value == 'information') {
                          showSongInformation(context, track);
                        }
                        if (value == 'select' && canSelect) onSelect();
                        if (value == 'tags') {
                          showTagActions(context, library, {track.song.id});
                        }
                        if (value == 'playlist') {
                          addToPlaylist(context, library, [track.song.id]);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'information',
                          child: Text('歌曲信息'),
                        ),
                        if (reorderIndex == null)
                          const PopupMenuItem(
                            value: 'select',
                            child: Text('多选歌曲'),
                          ),
                        const PopupMenuItem(value: 'tags', child: Text('编辑标签')),
                        const PopupMenuItem(
                          value: 'playlist',
                          child: Text('加入歌单'),
                        ),
                      ],
                    ),
                  ),
                  if (reorderIndex != null)
                    ReorderHandle(
                      index: reorderIndex!,
                      label: '拖动${track.title}排序',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
