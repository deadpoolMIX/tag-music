import 'package:flutter/material.dart';

import 'playback_controller.dart';

void enqueueSongs(
  BuildContext context,
  PlaybackController playback,
  List<QueueSong> songs,
) {
  playback.addToQueue(List.of(songs));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('已添加 ${songs.length} 首到优先待播，按添加顺序播放')),
    );
}
