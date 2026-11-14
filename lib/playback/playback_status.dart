import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'playback_controller.dart';

String playbackTitle(PlaybackController playback) =>
    (!playback.changingTrack ? playback.metadata?.title : null) ??
    playback.current?.name ??
    '未播放';

String playbackArtist(PlaybackController playback) =>
    playback.changingTrack ? '正在读取歌曲信息' : playback.metadata?.artist ?? '未知歌手';

String playbackActivityLabel(PlaybackController playback) {
  if (playback.changingTrack) return '正在装载歌曲';
  if (playback.current == null) return '尚未选择歌曲';
  if (playback.playbackFailed) return '播放失败';
  if (playback.player.state.playlist.medias.isEmpty) return '尚未开始播放';
  if (playback.player.state.completed) return '本曲已结束';
  if (playback.playing && playback.player.state.buffering) return '正在缓冲';
  return playback.playing ? '正在播放' : '已暂停';
}

/// Feedback only; the backend remains the source of playback and buffering state.
class PlaybackActivity extends StatelessWidget {
  const PlaybackActivity({required this.playback, super.key});
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        playbackActivityLabel(playback),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

/// One transport button across the minibar, full player, lyrics and queue.
class PlaybackToggleButton extends StatelessWidget {
  const PlaybackToggleButton({
    required this.playback,
    this.filled = true,
    this.enabled = true,
    this.onToggleLayout,
    super.key,
  });
  final PlaybackController playback;
  final bool filled, enabled;
  final VoidCallback? onToggleLayout;

  @override
  Widget build(BuildContext context) {
    final loading = playback.changingTrack;
    final canToggle = enabled && playback.current != null && !loading;
    final label = loading
        ? '正在装载歌曲'
        : playback.playing
        ? '暂停'
        : playback.playbackFailed
        ? '重试播放'
        : playback.player.state.completed
        ? '重新播放'
        : '播放';
    final icon = loading
        ? MediaQuery.disableAnimationsOf(context)
              ? const Icon(Icons.hourglass_empty)
              : const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
        : Icon(playback.playing ? Icons.pause : Icons.play_arrow);
    final button = filled
        ? IconButton.filled(
            key: const ValueKey('play-pause'),
            tooltip: label,
            onPressed: canToggle ? playback.togglePlayPause : null,
            icon: icon,
          )
        : IconButton(
            key: const ValueKey('play-pause'),
            tooltip: label,
            onPressed: canToggle ? playback.togglePlayPause : null,
            icon: icon,
          );
    return Semantics(
      value: playbackActivityLabel(playback),
      customSemanticsActions: onToggleLayout == null
          ? null
          : {const CustomSemanticsAction(label: '切换标准或简洁布局'): onToggleLayout!},
      child: GestureDetector(onLongPress: onToggleLayout, child: button),
    );
  }
}
