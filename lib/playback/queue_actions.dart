import 'package:flutter/material.dart';

import 'playback_controller.dart';

/// Capture the source order when pressed; repeated songs remain separate entries.
class QueueAddButton extends StatelessWidget {
  const QueueAddButton({
    required this.playback,
    required this.songs,
    this.compact = false,
    super.key,
  });
  final PlaybackController playback;
  final List<QueueSong> songs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    void add() {
      playback.addToQueue(List.of(songs));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('已添加 ${songs.length} 首到优先待播，按添加顺序播放')),
        );
    }

    return compact
        ? IconButton(
            tooltip: '添加到播放队列',
            onPressed: songs.isEmpty ? null : add,
            icon: const Icon(Icons.queue_music),
          )
        : TextButton.icon(
            onPressed: songs.isEmpty ? null : add,
            icon: const Icon(Icons.queue_music),
            label: const Text('添加到播放队列'),
          );
  }
}
