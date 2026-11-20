import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../core/reorder_handle.dart';
import '../library/library_controller.dart';
import '../library/playlist_actions.dart';
import '../library/song_information.dart';
import 'playback_controller.dart';
import 'playback_status.dart';

const playbackModeNames = {
  PlaybackMode.sequential: '顺序播放',
  PlaybackMode.repeatAll: '列表循环',
  PlaybackMode.repeatOne: '单曲循环',
  PlaybackMode.shuffle: '随机播放',
};

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    required this.playback,
    this.onToggleLayout,
    this.large = false,
    this.immersive = false,
    super.key,
  });
  final PlaybackController playback;
  final VoidCallback? onToggleLayout;
  final bool large, immersive;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: large ? 24 : 0,
    children: [
      IconButton(
        tooltip: '上一首',
        color: immersive ? Colors.white : null,
        disabledColor: immersive ? Colors.white38 : null,
        iconSize: large ? 32 : null,
        onPressed: playback.canPrevious ? playback.previous : null,
        icon: const Icon(Icons.skip_previous),
      ),
      PlaybackToggleButton(
        playback: playback,
        onToggleLayout: onToggleLayout,
        large: large,
        filled: !immersive,
      ),
      IconButton(
        tooltip: '下一首',
        color: immersive ? Colors.white : null,
        disabledColor: immersive ? Colors.white38 : null,
        iconSize: large ? 32 : null,
        onPressed: playback.canNext ? playback.next : null,
        icon: const Icon(Icons.skip_next),
      ),
    ],
  );
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

Future<void> showPlaybackQueue(
  BuildContext context,
  PlaybackController playback,
  LibraryController? library,
) => showGeneralDialog<void>(
  context: context,
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 260),
  pageBuilder: (_, _, _) => Dialog.fullscreen(
    child: SafeArea(
      child: QueuePage(playback: playback, library: library),
    ),
  ),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: animation.drive(
      Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    ),
    child: child,
  ),
);

class QueuePage extends StatefulWidget {
  const QueuePage({required this.playback, this.library, super.key});
  final PlaybackController playback;
  final LibraryController? library;
  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  bool busy = false;
  final _scroll = ScrollController();
  bool _positioned = false;
  double _rowExtent = 72;

