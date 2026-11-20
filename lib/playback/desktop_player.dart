import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/desktop_navigation.dart';
import '../core/desktop_title_bar.dart';
import '../library/library_controller.dart';
import '../library/song_selection.dart';
import '../library/track_cover.dart';
import 'cover_viewer.dart';
import 'full_player.dart' show ImmersiveLyrics, PlayerSeek;
import 'playback_bar_gestures.dart';
import 'playback_controller.dart';
import 'playback_status.dart';
import 'player_actions.dart';
import 'player_background.dart';
import 'player_volume.dart';
import 'queue_page.dart';
import 'sleep_timer_sheet.dart';

const _playerLayer = '/desktop/player';
const _titleDividerHeight = 1.0;

/// The content navigator can change pages without replacing the playback bar.
class DesktopPlaybackFrame extends ConsumerStatefulWidget {
  const DesktopPlaybackFrame({
    required this.navigation,
    required this.libraryPage,
    required this.lightTheme,
    required this.darkTheme,
    super.key,
  });

  final DesktopNavigation navigation;
  final Widget libraryPage;
  final ThemeData lightTheme, darkTheme;

  @override
  ConsumerState<DesktopPlaybackFrame> createState() =>
      _DesktopPlaybackFrameState();
}

class _DesktopPlaybackFrameState extends ConsumerState<DesktopPlaybackFrame> {
  final _heroes = MaterialApp.createMaterialHeroController();

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final theme = Theme.of(context);
    final selecting = SongSelectionScope.isSelectingOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.navigation.activeRoute, playback]),
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
      builder: (context, content) {
        final expanded = widget.navigation.top?.settings.name == _playerLayer;
        return PlayerBackground(
          playback: playback,
          immersive: expanded,
          lyricsVisible: true,
          surfaceColor: theme.colorScheme.surface,
          shareBackdrop: true,
          builder: (context, _, lyricsColor) {
            final chromeTheme = !expanded
                ? theme
                : lyricsColor == Colors.white
                ? widget.darkTheme
                : widget.lightTheme;
            return _DesktopPlayerPalette(
              lyricsColor: lyricsColor,
              child: Column(
                children: [
                  Theme(data: chromeTheme, child: const DesktopTitleBar()),
                  Divider(
                    height: _titleDividerHeight,
                    color: expanded
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                  Expanded(child: content!),
                  Visibility(
                    visible: !selecting,
                    maintainState: true,
                    child: Theme(
                      data: chromeTheme,
                      child: _DesktopPlaybackBar(
                        navigation: widget.navigation,
                        expanded: expanded,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopPlayerPalette extends InheritedWidget {
  const _DesktopPlayerPalette({
    required this.lyricsColor,
    required super.child,
  });

  final Color lyricsColor;

  static Color lyricsOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DesktopPlayerPalette>()!
      .lyricsColor;

  @override
  bool updateShouldNotify(_DesktopPlayerPalette oldWidget) =>
      oldWidget.lyricsColor != lyricsColor;
}

class _DesktopPlaybackBar extends ConsumerWidget {
  const _DesktopPlaybackBar({required this.navigation, required this.expanded});

  final DesktopNavigation navigation;
  final bool expanded;

  void _toggle(BuildContext context) {
    if (navigation.top?.settings.name == _playerLayer) {
      navigation.back();
      return;
    }
    final duration = playerLayoutFadeDuration(context);
    pushAppPage(
      context,
      () => PageRouteBuilder<void>(
        settings: const RouteSettings(name: _playerLayer),
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (_, _, _) => const _DesktopPlayerLayer(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Widget _nowPlaying(
    BuildContext context,
    PlaybackController? playback,
    LibraryController? library,
    QueueEntry? preview,
  ) {
    final display = playbackBarTrack(playback, library, preview);
    final current = display.track;
    final theme = Theme.of(context);
    return Padding(
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
                  display.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  display.subtitle,
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
    );
  }

  Widget _transport(
    BuildContext context,
    PlaybackController? playback, {
    required bool preview,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (playback != null)
        PlaybackControls(
          playback: playback,
          blockBackgroundTap: true,
        )
      else
        const IconButton.filled(
          tooltip: '播放',
          onPressed: null,
          icon: Icon(Icons.play_arrow),
        ),
      if (playback != null)
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: PlayerSeek(
            playback: playback,
            inlineTimes: true,
            preview: preview,
          ),
        )
      else
        const SizedBox(height: 26),
    ],
  );

  Widget _auxiliary(
    BuildContext context,
    PlaybackController? playback,
    LibraryController? library,
  ) {
    if (playback == null) return const SizedBox.shrink();
    final queueOpen = navigation.top?.settings.name == playbackQueueRouteName;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (library != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            // Leave the player layer alone when the tag button is disabled.
            onTap: () {},
            child: PlaybackTagButton(
              playback: playback,
              library: library,
              iconSize: 20,
            ),
          ),
        PlaybackModeButton(playback: playback),
        IconButton(
          tooltip: playback.sleep.active
              ? sleepTimerProgressLabel(playback)
              : '睡眠定时',
          icon: Icon(
            playback.sleep.active ? Icons.bedtime : Icons.bedtime_outlined,
          ),
          onPressed: () => showSleepTimer(context, playback),
        ),
        IconButton(
          key: const ValueKey('open-playback-queue'),
          tooltip: queueOpen ? '收起播放队列' : '播放队列',
          onPressed: queueOpen
              ? navigation.back
              : () => showPlaybackQueue(context, playback, library),
          icon: const Icon(Icons.queue_music),
        ),
        PlayerVolume(playback: playback),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    final toggle = playback == null ? null : () => _toggle(context);
    return Material(
      key: const ValueKey('global-minibar'),
      type: MaterialType.transparency,
      child: PlaybackBarGestures(
        playback: playback,
        onOpenPlayer: expanded ? null : toggle,
        builder: (context, preview) {
          final theme = Theme.of(context);
          final feedback = preview == null ? playback?.playerFeedback : null;
          final identity = Row(
            children: [
              Expanded(
                child: Semantics(
                  button: toggle == null ? null : true,
                  label: expanded ? '收起播放器' : '展开播放器',
                  onTap: toggle,
                  child: _nowPlaying(context, playback, library, preview),
                ),
              ),
              if (playback != null && feedback != null)
                IconButton(
                  tooltip: feedback,
                  icon: Icon(
                    playback.error == null
                        ? Icons.info_outline
                        : Icons.error_outline,
                  ),
                  onPressed: () => showPlaybackFeedback(context, playback),
                ),
            ],
          );
          final controls = _transport(
            context,
            playback,
            preview: preview != null,
          );
          final auxiliary = _auxiliary(context, playback, library);
          return Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: toggle,
              onSecondaryTapUp: playback == null
                  ? null
                  : (details) =>
                        PlayerActions(
                          playback: playback,
                          library: library,
                        ).show(
                          context,
                          globalPosition: details.globalPosition,
                          includeClose: false,
                        ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Divider(
                      height: 1,
                      color: expanded
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant,
                    ),
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            if (width < 640) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (width < 320) ...[
                                    identity,
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: auxiliary,
                                    ),
                                  ] else
                                    Row(
                                      children: [
                                        Expanded(child: identity),
                                        auxiliary,
                                      ],
                                    ),
                                  controls,
                                ],
                              );
                            }
                            return Row(
                              spacing: 12,
                              children: [
                                SizedBox(
                                  width: (width * .18).clamp(138.0, 246.0),
                                  child: identity,
                                ),
                                Expanded(child: controls),
                                auxiliary,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
    final lyricsColor = _DesktopPlayerPalette.lyricsOf(context);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            // Crop the full-window backdrop to the area between the bars.
            top: -DesktopTitleBar.height - _titleDividerHeight,
            left: 0,
            right: 0,
            height: MediaQuery.sizeOf(context).height,
            child: PlayerBackground.sharedBackdropOf(context),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final margin = (constraints.maxWidth * .03).clamp(6.0, 36.0);
                final gap = (constraints.maxWidth * .045).clamp(8.0, 64.0);
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: margin,
                    vertical: 12,
                  ),
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
        ],
      ),
    );
  }
}
