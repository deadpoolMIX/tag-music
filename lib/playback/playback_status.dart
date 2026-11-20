import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../library/library_controller.dart';
import 'documents.dart' show ProbeTrack;
import 'playback_controller.dart';
import 'playback_queue.dart' show QueueEntry;

String? _nonBlank(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String playbackTitle(PlaybackController playback) =>
    (!playback.changingTrack ? _nonBlank(playback.metadata?.title) : null) ??
    _nonBlank(playback.current?.name) ??
    '未播放';

String playbackArtist(PlaybackController playback) => playback.changingTrack
    ? '正在读取歌曲信息'
    : _nonBlank(playback.metadata?.artist) ?? '未知歌手';

({ProbeTrack? track, String title, String subtitle}) playbackBarTrack(
  PlaybackController? playback,
  LibraryController? library,
  QueueEntry? preview,
) {
  if (preview != null) {
    final track = library?.availableTrack(preview.song.songId);
    return (
      track: track?.probe ?? preview.song.track,
      title: track?.title ?? preview.song.track.name,
      subtitle: _nonBlank(track?.song.artist) ?? '未知歌手',
    );
  }
  final current = playback?.current;
  if (playback == null || current == null) {
    return (track: null, title: '未播放', subtitle: '选择歌曲开始播放');
  }
  final songId = playback.currentSongId;
  final saved = songId == null ? null : library?.availableTrack(songId);
  return (
    track: current,
    title: playback.changingTrack
        ? saved?.title ?? current.name
        : playbackTitle(playback),
    subtitle: playback.changingTrack
        ? '正在装载歌曲'
        : playback.currentLyric ?? playbackArtist(playback),
  );
}

String playbackActivityLabel(PlaybackController playback) {
  if (playback.changingTrack) return '正在装载歌曲';
  if (playback.current == null) return '尚未选择歌曲';
  if (playback.playbackFailed) return '播放失败';
  if (playback.player.state.playlist.medias.isEmpty) return '尚未开始播放';
  if (playback.player.state.completed) return '本曲已结束';
  if (playback.playing && playback.player.state.buffering) return '正在缓冲';
  return playback.playing ? '正在播放' : '已暂停';
}

/// The shared transport button for the minibar and playback controls.
class PlaybackToggleButton extends StatelessWidget {
  const PlaybackToggleButton({
    required this.playback,
    this.filled = true,
    this.enabled = true,
    this.onToggleLayout,
    this.large = false,
    this.unfilledColor,
    super.key,
  });
  final PlaybackController playback;
  final bool filled, enabled;
  final bool large;
  final Color? unfilledColor;
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
        : Icon(switch ((large, playback.playing)) {
            (true, true) => Icons.pause_rounded,
            (true, false) => Icons.play_arrow_rounded,
            (false, true) => Icons.pause,
            (false, false) => Icons.play_arrow,
          }, size: large ? 36 : null);
    if (onToggleLayout case final toggleLayout?) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Semantics(
        label: label,
        value: playbackActivityLabel(playback),
        button: true,
        enabled: true,
        onTap: canToggle ? playback.togglePlayPause : null,
        onLongPress: toggleLayout,
        customSemanticsActions: {
          const CustomSemanticsAction(label: '切换沉浸模式'): toggleLayout,
        },
        child: Material(
          shape: const CircleBorder(),
          color: filled
              ? scheme.primary
              : (unfilledColor ?? scheme.onSurface).withValues(alpha: .12),
          child: InkWell(
            key: const ValueKey('play-pause'),
            customBorder: const CircleBorder(),
            onTap: canToggle ? playback.togglePlayPause : null,
            onLongPress: toggleLayout,
            excludeFromSemantics: true,
            child: SizedBox.square(
              dimension: large ? 64 : 48,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: filled
                        ? scheme.onPrimary
                        : unfilledColor ?? scheme.onSurface,
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      );
    }
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
    return Semantics(value: playbackActivityLabel(playback), child: button);
  }
}
