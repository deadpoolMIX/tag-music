import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';

String formatPosition(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class PlaybackPage extends ConsumerWidget {
  const PlaybackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackProvider);
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
                            controller.index == index && state.playing
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
                          Text(formatPosition(state.duration)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '上一首',
                            onPressed: controller.index > 0
                                ? controller.previous
                                : null,
                            icon: const Icon(Icons.skip_previous),
                          ),
                          IconButton.filled(
                            key: const ValueKey('play-pause'),
                            tooltip: state.playing ? '暂停' : '播放',
                            onPressed: controller.togglePlayPause,
                            icon: Icon(
                              state.playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          IconButton(
                            tooltip: '停止',
                            onPressed: controller.stop,
                            icon: const Icon(Icons.stop),
                          ),
                          IconButton(
                            tooltip: '下一首',
                            onPressed:
                                controller.index + 1 < controller.tracks.length
                                ? controller.next
                                : null,
                            icon: const Icon(Icons.skip_next),
                          ),
                        ],
                      ),
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
