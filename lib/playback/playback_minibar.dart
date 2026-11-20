import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_controller.dart';
import '../library/song_selection.dart';
import 'playback_bar_gestures.dart';
import 'playback_controller.dart';
import 'playback_queue.dart' show QueueEntry;
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
    if (SongSelectionScope.isSelectingOf(context)) {
      return const SafeArea(top: false, child: SizedBox.shrink());
    }

    final openPlayer = playback == null ? null : () => openFullPlayer(context);
    Widget content(BuildContext context, QueueEntry? preview) {
      final display = playbackBarTrack(playback, library, preview);
      final current = display.track;
      final title = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            display.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            display.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );
      return Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: '打开完整播放器',
                child: InkWell(
                  onTap: openPlayer,
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
                        Expanded(child: title),
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
      );
    }

    Widget bar() => Material(
      key: const ValueKey('global-minibar'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: PlaybackBarGestures(
          playback: playback,
          onOpenPlayer: openPlayer,
          builder: content,
        ),
      ),
    );
    return playback == null
        ? bar()
        : ListenableBuilder(listenable: playback, builder: (_, _) => bar());
  }
}
