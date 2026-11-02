import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';
import 'queue_page.dart';
import '../library/library_page.dart';
import '../library/library_controller.dart';
import '../library/filter_page.dart';
import '../library/playlists_page.dart';

String formatPosition(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class PlaybackPage extends ConsumerWidget {
  const PlaybackPage({
    this.filtering = false,
    this.playlists = false,
    super.key,
  });
  final bool filtering;
  final bool playlists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    if (controller == null) {
      return const Center(child: Text('让音乐有自己的归属'));
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.player.state;
        final current = controller.current;
        return Column(
          children: [
            if (controller.playbackNotice != null && controller.error == null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  controller.playbackNotice!,
                  key: const ValueKey('playback-notice'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if ((filtering || playlists) && controller.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  controller.error!,
                  key: const ValueKey('playback-error'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (library != null)
              Expanded(
                child: playlists
                    ? PlaylistsPage(library: library, playback: controller)
                    : filtering
                    ? FilterPage(library: library, playback: controller)
                    : LibraryPage(library: library, playback: controller),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('choose-directory'),
                          onPressed: controller.busy
                              ? null
                              : controller.chooseDirectory,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('选择音乐文件夹'),
                        ),
                        PopupMenuButton<String>(
                          tooltip: '重新打开已授权目录',
                          enabled:
                              !controller.busy && controller.roots.isNotEmpty,
                          onSelected: controller.refresh,
                          itemBuilder: (_) => [
                            for (var i = 0; i < controller.roots.length; i++)
                              PopupMenuItem(
                                value: controller.roots[i],
                                child: Text('已授权目录 ${i + 1}'),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('重新打开目录'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '播放技术验证 · ${controller.tracks.length} 首',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('目录授权会保存；本轮曲目列表不保存。点击歌曲开始播放。'),
                    if (!controller.notificationsEnabled ||
                        controller.notificationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        controller.notificationMessage ??
                            '允许播放通知后，可在通知栏和锁屏控制音乐。部分手机还需在通知设置中开启锁屏显示。',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: controller.requestingNotifications
                                ? null
                                : controller.requestNotificationPermission,
                            child: const Text('开启播放通知'),
                          ),
                          TextButton(
                            onPressed: controller.openNotificationSettings,
                            child: const Text('通知设置'),
                          ),
                        ],
                      ),
                    ],
                    if (controller.busy) const LinearProgressIndicator(),
                    if (controller.error != null)
                      Text(
                        controller.error!,
                        key: const ValueKey('playback-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: controller.tracks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '让音乐有自己的归属\n选择包含音乐的文件夹，支持读取子文件夹。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: controller.tracks.length,
                        itemBuilder: (context, index) {
                          final track = controller.tracks[index];
                          return ListTile(
                            key: ValueKey('track-$index'),
                            selected: controller.index == index,
                            leading: Icon(
                              controller.index == index && controller.playing
                                  ? Icons.graphic_eq
                                  : Icons.music_note_outlined,
                            ),
                            title: Text(
                              track.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: controller.busy
                                ? null
                                : () => unawaited(controller.select(index)),
                          );
                        },
                      ),
              ),
            ],
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PlaybackModeButton(playback: controller),
                TextButton.icon(
                  key: const ValueKey('open-playback-queue'),
                  onPressed: () =>
                      showPlaybackQueue(context, controller, library),
                  icon: const Icon(Icons.queue_music),
                  label: Text('播放队列 · ${controller.queue.entries.length}'),
                ),
              ],
            ),
            if (current != null)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (library != null)
                        TrackCover(
                          key: ValueKey(current.location),
                          documents: controller.documents,
                          track: current,
                        ),
                      Text(
                        controller.metadata?.title ?? current.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          controller.metadata?.artist ?? '未知艺术家',
                          controller.metadata?.album,
                        ].nonNulls.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (controller.metadataWarning != null)
                        Text(
                          controller.metadataWarning!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      Row(
                        children: [
                          Text(formatPosition(state.position)),
                          Expanded(
                            // Keep overlay descendants together across changes
                            // in seek availability. Windows removes reparented
                            // subtrees before applying semantics updates.
                            child: KeyedSubtree(
                              key: ValueKey(state.duration > Duration.zero),
                              child: Slider(
                                key: const ValueKey('playback-seek'),
                                value: state.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0,
                                      state.duration.inMilliseconds
                                          .toDouble()
                                          .clamp(1, double.infinity),
                                    ),
                                max: state.duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1, double.infinity),
                                onChanged: state.duration > Duration.zero
                                    ? (value) => unawaited(
                                        controller.seek(
                                          Duration(milliseconds: value.round()),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          Text(formatPosition(state.duration)),
                        ],
                      ),
                      PlaybackControls(playback: controller),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
