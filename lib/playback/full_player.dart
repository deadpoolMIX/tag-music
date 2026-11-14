import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_controller.dart';
import '../library/song_information.dart';
import '../library/track_cover.dart';
import 'playback_controller.dart';
import 'playback_page.dart' show formatPosition;
import 'queue_page.dart';
import 'lyrics.dart';
import 'sleep_timer_sheet.dart';

Future<void> openFullPlayer(BuildContext context) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const FullPlayer()));

class PlayerBackground extends StatefulWidget {
  const PlayerBackground({
    required this.playback,
    required this.child,
    super.key,
  });
  final PlaybackController playback;
  final Widget child;
  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground> {
  String? _key;
  Future<Uint8List?>? _cover;
  @override
  Widget build(BuildContext context) {
    final track = widget.playback.current;
    final key = track == null
        ? null
        : '${track.location}|${track.size}|${track.modified}';
    if (key != _key) {
      _key = key;
      _cover = track == null
          ? null
          : widget.playback.documents.cachedCover(track);
    }
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.secondaryContainer,
                scheme.surface,
                scheme.primaryContainer,
              ],
            ),
          ),
        ),
        FutureBuilder<Uint8List?>(
          key: ValueKey(_key),
          future: _cover,
          builder: (_, snapshot) => snapshot.data == null
              ? const SizedBox.shrink()
              : ExcludeSemantics(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: Opacity(
                        opacity: .25,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: false,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .60),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class PlayerSeek extends StatelessWidget {
  const PlayerSeek({required this.playback, this.onSeek, super.key});
  final PlaybackController playback;
  final VoidCallback? onSeek;
  @override
  Widget build(BuildContext context) {
    final state = playback.player.state;
    final max = state.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    return Row(
      children: [
        Text(formatPosition(state.position)),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(state.duration > Duration.zero),
            child: Slider(
              key: const ValueKey('playback-seek'),
              semanticFormatterCallback: (value) =>
                  formatPosition(Duration(milliseconds: value.round())),
              value: state.position.inMilliseconds.toDouble().clamp(0, max),
              max: max,
              onChanged: state.duration > Duration.zero
                  ? (value) {
                      onSeek?.call();
                      unawaited(
                        playback.seek(Duration(milliseconds: value.round())),
                      );
                    }
                  : null,
            ),
          ),
        ),
        Text(formatPosition(state.duration)),
      ],
    );
  }
}

class FullPlayer extends ConsumerWidget {
  const FullPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    if (playback == null) {
      return const Scaffold(body: Center(child: Text('播放器尚未就绪')));
    }
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final current = playback.current;
        final simple = playback.simpleLayout;
        void menu(String value) {
          switch (value) {
            case 'layout':
              playback.toggleLayout();
            case 'stop':
              unawaited(playback.stop());
            case 'info':
              final tracks = library?.tracks.where(
                (t) => t.song.id == playback.currentSongId,
              );
              if (tracks?.isNotEmpty == true) {
                unawaited(showSongInformation(context, tracks!.first));
              }
          }
        }

