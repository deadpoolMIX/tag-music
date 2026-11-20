import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/desktop_navigation.dart';
import '../library/library_controller.dart';
import '../library/track_cover.dart';
import 'cover_viewer.dart';
import 'full_player.dart' show ImmersiveLyrics, PlayerSeek;
import 'playback_controller.dart';
import 'playback_status.dart';
import 'player_actions.dart';
import 'player_background.dart';
import 'player_volume.dart';
import 'queue_page.dart';
import 'sleep_timer_sheet.dart';
import 'slide_dismiss_route.dart';

const _playerLayer = '/desktop/player';

/// The content navigator can change pages without replacing the playback bar.
class DesktopPlaybackFrame extends StatefulWidget {
  const DesktopPlaybackFrame({
    required this.navigation,
    required this.libraryPage,
    super.key,
  });

  final DesktopNavigation navigation;
  final Widget libraryPage;

  @override
  State<DesktopPlaybackFrame> createState() => _DesktopPlaybackFrameState();
}

class _DesktopPlaybackFrameState extends State<DesktopPlaybackFrame> {
  final _heroes = MaterialApp.createMaterialHeroController();

  @override
  Widget build(BuildContext context) => Material(
    child: Column(
      children: [
        Expanded(
          child: HeroControllerScope(
            controller: _heroes,
            child: Navigator(
              observers: [widget.navigation],
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => widget.libraryPage,
              ),
            ),
          ),
        ),
        _DesktopPlaybackBar(navigation: widget.navigation),
      ],
    ),
  );
}

class _DesktopPlaybackBar extends ConsumerWidget {
  const _DesktopPlaybackBar({required this.navigation});

  final DesktopNavigation navigation;

  void _toggle(BuildContext context) {
    if (navigation.top?.settings.name == _playerLayer) {
      navigation.back();
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    pushAppPage(
      context,
      () => SlideDismissRoute(
        name: _playerLayer,
        reduceMotion: reduceMotion,
        builder: (_) => const _DesktopPlayerLayer(),
      ),
    );
  }

  Widget _nowPlaying(
    BuildContext context,
    PlaybackController? playback,
    LibraryController? library,
    VoidCallback? toggle,
  ) {
    final current = playback?.current;
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: toggle,
      onSecondaryTapUp: playback == null
          ? null
          : (details) =>
                PlayerActions(playback: playback, library: library).show(
                  context,
                  globalPosition: details.globalPosition,
                  includeClose: false,
                ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          spacing: 10,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: current == null || playback == null
                  ? Container(
                      width: 46,
                      height: 46,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.album_outlined, size: 23),
                    )
                  : TrackCover(
                      documents: playback.documents,
                      track: current,
                      size: 46,
                      currentArtwork: true,
                    ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playback == null ? '未播放' : playbackTitle(playback),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    current == null || playback == null
                        ? '选择歌曲开始播放'
                        : playback.changingTrack
                        ? '正在装载歌曲'
                        : playback.currentLyric ?? playbackArtist(playback),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transport(
    BuildContext context,
    PlaybackController? playback,
    LibraryController? library,
  ) {
    final queueOpen = navigation.top?.settings.name == playbackQueueRouteName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (playback != null) ...[
              PlaybackModeButton(playback: playback),
              IconButton(
                tooltip: playback.sleep.active
                    ? sleepTimerProgressLabel(playback)
                    : '睡眠定时',
                icon: Icon(
                  playback.sleep.active
                      ? Icons.bedtime
                      : Icons.bedtime_outlined,
                ),
                onPressed: () => showSleepTimer(context, playback),
              ),
              PlaybackControls(playback: playback),
              IconButton(
                key: const ValueKey('open-playback-queue'),
                tooltip: queueOpen ? '收起播放队列' : '播放队列',
                onPressed: queueOpen
                    ? navigation.back
                    : () => showPlaybackQueue(context, playback, library),
                icon: const Icon(Icons.queue_music),
              ),
              PlayerVolume(playback: playback),
            ] else
              const IconButton.filled(
                tooltip: '播放',
                onPressed: null,
                icon: Icon(Icons.play_arrow),
              ),
          ],
        ),
        if (playback != null)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: PlayerSeek(playback: playback, inlineTimes: true),
          )
        else
          const SizedBox(height: 26),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('global-minibar'),
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    iconSize: 20,
                    minimumSize: const Size.square(36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    navigation.activeRoute,
                    playback,
                  ]),
                  builder: (context, _) {
                    final expanded =
                        navigation.top?.settings.name == _playerLayer;
                    final toggle = playback == null
                        ? null
                        : () => _toggle(context);
                    final identity = _nowPlaying(
                      context,
                      playback,
                      library,
                      toggle,
                    );
                    final controls = _transport(context, playback, library);
                    final disclosure = IconButton(
                      tooltip: expanded ? '收起播放器' : '展开播放器',
                      icon: Icon(
                        expanded ? Icons.expand_more : Icons.expand_less,
                      ),
                      onPressed: toggle,
                    );
                    final feedback = playback?.playerFeedback;
                    final trailing = Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (playback != null && feedback != null)
                          IconButton(
                            tooltip: feedback,
                            icon: Icon(
                              playback.error == null
                                  ? Icons.info_outline
                                  : Icons.error_outline,
                            ),
                            onPressed: () =>
                                showPlaybackFeedback(context, playback),
                          ),
                        disclosure,
                      ],
                    );
                    return LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 520
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: identity),
                                    trailing,
                                  ],
                                ),
                                controls,
                              ],
                            )
                          : Row(
                              spacing: 12,
                              children: [
                                Expanded(child: identity),
                                SizedBox(
                                  width: (constraints.maxWidth * .49).clamp(
                                    284.0,
                                    580.0,
                                  ),
                                  child: controls,
                                ),
                                Expanded(child: trailing),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPlayerLayer extends ConsumerWidget {
  const _DesktopPlayerLayer();

  Widget _cover(
    BuildContext context,
    PlaybackController playback,
    double size,
  ) {
    final track = playback.current;
    final artwork = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox.square(
        dimension: size,
        child: track == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Icon(Icons.album_outlined, size: math.min(96, size)),
              )
            : TrackCover(
                documents: playback.documents,
                track: track,
                size: size,
                currentArtwork: true,
              ),
      ),
    );
    if (track == null) return artwork;
    return Semantics(
      label: '歌曲封面',
      hint: '长按查看原图',
      child: GestureDetector(
        onLongPress: () => showCoverViewer(
          context,
          documents: playback.documents,
          track: track,
          previewSize: size,
        ),
        child: Hero(tag: playerCoverHeroTag(track), child: artwork),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    if (playback == null) {
      return const Material(child: Center(child: Text('播放器尚未就绪')));
    }
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => PlayerBackground(
        playback: playback,
        immersive: true,
        lyricsVisible: true,
        builder: (context, _, lyricsColor) => SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final margin = (constraints.maxWidth * .03).clamp(6.0, 36.0);
              final gap = (constraints.maxWidth * .045).clamp(8.0, 64.0);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: margin, vertical: 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1360),
                    child: Row(
                      spacing: gap,
                      children: [
                        Expanded(
                          flex: 5,
                          child: LayoutBuilder(
                            builder: (context, space) => Center(
                              child: _cover(
                                context,
                                playback,
                                math.min(560.0, space.biggest.shortestSide),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: ImmersiveLyrics(
                            playback: playback,
                            foreground: lyricsColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
