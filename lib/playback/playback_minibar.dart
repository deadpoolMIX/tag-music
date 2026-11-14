import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_controller.dart';
import 'playback_controller.dart';
import 'full_player.dart';
import '../library/track_cover.dart';
import 'queue_page.dart';

class PlaybackMinibar extends ConsumerWidget {
  const PlaybackMinibar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    Widget bar() {
      final current = playback?.current;
      return Material(
        key: const ValueKey('global-minibar'),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
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
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current == null
                                    ? '未播放'
                                    : playback?.metadata?.title ?? current.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text(
                                current == null
                                    ? '选择歌曲开始播放'
                                    : playback?.currentLyric ??
                                          playback?.metadata?.artist ??
                                          '未知歌手',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('play-pause'),
                tooltip: playback?.playing == true ? '暂停' : '播放',
                onPressed: current == null || playback == null || playback.busy
                    ? null
                    : playback.togglePlayPause,
                icon: Icon(
                  playback?.playing == true ? Icons.pause : Icons.play_arrow,
                ),
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
