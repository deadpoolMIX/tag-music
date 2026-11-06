import 'package:flutter/material.dart';

import '../core/reorder_handle.dart';
import '../library/library_controller.dart';
import '../library/playlist_actions.dart';
import 'playback_controller.dart';

const playbackModeNames = {
  PlaybackMode.sequential: '顺序播放',
  PlaybackMode.repeatAll: '列表循环',
  PlaybackMode.repeatOne: '单曲循环',
  PlaybackMode.shuffle: '随机播放',
};

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({required this.playback, super.key});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '上一首',
        onPressed: playback.canPrevious ? playback.previous : null,
        icon: const Icon(Icons.skip_previous),
      ),
      IconButton.filled(
        key: const ValueKey('play-pause'),
        tooltip: playback.playing ? '暂停' : '播放',
        onPressed: playback.togglePlayPause,
        icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
      ),
      IconButton(
        tooltip: '停止',
        onPressed: playback.stop,
        icon: const Icon(Icons.stop),
      ),
      IconButton(
        tooltip: '下一首',
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
  Widget build(BuildContext context) => PopupMenuButton<PlaybackMode>(
    key: const ValueKey('playback-mode'),
    tooltip: '播放模式',
    initialValue: playback.queue.mode,
    onSelected: playback.setMode,
    itemBuilder: (_) => [
      for (final mode in PlaybackMode.values)
        CheckedPopupMenuItem(
          key: ValueKey('playback-mode-${mode.name}'),
          value: mode,
          checked: mode == playback.queue.mode,
          child: Text(playbackModeNames[mode]!),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(playbackModeNames[playback.queue.mode]!),
    ),
  );
}

Future<void> showPlaybackQueue(
  BuildContext context,
  PlaybackController playback,
  LibraryController? library,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog.fullscreen(
    child: SafeArea(
      child: QueuePage(playback: playback, library: library),
    ),
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
      builder: (dialog) => AlertDialog(
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
      final priority = {
        for (final (index, id) in playback.queue.priorityIds.indexed)
          id: index + 1,
      };
      return Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '关闭队列',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              Expanded(child: Text('播放队列 · ${entries.length} 项')),
              PlaybackModeButton(playback: playback),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('优先待播按编号播放一次，再续原序列；已播条目保留。拖动可调整队列和待播顺序。'),
          ),
          if (playback.error case final error?)
            Text(error, key: const ValueKey('queue-error')),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('队列为空，从曲库、筛选或歌单添加歌曲'))
                : ReorderableListView.builder(
                    key: const ValueKey('queue-order'),
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
                        leading: Icon(
                          current ? Icons.graphic_eq : Icons.music_note,
                        ),
                        title: Text(
                          entry.song.track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (current) playback.playing ? '正在播放' : '当前 · 已暂停',
                            if (priority[entry.entryId] case final rank?)
                              '优先待播 $rank',
                          ].join(' · '),
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
          if (playback.queue.current != null)
            PlaybackControls(playback: playback),
        ],
      );
    },
  );
}
