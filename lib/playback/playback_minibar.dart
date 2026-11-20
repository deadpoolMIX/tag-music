import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_controller.dart';
import 'playback_controller.dart';
import 'full_player.dart';
import '../library/track_cover.dart';
import 'queue_page.dart';
import 'playback_status.dart';

class PlaybackMinibar extends ConsumerWidget {
  const PlaybackMinibar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    final desktop = Theme.of(context).platform == TargetPlatform.windows;
    Widget bar() {
      final current = playback?.current;
      final lyric = current != null && playback?.changingTrack == false
          ? playback?.currentLyric
          : null;
      final title = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            current == null ? '未播放' : playbackTitle(playback!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            current == null
                ? '选择歌曲开始播放'
                : playback!.changingTrack
                ? '正在装载歌曲'
                : (desktop ? null : lyric) ?? playbackArtist(playback),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
      return Material(
        key: const ValueKey('global-minibar'),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: '打开完整播放器',
                  child: InkWell(
                    onTap: playback == null
                        ? null
                        : () => openFullPlayer(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          if (current != null && playback != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: TrackCover(
                                documents: playback.documents,
                                track: current,
                                size: 44,
                                currentArtwork: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: desktop && lyric != null
                                ? LayoutBuilder(
                                    builder: (context, constraints) => Row(
                                      spacing: constraints.maxWidth < 260
                                          ? 8
                                          : 24,
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                constraints.maxWidth * .42,
                                          ),
                                          child: title,
                                        ),
                                        Expanded(
                                          child: Text(
                                            lyric,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : title,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (playback != null)
                PlaybackToggleButton(
                  playback: playback,
                  filled: false,
                  enabled: !playback.busy,
                )
              else
                const IconButton(
                  key: ValueKey('play-pause'),
                  tooltip: '播放',
                  onPressed: null,
                  icon: Icon(Icons.play_arrow),
                ),
              IconButton(
                key: const ValueKey('open-playback-queue'),
                tooltip: '播放队列',
                onPressed: playback == null
                    ? null
                    : () => showPlaybackQueue(context, playback, library),
                icon: const Icon(Icons.queue_music),
              ),
            ],
          ),
        ),
      );
    }

    return playback == null
        ? bar()
        : ListenableBuilder(listenable: playback, builder: (_, _) => bar());
  }
}
