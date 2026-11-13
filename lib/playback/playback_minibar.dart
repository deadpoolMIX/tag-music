import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_controller.dart';
import 'playback_controller.dart';
import 'playback_page.dart';
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
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(
                              appBar: _PlayerAppBar(),
                              body: PlaybackPage(controlsOnly: true),
                            ),
                          ),
                        ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current == null
                              ? '尚未播放'
                              : playback?.metadata?.title ?? current.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          current == null
                              ? '选择歌曲开始播放'
                              : playback?.metadata?.artist ?? '未知歌手',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
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

class _PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlayerAppBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(title: const Text('正在播放'));
}