        Widget more() => PopupMenuButton<String>(
          tooltip: '更多播放操作',
          onSelected: menu,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'layout',
              child: Text(simple ? '切换标准布局' : '切换简洁布局'),
            ),
            const PopupMenuItem(value: 'stop', child: Text('停止播放')),
            if (library?.tracks.any(
                  (t) => t.song.id == playback.currentSongId,
                ) ==
                true)
              const PopupMenuItem(value: 'info', child: Text('歌曲信息')),
          ],
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.maybePop(context),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                title: simple ? null : const Text('正在播放'),
                actions: [more()],
              ),
              body: GestureDetector(
                onSecondaryTapUp: (details) async {
                  final choice = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      0,
                      0,
                    ),
                    items: [
                      PopupMenuItem(
                        value: 'layout',
                        child: Text(simple ? '切换标准布局' : '切换简洁布局'),
                      ),
                    ],
                  );
                  if (choice != null) menu(choice);
                },
                child: PlayerBackground(
                  playback: playback,
                  child: SafeArea(
                    minimum: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final coverSize = math
                            .min(
                              440.0,
                              math.min(
                                constraints.maxWidth - 64,
                                constraints.maxHeight * (simple ? .62 : .47),
                              ),
                            )
                            .clamp(96.0, 440.0);
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!simple) ...[
                                        Text(
                                          playback.metadata?.title ??
                                              current?.name ??
                                              '未播放',
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          playback.metadata?.artist ?? '未知歌手',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 24),
                                      ],
                                      Semantics(
                                        button: true,
                                        label: '打开沉浸歌词',
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                          onTap: current == null
                                              ? null
                                              : () => Navigator.push<void>(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ImmersiveLyrics(
                                                          playback: playback,
                                                        ),
                                                  ),
                                                ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                            child: SizedBox(
                                              width: coverSize,
                                              height: coverSize,
                                              child: ColoredBox(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainer
                                                    .withValues(alpha: .6),
                                                child: current == null
                                                    ? const Icon(
                                                        Icons.album_outlined,
                                                        size: 96,
                                                      )
                                                    : TrackCover(
                                                        documents:
                                                            playback.documents,
                                                        track: current,
                                                        size: coverSize,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      if (!simple)
                                        PlayerSeek(playback: playback),
                                      PlaybackControls(
                                        playback: playback,
                                        onToggleLayout: playback.toggleLayout,
                                      ),
                                      if (!simple) ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            PlaybackModeButton(
                                              playback: playback,
                                            ),
                                            IconButton(
                                              tooltip: playback.sleep.active
                                                  ? '睡眠定时已开启'
                                                  : '睡眠定时',
                                              icon: Icon(
                                                playback.sleep.active
                                                    ? Icons.bedtime
                                                    : Icons.bedtime_outlined,
                                              ),
                                              onPressed: () => showSleepTimer(
                                                context,
                                                playback,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '播放队列',
                                              icon: const Icon(
                                                Icons.queue_music,
                                              ),
                                              onPressed: () =>
                                                  showPlaybackQueue(
                                                    context,
                                                    playback,
                                                    library,
                                                  ),
                                            ),
                                            more(),
                                          ],
                                        ),
                                        if (playback.error != null ||
                                            playback.playbackNotice != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              playback.error ??
                                                  playback.playbackNotice!,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ImmersiveLyrics extends StatefulWidget {
  const ImmersiveLyrics({required this.playback, super.key});
  final PlaybackController playback;
  @override
  State<ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends State<ImmersiveLyrics> {
  final _scroll = ScrollController();
  Timer? _hide;
  bool _controls = true, _follow = true;
  int _last = -2;
  Lyrics? _lyrics;
  List<double> _offsets = [], _heights = [];
  double _width = 0, _scale = 0;
  static const _original = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w300,
    height: 1.5,
  );
  static const _translation = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w300,
    height: 1.5,
  );
  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_changed);
    _arm();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _arm() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          (MediaQuery.accessibleNavigationOf(context) ||
              WidgetsBinding.instance.semanticsEnabled)) {
        return;
      }
      setState(() => _controls = false);
    });
  }

  void _reveal() {
    setState(() => _controls = true);
    _arm();
  }

  void _goCurrent() {
    setState(() {
      _follow = true;
      _last = -2;
    });
    _reveal();
  }

  void _metrics(Lyrics lyrics, double width, TextScaler scaler) {
    final scale = scaler.scale(26);
    if (identical(lyrics, _lyrics) && width == _width && scale == _scale) {
      return;
    }
    final changedTrack = !identical(lyrics, _lyrics);
    _lyrics = lyrics;
    _width = width;
    _scale = scale;
    _last = -2;
    if (changedTrack) _follow = true;
    _offsets = [];
    _heights = [];
    var offset = 0.0;
    for (final line in lyrics.lines) {
      var height = 32.0;
      for (var i = 0; i < line.texts.length; i++) {
        final painter = TextPainter(
          text: TextSpan(
            text: line.texts[i],
            style: i == 0 ? _original : _translation,
          ),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: width);
        height += painter.height + (i == 0 ? 0 : 6);
        painter.dispose();
      }
      _offsets.add(offset);
      _heights.add(height);
      offset += height;
    }
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final lyrics = playback.lyrics.value;
    final active = lyrics.indexAt(playback.player.state.position);
    final showControls =
        _controls ||
        (MediaQuery.accessibleNavigationOf(context) ||
            WidgetsBinding.instance.semanticsEnabled);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: PlayerBackground(
            playback: playback,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _reveal,
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final padding = math.max(
                            24.0,
                            (constraints.maxWidth - 720) / 2,
                          );
                          _metrics(
                            lyrics,
                            constraints.maxWidth - padding * 2,
                            MediaQuery.textScalerOf(context),
                          );
                          if (_follow && active != _last) {
                            _last = active;
                            final target = active < 0 ? 0.0 : _offsets[active];
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted || !_follow || !_scroll.hasClients) {
                                return;
                              }
                              unawaited(
                                _scroll.animateTo(
                                  target.clamp(
                                    0,
                                    _scroll.position.maxScrollExtent,
                                  ),
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOut,
                                ),
                              );
                            });
                          }
                          if (lyrics.lines.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  lyrics.message ?? '暂无歌词',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          return ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (rect) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black,
                                Colors.black,
                                Colors.transparent,
                              ],
                              stops: [0, .12, .83, 1],
                            ).createShader(rect),
                            child: NotificationListener<ScrollStartNotification>(
                              onNotification: (notice) {
                                if (notice.dragDetails != null) {
                                  setState(() => _follow = false);
                                  _reveal();
                                }
                                return false;
                              },
                              child: Listener(
                                onPointerSignal: (_) {
                                  setState(() => _follow = false);
                                  _reveal();
                                },
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: EdgeInsets.fromLTRB(
                                    padding,
                                    constraints.maxHeight * .30,
                                    padding,
                                    constraints.maxHeight * .65,
                                  ),
                                  itemCount: lyrics.lines.length,
                                  itemExtentBuilder: (index, _) =>
                                      _heights[index],
                                  itemBuilder: (context, index) {
                                    final line = lyrics.lines[index];
                                    final distance = (index - active).abs();
                                    final alpha = active < 0
                                        ? .65
                                        : distance == 0
                                        ? 1.0
                                        : distance == 1
                                        ? .65
                                        : distance == 2
                                        ? .45
                                        : .30;
                                    return Semantics(
                                      selected: index == active,
                                      button: true,
                                      label:
                                          '${line.texts.join('，')}，${formatPosition(Duration(milliseconds: line.milliseconds))}',
                                      child: ExcludeSemantics(
                                        child: InkWell(
                                          onTap: () {
                                            _goCurrent();
                                            unawaited(
                                              playback.seek(
                                                Duration(
                                                  milliseconds:
                                                      line.milliseconds,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            child: AnimatedOpacity(
                                              duration: const Duration(
                                                milliseconds: 250,
                                              ),
                                              opacity: alpha,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (
                                                    var i = 0;
                                                    i < line.texts.length;
                                                    i++
                                                  )
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        top: i == 0 ? 0 : 6,
                                                      ),
                                                      child: Text(
                                                        line.texts[i],
                                                        style:
                                                            (i == 0
                                                                    ? _original
                                                                    : _translation)
                                                                .copyWith(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onSurface,
                                                                ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (showControls)
                      Positioned(left: 8, top: 8, child: BackButton()),
                    if (!_follow)
                      Positioned(
                        right: 16,
                        top: 16,
                        child: FilledButton.tonalIcon(
                          onPressed: _goCurrent,
                          icon: const Icon(Icons.my_location),
                          label: const Text('回到当前句'),
                        ),
                      ),
                    if (showControls)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 8,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: .92),
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PlayerSeek(
                                  playback: playback,
                                  onSeek: _goCurrent,
                                ),
                                PlaybackControls(playback: playback),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.playback.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }
}