  void _locateCurrent({bool animate = true}) {
    final index = widget.playback.queue.index;
    if (index < 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final offset =
        (index * _rowExtent - (position.viewportDimension - _rowExtent) / 2)
            .clamp(0.0, position.maxScrollExtent);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _move(String entryId, int delta) => _change(() async {
    // Resolve identities after a menu closes; the queue may have advanced or
    // changed while the user was choosing an operation.
    final ids = widget.playback.queue.entries.map((e) => e.entryId).toList();
    final index = ids.indexOf(entryId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= ids.length) return;
    ids.insert(target, ids.removeAt(index));
    await widget.playback.reorderQueue(ids);
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.playback,
    builder: (context, _) {
      final playback = widget.playback;
      final entries = playback.queue.entries.toList();
      final scaler = MediaQuery.textScalerOf(context);
      _rowExtent = math.max(
        72,
        scaler.scale(16) * 1.5 + scaler.scale(14) * 1.5 + 24,
      );
      if (!_positioned && entries.isNotEmpty) {
        _positioned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _locateCurrent(animate: false);
        });
      }
      final priority = {
        for (final (index, id) in playback.queue.priorityIds.indexed)
          id: index + 1,
      };
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .45,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: '关闭队列',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                        Expanded(child: Text('播放队列 · ${entries.length} 项')),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PlaybackModeButton(playback: playback),
                        TextButton.icon(
                          onPressed: playback.queue.current == null
                              ? null
                              : _locateCurrent,
                          icon: const Icon(Icons.my_location),
                          label: const Text('定位当前歌曲'),
                        ),
                        if (widget.library case final library?)
                          TextButton.icon(
                            key: const ValueKey('save-full-queue'),
                            onPressed: entries.isEmpty || busy
                                ? null
                                : () => savePlaylist(
                                    context,
                                    library,
                                    entries.map((e) => e.song.songId),
                                  ),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('保存完整队列为歌单'),
                          ),
                        TextButton(
                          key: const ValueKey('clear-playback-queue'),
                          onPressed: entries.isEmpty || busy ? null : _clear,
                          child: const Text('清空队列'),
                        ),
                      ],
                    ),
                    if (playback.error case final error?)
                      Text(error, key: const ValueKey('queue-error')),
                  ],
                ),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('队列为空，从曲库、筛选或歌单添加歌曲'))
                  : ReorderableListView.builder(
                      key: const ValueKey('queue-order'),
                      scrollController: _scroll,
                      itemExtent: _rowExtent,
                      buildDefaultDragHandles: false,
                      itemCount: entries.length,
                      onReorderItem: (oldIndex, newIndex) {
                        final ids = entries.map((e) => e.entryId).toList();
                        ids.insert(newIndex, ids.removeAt(oldIndex));
                        _change(() => playback.reorderQueue(ids));
                      },
                      itemBuilder: (_, i) {
                        final entry = entries[i];
                        final current =
                            playback.queue.current?.entryId == entry.entryId;
                        return ListTile(
                          key: ValueKey('queue-entry-${entry.entryId}'),
                          selected: current,
                          leading: PopupMenuButton<String>(
                            tooltip: '队列第${i + 1}项操作',
                            enabled: !busy,
                            icon: Icon(
                              current ? Icons.graphic_eq : Icons.music_note,
                            ),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'up',
                                enabled: i > 0,
                                child: const Text('上移一项'),
                              ),
                              PopupMenuItem(
                                value: 'down',
                                enabled: i + 1 < entries.length,
                                child: const Text('下移一项'),
                              ),
                              if (widget.library?.tracks.any(
                                    (t) => t.song.id == entry.song.songId,
                                  ) ==
                                  true)
                                const PopupMenuItem(
                                  value: 'info',
                                  child: Text('歌曲信息'),
                                ),
                            ],
                            onSelected: (choice) async {
                              if (!mounted ||
                                  ModalRoute.of(context)?.isCurrent != true) {
                                return;
                              }
                              if (choice == 'up' || choice == 'down') {
                                await _move(
                                  entry.entryId,
                                  choice == 'up' ? -1 : 1,
                                );
                              } else {
                                final tracks = widget.library?.tracks.where(
                                  (t) => t.song.id == entry.song.songId,
                                );
                                if (tracks?.isNotEmpty == true) {
                                  await showSongInformation(
                                    context,
                                    tracks!.first,
                                  );
                                }
                              }
                            },
                          ),
                          titleTextStyle: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontSize: 16, height: 1.5),
                          subtitleTextStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 14, height: 1.5),
                          title: Text(
                            entry.song.track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              '${i + 1} / ${entries.length}',
                              if (current)
                                '当前 · ${playbackActivityLabel(playback)}',
                              if (priority[entry.entryId] case final rank?)
                                '优先待播 $rank',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: busy
                              ? null
                              : () => _change(
                                  () => playback.selectEntry(entry.entryId),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey('queue-remove-${entry.entryId}'),
                                tooltip: '移除此条目',
                                onPressed: busy
                                    ? null
                                    : () => _change(
                                        () => playback.removeFromQueue(
                                          entry.entryId,
                                        ),
                                      ),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              ReorderHandle(
                                index: i,
                                enabled: !busy,
                                label: '拖动队列条目排序',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (playback.queue.current != null)
                  PlaybackControls(playback: playback),
                PopupMenuButton<String>(
                  tooltip: '更多播放操作',
                  onSelected: (_) => playback.stop(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'stop', child: Text('停止播放')),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
