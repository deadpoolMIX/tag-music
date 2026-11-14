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
                          errorBuilder: (_, error, stack) =>
                              const SizedBox.shrink(),
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

class PlayerSeek extends StatefulWidget {
  const PlayerSeek({required this.playback, this.onSeek, super.key});
  final PlaybackController playback;
  final VoidCallback? onSeek;
  @override
  State<PlayerSeek> createState() => _PlayerSeekState();
}

class _PlayerSeekState extends State<PlayerSeek> {
  double? _preview;
  String? _entryId;

  @override
  void didUpdateWidget(PlayerSeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playback != widget.playback ||
        widget.playback.queue.current?.entryId != _entryId ||
        widget.playback.player.state.duration <= Duration.zero) {
      _preview = null;
      _entryId = null;
    }
  }

  void _commit(double value) {
    final playback = widget.playback;
    final entryId = _entryId;
    setState(() {
      _preview = null;
      _entryId = null;
    });
    // A natural track change during a held drag must not seek the new track.
    if (entryId == null || playback.queue.current?.entryId != entryId) return;
    widget.onSeek?.call();
    unawaited(
      playback.seek(
        Duration(milliseconds: value.round()),
        expectedEntryId: entryId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final state = playback.player.state;
    final max = state.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final position = Duration(
      milliseconds: (_preview ?? state.position.inMilliseconds.toDouble())
          .clamp(0, max)
          .round(),
    );
    final enabled = playback.current != null && state.duration > Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: ValueKey(enabled),
          child: Semantics(
            label: '播放进度',
            child: Slider(
              key: const ValueKey('playback-seek'),
              semanticFormatterCallback: (value) =>
                  formatPosition(Duration(milliseconds: value.round())),
              label: formatPosition(position),
              value: position.inMilliseconds.toDouble().clamp(0, max),
              max: max,
              onChangeStart: enabled
                  ? (value) => setState(() {
                      _entryId = playback.queue.current?.entryId;
                      _preview = value;
                    })
                  : null,
              onChanged: enabled
                  ? (value) => setState(() => _preview = value)
                  : null,
              onChangeEnd: enabled ? _commit : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatPosition(position),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatPosition(state.duration),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
        final simple = playback.simpleLayout;
        void menu(String value) {
          switch (value) {
            case 'layout':
              playback.toggleLayout();
            case 'stop':
              unawaited(playback.stop());
            case 'sleep':
              unawaited(showSleepTimer(context, playback));
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
            PopupMenuItem(
              value: 'sleep',
              child: Text(playback.sleep.active ? '管理睡眠定时' : '睡眠定时'),
            ),
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
                    child: _PlayerBody(
                      playback: playback,
                      library: library,
                      simple: simple,
                      more: more(),
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

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.playback,
    required this.library,
    required this.simple,
    required this.more,
  });
  final PlaybackController playback;
  final LibraryController? library;
  final bool simple;
  final Widget more;

  Widget _artwork(BuildContext context, double size) {
    final current = playback.current;
    return Semantics(
      button: true,
      enabled: current != null,
      label: '打开沉浸歌词',
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: current == null
            ? null
            : () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ImmersiveLyrics(playback: playback),
                ),
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox.square(
            dimension: size,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainer
                  .withValues(alpha: .6),
              child: current == null
                  ? Icon(Icons.album_outlined, size: math.min(96, size))
                  : TrackCover(
                      documents: playback.documents,
                      track: current,
                      size: size,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        playback.metadata?.title ?? playback.current?.name ?? '未播放',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      Text(
        playback.metadata?.artist ?? '未知歌手',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  Widget _controls(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!simple) PlayerSeek(playback: playback),
      PlaybackControls(
        playback: playback,
        onToggleLayout: playback.toggleLayout,
      ),
      if (!simple) ...[
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            PlaybackModeButton(playback: playback),
            IconButton(
              tooltip: playback.sleep.active ? '睡眠定时已开启' : '睡眠定时',
              icon: Icon(
                playback.sleep.active ? Icons.bedtime : Icons.bedtime_outlined,
              ),
              onPressed: () => showSleepTimer(context, playback),
            ),
            IconButton(
              tooltip: '播放队列',
              icon: const Icon(Icons.queue_music),
              onPressed: () => showPlaybackQueue(context, playback, library),
            ),
            more,
          ],
        ),
        if (playback.sleep.active) SleepTimerStatus(playback: playback),
        if (playback.error != null || playback.playbackNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              playback.error ?? playback.playbackNotice!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 360 ? 16.0 : 32.0;
      final width = math.max(0.0, constraints.maxWidth - horizontalPadding * 2);
      final wide = !simple && width >= 760;
      final target = wide
          ? math.min(width * .44, constraints.maxHeight - 48)
          : constraints.maxHeight * (simple ? .62 : .45);
      final coverSize = math.min(
        width,
        math.min(440.0, math.max(96.0, target)),
      );
      final artwork = _artwork(context, coverSize);
      final controls = _controls(context);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1080 : 560),
                child: wide
                    ? Row(
                        key: const ValueKey('player-wide-layout'),
                        children: [
                          Expanded(child: Center(child: artwork)),
                          const SizedBox(width: 32),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _heading(context),
                                const SizedBox(height: 24),
                                controls,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('player-stacked-layout'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!simple) ...[
                            _heading(context),
                            const SizedBox(height: 24),
                          ],
                          artwork,
                          const SizedBox(height: 28),
                          controls,
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ImmersiveLyrics extends StatefulWidget {
  const ImmersiveLyrics({required this.playback, super.key});
  final PlaybackController playback;
  @override
  State<ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends State<ImmersiveLyrics> {
  final _scroll = ScrollController();
  final _pageFocus = FocusNode(debugLabel: 'lyrics-page');
  final _lyricsFocus = FocusNode(debugLabel: 'lyrics-lines');
  final _headerFocus = FocusNode(debugLabel: 'lyrics-header');
  final _controlsFocus = FocusNode(debugLabel: 'lyrics-controls');
  Timer? _hide;
  bool _controls = true, _follow = true, _keyboardInput = false;
  int _pointers = 0, _followGeneration = 0;
  int _last = -2;
  Lyrics? _lyrics;
  List<double> _offsets = [], _heights = [];
  double _width = 0, _scale = 0, _viewportHeight = 0;
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
    FocusManager.instance.addEarlyKeyEventHandler(_keyEvent);
    _arm();
  }

  // Observe before child shortcuts consume slider or scrolling keys. Never
  // consume the event, and leave keys on other routes entirely untouched.
  KeyEventResult _keyEvent(KeyEvent event) {
    if (!mounted ||
        !_pageFocus.hasFocus ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    _keyboardInput = true;
    if ((_lyricsFocus.hasFocus || _pageFocus.hasPrimaryFocus) &&
        const [
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.home,
          LogicalKeyboardKey.end,
        ].contains(event.logicalKey)) {
      _pauseFollow();
    } else {
      _reveal();
    }
    return KeyEventResult.ignored;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _arm() {
    _hide?.cancel();
    if (_holdingControls) return;
    _hide = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          _holdingControls ||
          (MediaQuery.accessibleNavigationOf(context) ||
              WidgetsBinding.instance.semanticsEnabled)) {
        return;
      }
      setState(() => _controls = false);
    });
  }

  bool get _holdingControls =>
      _pointers > 0 ||
      (_keyboardInput && (_headerFocus.hasFocus || _controlsFocus.hasFocus));

  void _controlFocusChanged(bool focused) {
    if (focused) {
      _reveal();
    } else {
      _arm();
    }
  }

  void _reveal() {
    setState(() => _controls = true);
    _arm();
  }

  void _goCurrent() {
    setState(() {
      _follow = true;
      _last = -2;
      _followGeneration++;
    });
    _reveal();
  }

  void _pauseFollow() {
    setState(() {
      _follow = false;
      _followGeneration++;
    });
    _reveal();
  }

  void _browseWithPointer() {
    _keyboardInput = false;
    _pauseFollow();
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
    _followGeneration++;
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

  Widget _lines(BuildContext context, BoxConstraints constraints) {
    final playback = widget.playback;
    final lyrics = playback.lyrics.value;
    final entryId = playback.queue.current?.entryId;
    final active = lyrics.indexAt(playback.player.state.position);
    final padding = math.max(24.0, (constraints.maxWidth - 720) / 2);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _metrics(
      lyrics,
      math.max(0.0, constraints.maxWidth - padding * 2),
      MediaQuery.textScalerOf(context),
    );
    if (_viewportHeight != constraints.maxHeight) {
      _viewportHeight = constraints.maxHeight;
      _last = -2;
      _followGeneration++;
    }
    if (_follow && _pointers == 0 && active != _last) {
      _last = active;
      final target = active < 0 ? 0.0 : _offsets[active];
      final generation = ++_followGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_follow ||
            generation != _followGeneration ||
            !_scroll.hasClients) {
          return;
        }
        final offset = target.clamp(0.0, _scroll.position.maxScrollExtent);
        if (reducedMotion) {
          _scroll.jumpTo(offset);
        } else {
          unawaited(
            _scroll.animateTo(
              offset,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            ),
          );
        }
      });
    }
    if (lyrics.lines.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(lyrics.message ?? '暂无歌词', textAlign: TextAlign.center),
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
          if (notice.dragDetails != null) _pauseFollow();
          return false;
        },
        child: Focus(
          focusNode: _lyricsFocus,
          skipTraversal: true,
          child: Listener(
            onPointerSignal: (_) => _browseWithPointer(),
            onPointerPanZoomStart: (_) => _browseWithPointer(),
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                padding,
                constraints.maxHeight * .30,
                padding,
                constraints.maxHeight * .65,
              ),
              itemCount: lyrics.lines.length,
              itemExtentBuilder: (index, _) => _heights[index],
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final distance = (index - active).abs();
                final alpha = active < 0
                    ? .65
                    : switch (distance) {
                        0 => 1.0,
                        1 => .65,
                        2 => .45,
                        _ => .30,
                      };
                return Semantics(
                  selected: index == active,
                  button: true,
                  label:
                      '${line.texts.join('，')}，${formatPosition(Duration(milliseconds: line.milliseconds))}',
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: () {
                        _goCurrent();
                        if (entryId == null) return;
                        unawaited(
                          playback.seek(
                            Duration(milliseconds: line.milliseconds),
                            expectedEntryId: entryId,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: AnimatedOpacity(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          opacity: alpha,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < line.texts.length; i++)
                                Padding(
                                  padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                                  child: Text(
                                    line.texts[i],
                                    style: (i == 0 ? _original : _translation)
                                        .copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
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
      ),
    );
  }

  Widget _controlPanel(BuildContext context, double maxHeight) => Align(
    alignment: Alignment.bottomCenter,
    child: Focus(
      focusNode: _controlsFocus,
      skipTraversal: true,
      onFocusChange: _controlFocusChanged,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlayerSeek(playback: widget.playback, onSeek: _goCurrent),
                  PlaybackControls(playback: widget.playback),
                  if (widget.playback.sleep.active)
                    SleepTimerStatus(playback: widget.playback),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final showControls =
        _controls ||
        MediaQuery.accessibleNavigationOf(context) ||
        WidgetsBinding.instance.semanticsEnabled;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Focus(
        focusNode: _pageFocus,
        autofocus: true,
        child: Scaffold(
          body: PlayerBackground(
            playback: widget.playback,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                _keyboardInput = false;
                _pointers++;
                _reveal();
              },
              onPointerUp: (_) {
                setState(() => _pointers = math.max(0, _pointers - 1));
                _arm();
              },
              onPointerCancel: (_) {
                setState(() => _pointers = math.max(0, _pointers - 1));
                _arm();
              },
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      if (showControls || !_follow)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Focus(
                            focusNode: _headerFocus,
                            skipTraversal: true,
                            onFocusChange: _controlFocusChanged,
                            child: Row(
                              children: [
                                if (showControls) const BackButton(),
                                const Spacer(),
                                if (!_follow)
                                  Flexible(
                                    child: FilledButton.tonalIcon(
                                      onPressed: _goCurrent,
                                      icon: const Icon(Icons.my_location),
                                      label: const Text('回到当前句'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(child: LayoutBuilder(builder: _lines)),
                      if (showControls)
                        _controlPanel(context, constraints.maxHeight * .45),
                    ],
                  ),
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
    FocusManager.instance.removeEarlyKeyEventHandler(_keyEvent);
    widget.playback.removeListener(_changed);
    _pageFocus.dispose();
    _lyricsFocus.dispose();
    _headerFocus.dispose();
    _controlsFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
