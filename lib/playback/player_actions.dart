import 'dart:async';

import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../library/library_controller.dart';
import '../library/song_information.dart';
import 'playback_controller.dart';
import 'queue_page.dart';
import 'sleep_timer_sheet.dart';

class PlayerActions {
  const PlayerActions({required this.playback, this.library, this.openLyrics});

  final PlaybackController playback;
  final LibraryController? library;
  final Future<void> Function()? openLyrics;

  List<PopupMenuEntry<String>> _items() => [
    if (openLyrics != null)
      PopupMenuItem(
        value: 'lyrics',
        enabled: playback.current != null,
        child: const Text('沉浸歌词'),
      ),
    const PopupMenuItem(value: 'queue', child: Text('播放队列')),
    PopupMenuItem(
      value: 'sleep',
      child: Text(playback.sleep.active ? '管理睡眠定时' : '睡眠定时'),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(value: 'stop', child: Text('停止播放')),
    if (library?.tracks.any((t) => t.song.id == playback.currentSongId) == true)
      const PopupMenuItem(value: 'info', child: Text('歌曲信息')),
    if (playback.playerFeedback != null)
      const PopupMenuItem(value: 'status', child: Text('查看播放提示')),
    const PopupMenuItem(value: 'close', child: Text('关闭播放页')),
  ];

  Future<void> show(BuildContext context, {Offset? globalPosition}) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final anchor = context.findRenderObject() as RenderBox;
    final point = overlay.globalToLocal(
      globalPosition ?? anchor.localToGlobal(Offset(0, anchor.size.height)),
    );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: _items(),
    );
    if (!context.mounted ||
        choice == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    switch (choice) {
      case 'lyrics':
        if (playback.current != null) await openLyrics?.call();
      case 'queue':
        await showPlaybackQueue(context, playback, library);
      case 'sleep':
        await showSleepTimer(context, playback);
      case 'stop':
        await playback.stop();
      case 'info':
        // Resolve the current track after the menu closes: playback may have
        // advanced while the menu was open.
        final matches = library?.tracks.where(
          (t) => t.song.id == playback.currentSongId,
        );
        if (matches?.isNotEmpty == true) {
          await showSongInformation(context, matches!.first);
        }
      case 'status':
        await showPlaybackFeedback(context, playback);
      case 'close':
        await Navigator.maybePop(context);
    }
  }
}

class PlayerActionsButton extends StatelessWidget {
  const PlayerActionsButton({required this.actions, this.interact, super.key});
  final PlayerActions actions;
  final Future<void> Function(Future<void> Function())? interact;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => IconButton(
      tooltip: '更多播放操作',
      icon: const Icon(Icons.more_vert),
      onPressed: () => unawaited(
        interact == null
            ? actions.show(buttonContext)
            : interact!(() => actions.show(buttonContext)),
      ),
    ),
  );
}

Future<void> showPlaybackFeedback(
  BuildContext context,
  PlaybackController playback,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => CompactAlertDialog(
    title: const Text('播放提示'),
    content: SingleChildScrollView(
      child: SelectableText(playback.playerFeedback ?? '当前没有播放提示。'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('关闭'),
      ),
    ],
  ),
);

class PlaybackFeedback extends StatelessWidget {
  const PlaybackFeedback({
    required this.playback,
    this.onOpen,
    this.color,
    super.key,
  });
  final PlaybackController playback;
  final VoidCallback? onOpen;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final message = playback.playerFeedback;
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: TextButton.icon(
        style: color == null
            ? null
            : TextButton.styleFrom(foregroundColor: color),
        onPressed: onOpen ?? () => showPlaybackFeedback(context, playback),
        icon: Icon(
          playback.error == null ? Icons.info_outline : Icons.error_outline,
        ),
        label: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
