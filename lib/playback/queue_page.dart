import 'dart:math' as math;

import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../core/compact_dialog.dart';
import '../core/desktop_navigation.dart';
import '../core/fast_scrollbar.dart';
import '../core/reorder_handle.dart';
import '../library/library_controller.dart';
import '../library/playlist_actions.dart';
import '../library/song_information.dart';
import '../library/tags_page.dart' show showTagActions;
import '../library/track_cover.dart';
import 'playback_controller.dart';
import 'playback_queue.dart' show QueueEntry;
import 'playback_status.dart';
import 'slide_dismiss_route.dart';

const playbackModeNames = {
  PlaybackMode.sequential: '顺序播放',
  PlaybackMode.repeatAll: '列表循环',
  PlaybackMode.repeatOne: '单曲循环',
  PlaybackMode.shuffle: '随机播放',
};

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    required this.playback,
    this.tagLibrary,
    this.onToggleLayout,
    this.large = false,
    this.immersiveColor,
    this.blockBackgroundTap = false,
    super.key,
  });
  final PlaybackController playback;
  final LibraryController? tagLibrary;
  final VoidCallback? onToggleLayout;
  final bool large;
  final Color? immersiveColor;
  final bool blockBackgroundTap;

  Widget _buttonArea(Widget child) => blockBackgroundTap
      ? GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          // Even disabled buttons should leave the desktop player layer alone.
          onTap: () {},
          child: child,
        )
      : child;

  Widget _transport(double spacing) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: spacing,
    children: [
      IconButton(
        tooltip: '上一首',
        color: immersiveColor,
        disabledColor: immersiveColor?.withValues(alpha: .38),
        iconSize: large ? 32 : null,
        onPressed: playback.canPrevious ? playback.previous : null,
        icon: const Icon(Icons.skip_previous),
      ),
      PlaybackToggleButton(
        playback: playback,
        onToggleLayout: onToggleLayout,
        large: large,
        filled: immersiveColor == null,
        unfilledColor: immersiveColor,
      ),
      IconButton(
        tooltip: '下一首',
        color: immersiveColor,
        disabledColor: immersiveColor?.withValues(alpha: .38),
        iconSize: large ? 32 : null,
        onPressed: playback.canNext ? playback.next : null,
        icon: const Icon(Icons.skip_next),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final library = tagLibrary;
    if (library == null) return _buttonArea(_transport(large ? 24 : 0));
    final tagWidth = large ? 48.0 : 36.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final balanced = width >= (large ? 256 : 184);
        final spacing = large && width >= 304 ? 24.0 : 0.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (balanced) SizedBox(width: tagWidth),
            Flexible(child: _buttonArea(_transport(spacing))),
            _buttonArea(
              SizedBox(
                width: tagWidth,
                child: PlaybackTagButton(
                  playback: playback,
                  library: library,
                  foreground: immersiveColor,
                  iconSize: large ? 24 : 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlaybackTagButton extends StatelessWidget {
  const PlaybackTagButton({
    required this.playback,
    required this.library,
    this.foreground,
    this.iconSize = 24,
    super.key,
  });

  final PlaybackController playback;
  final LibraryController? library;
  final Color? foreground;
  final double iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('player-add-tag'),
    tooltip: '添加标签',
    color: foreground,
    disabledColor: foreground?.withValues(alpha: .38),
    onPressed: library == null || playback.currentSongId == null
        ? null
        : () {
            final songId = playback.currentSongId;
            if (songId != null) {
              showTagActions(context, library!, {songId}, title: '添加标签');
            }
          },
    icon: Builder(
      builder: (context) => CustomPaint(
        size: Size.square(iconSize),
        painter: _PlaybackTagIcon(
          IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _PlaybackTagIcon extends CustomPainter {
  const _PlaybackTagIcon(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final outline = Path()
      ..moveTo(4, 4)
      ..lineTo(12, 4)
      ..lineTo(21, 13)
      ..lineTo(13, 21)
      ..lineTo(4, 12)
      ..close();
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(outline, ink);
    canvas.drawCircle(
      const Offset(8.5, 8.5),
      1.15,
      ink..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_PlaybackTagIcon oldDelegate) =>
      color != oldDelegate.color;
}

class PlaybackModeButton extends StatelessWidget {
  const PlaybackModeButton({required this.playback, super.key});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final mode = playback.queue.mode;
    return IconButton(
      key: const ValueKey('playback-mode'),
      tooltip: playbackModeNames[mode],
      icon: Icon(switch (mode) {
        PlaybackMode.sequential => Icons.format_list_numbered,
        PlaybackMode.repeatAll => Icons.repeat,
        PlaybackMode.repeatOne => Icons.repeat_one,
        PlaybackMode.shuffle => Icons.shuffle,
      }),
      onPressed: () {
        final modes = PlaybackMode.values;
        playback.setMode(modes[(playback.queue.mode.index + 1) % modes.length]);
      },
    );
  }
}

const playbackQueueRouteName = '/queue';

Future<void> showPlaybackQueue(
  BuildContext context,
  PlaybackController playback,
  LibraryController? library,
) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return pushAppPage(
    context,
    () => SlideDismissRoute(
      name: playbackQueueRouteName,
      reduceMotion: reduceMotion,
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Semantics(
            customSemanticsActions: {
              const CustomSemanticsAction(label: '关闭队列'): () =>
                  Navigator.maybePop(context),
            },
            child: QueuePage(playback: playback, library: library),
          ),
        ),
      ),
    ),
  );
}

class QueuePage extends StatefulWidget {
  const QueuePage({required this.playback, this.library, super.key});
  final PlaybackController playback;
  final LibraryController? library;
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  bool busy = false;
  late final _scroll = _QueueScrollController(
    route: () => _dismissRoute,
    height: () => MediaQuery.sizeOf(context).height,
  );
  bool _positioned = false;
  double _rowExtent = 60;

  SlideDismissRoute? get _dismissRoute {
    final route = ModalRoute.of(context);
    return route is SlideDismissRoute ? route : null;
  }

  List<QueueEntry> _visibleEntries(Iterable<QueueEntry> entries) {
    final library = widget.library;
    return [
      for (final entry in entries)
        if (library == null ||
            library.availableTrack(entry.song.songId) != null)
          entry,
    ];
  }

  Future<void> _reorderEntries(
    List<QueueEntry> all,
    List<QueueEntry> visible,
    int from,
    int to,
  ) {
    final ordered = visible.map((entry) => entry.entryId).toList();
    final visibleIds = ordered.toSet();
    ordered.insert(to, ordered.removeAt(from));
    var index = 0;
    return widget.playback.reorderQueue([
      for (final entry in all)
        visibleIds.contains(entry.entryId) ? ordered[index++] : entry.entryId,
    ]);
  }

  Future<void> _move(String entryId, int delta) => _change(() async {
    // Resolve identities after a menu closes; the queue may have advanced or
    // changed while the user was choosing an operation.
    final all = widget.playback.queue.entries.toList();
    final visible = _visibleEntries(all);
    final index = visible.indexWhere((entry) => entry.entryId == entryId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= visible.length) return;
    await _reorderEntries(all, visible, index, target);
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _change(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => CompactAlertDialog(
        title: const Text('清空播放队列？'),
        content: const Text('将停止播放并移除全部队列条目，歌单和曲库保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('清空队列'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _change(widget.playback.clearQueue);
  }

  static const _rowShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  Widget _entryTile(
    BuildContext context,
    QueueEntry entry,
    int index,
    int count,
    int? rank,
  ) {
    final playback = widget.playback;
    final current = playback.queue.current?.entryId == entry.entryId;
    final track =
        (current ? playback.current : null) ??
        widget.library?.resolveSong(entry.song.songId) ??
        entry.song.track;
    final subtitle = [
      if (current) '当前 · ${playbackActivityLabel(playback)}',
      if (rank != null) '优先待播 $rank',
    ].join(' · ');

    return ListTile(
      key: ValueKey('queue-entry-${entry.entryId}'),
      shape: _rowShape,
      selected: current,
      selectedTileColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: .08),
      contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 4),
      leading: PopupMenuButton<String>(
        tooltip: '队列第${index + 1}首操作',
        enabled: !busy,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TrackCover(
            documents: playback.documents,
            track: track,
            size: 42,
          ),
        ),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'up',
            enabled: index > 0,
            child: const Text('上移一项'),
          ),
          PopupMenuItem(
            value: 'down',
            enabled: index + 1 < count,
            child: const Text('下移一项'),
          ),
          if (widget.library?.availableTrack(entry.song.songId) != null)
            const PopupMenuItem(value: 'info', child: Text('歌曲信息')),
        ],
        onSelected: (choice) async {
          if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
          if (choice == 'up' || choice == 'down') {
            await _move(entry.entryId, choice == 'up' ? -1 : 1);
          } else {
            final track = widget.library?.availableTrack(entry.song.songId);
            if (track != null) await showSongInformation(context, track);
          }
        },
      ),
      title: Text(
        entry.song.track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: busy
          ? null
          : () => _change(() => playback.selectEntry(entry.entryId)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('queue-remove-${entry.entryId}'),
            tooltip: '移除此条目',
            onPressed: busy
                ? null
                : () => _change(() => playback.removeFromQueue(entry.entryId)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          ReorderHandle(index: index, enabled: !busy, label: '拖动队列歌曲排序'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.playback, widget.library]),
    builder: (context, _) {
      final playback = widget.playback;
      final all = playback.queue.entries.toList();
      final entries = _visibleEntries(all);
      final scaler = MediaQuery.textScalerOf(context);
      final route = _dismissRoute;
      final height = MediaQuery.sizeOf(context).height;
      _rowExtent = math.max(
        60,
        (scaler.scale(16) + scaler.scale(14)) * 1.4 + 16,
      );
      if (!_positioned && entries.isNotEmpty) {
        _positioned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final queue = widget.playback.queue;
          final index = _visibleEntries(queue.entries)
              .indexWhere((entry) => entry.entryId == queue.current?.entryId);
          if (index < 0) return;
          final position = _scroll.position;
          final offset =
              index * _rowExtent -
              (position.viewportDimension - _rowExtent) / 2;
          _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
        });
      }
      final visibleIds = entries.map((entry) => entry.entryId).toSet();
      final priority = {
        for (final (index, id)
            in playback.queue.priorityIds.where(visibleIds.contains).indexed)
          id: index + 1,
      };
      final theme = Theme.of(context);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onVerticalDragStart: route == null ? null : (_) => route.startDrag(),
        onVerticalDragUpdate: route == null
            ? null
            : (details) => route.moveDrag(details.primaryDelta ?? 0, height),
        onVerticalDragEnd: route == null
            ? null
            : (details) =>
                  route.finishDrag(velocity: details.primaryVelocity ?? 0),
        onVerticalDragCancel: route == null
            ? null
            : () => route.finishDrag(cancelled: true),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '播放队列 · ${entries.length} 首',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (widget.library case final library?)
                    IconButton(
                      key: const ValueKey('save-full-queue'),
                      tooltip: '保存完整队列为歌单',
                      onPressed: all.isEmpty || busy
                          ? null
                          : () => savePlaylist(
                              context,
                              library,
                              all.map((e) => e.song.songId),
                            ),
                      icon: const Icon(Icons.playlist_add),
                    ),
                  IconButton(
                    key: const ValueKey('clear-playback-queue'),
                    tooltip: '清空队列',
                    onPressed: all.isEmpty || busy ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (playback.operationError case final error?)
              Text(
                error,
                key: const ValueKey('queue-error'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('队列为空，从曲库、筛选或歌单添加歌曲'))
                  : CoverScrollRegion(
                      cache: playback.documents.coverCache,
                      child: FastScrollbar(
                        controller: _scroll,
                        child: ReorderableListView.builder(
                          key: const ValueKey('queue-order'),
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: FastScrollbar.dragWidth - 4,
                          ),
                          scrollController: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                          itemExtent: _rowExtent,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, _, animation) =>
                              AnimatedBuilder(
                                animation: animation,
                                child: child,
                                builder: (context, child) => Material(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  shape: _rowShape,
                                  clipBehavior: Clip.antiAlias,
                                  elevation: 6 * animation.value,
                                  child: child,
                                ),
                              ),
                          itemCount: entries.length,
                          onReorderItem: (oldIndex, newIndex) => _change(
                            () => _reorderEntries(
                              all,
                              entries,
                              oldIndex,
                              newIndex,
                            ),
                          ),
                          itemBuilder: (context, index) => _entryTile(
                            context,
                            entries[index],
                            index,
                            entries.length,
                            priority[entries[index].entryId],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

// A downward drag past the top of the list moves the same route as its header.
class _QueueScrollController extends ScrollController {
  _QueueScrollController({required this.route, required this.height});

  final SlideDismissRoute? Function() route;
  final double Function() height;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _QueueScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    route: route,
    height: height,
  );
}

class _QueueScrollPosition extends ScrollPositionWithSingleContext {
  _QueueScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.route,
    required this.height,
  });

  final SlideDismissRoute? Function() route;
  final double Function() height;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final scrollDrag = super.drag(details, dragCancelCallback);
    final dismissRoute = route();
    return dismissRoute == null
        ? scrollDrag
        : _QueueListDrag(this, scrollDrag, dismissRoute, height());
  }
}

class _QueueListDrag extends Drag {
  _QueueListDrag(this.position, this.scrollDrag, this.route, this.height);

  final ScrollPosition position;
  final Drag scrollDrag;
  final SlideDismissRoute route;
  final double height;
  bool _dismissing = false;

  @override
  void update(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (!_dismissing &&
        delta > 0 &&
        position.pixels <= position.minScrollExtent) {
      _dismissing = route.startDrag();
    }
    if (_dismissing) {
      route.moveDrag(delta, height);
    } else {
      scrollDrag.update(details);
    }
  }

  @override
  void end(DragEndDetails details) {
    if (_dismissing) {
      scrollDrag.cancel();
      route.finishDrag(velocity: details.primaryVelocity ?? 0);
    } else {
      scrollDrag.end(details);
    }
  }

  @override
  void cancel() {
    scrollDrag.cancel();
    if (_dismissing) route.finishDrag(cancelled: true);
  }
}
