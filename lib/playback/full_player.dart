import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show DragStartBehavior, PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/compact_dialog.dart';
import '../core/desktop_navigation.dart';
import '../library/group_pages.dart';
import '../library/library_controller.dart';
import '../library/track_cover.dart';
import 'cover_viewer.dart';
import 'playback_controller.dart';
import 'player_background.dart';
import 'playback_page.dart' show formatPosition;
import 'queue_page.dart';
import 'player_actions.dart';
import 'playback_status.dart';
import 'lyrics.dart';
import 'sleep_timer_sheet.dart';
import 'slide_dismiss_route.dart';

const fullPlayerRouteName = '/player';

Future<void> openFullPlayer(BuildContext context) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return pushAppPage(
    context,
    () => SlideDismissRoute(
      name: fullPlayerRouteName,
      reduceMotion: reduceMotion,
      builder: (_) => const FullPlayer(),
    ),
  );
}

class PlayerSeek extends StatefulWidget {
  const PlayerSeek({
    required this.playback,
    this.onSeek,
    this.inlineTimes = false,
    super.key,
  });
  final PlaybackController playback;
  final VoidCallback? onSeek;
  final bool inlineTimes;

  static const _sliderHeight = 44.0;
  static const _timeStyle = TextStyle(fontSize: 12, height: 1.25);

  static double _timeHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(_timeStyle.fontSize!) *
              _timeStyle.height!)
          .ceilToDouble();

  static double heightOf(BuildContext context) =>
      _sliderHeight + _timeHeight(context);

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
        !widget.playback.canSeek) {
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
    if (entryId == null ||
        !playback.canSeek ||
        playback.queue.current?.entryId != entryId) {
      return;
    }
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
    final enabled = playback.canSeek;
    final max = enabled ? state.duration.inMilliseconds.toDouble() : 1.0;
    final position = Duration(
      milliseconds:
          (enabled ? _preview ?? state.position.inMilliseconds.toDouble() : 0.0)
              .clamp(0, max)
              .round(),
    );
    final slider = KeyedSubtree(
      key: ValueKey(enabled),
      child: Semantics(
        label: enabled ? '播放进度' : '播放进度暂不可用',
        child: SizedBox(
          height: widget.inlineTimes ? 26 : PlayerSeek._sliderHeight,
          child: Slider(
            padding: EdgeInsets.zero,
            key: const ValueKey('playback-seek'),
            semanticFormatterCallback: (value) =>
                '${formatPosition(Duration(milliseconds: value.round()))}，总长 ${formatPosition(state.duration)}',
            label: formatPosition(position),
            value: position.inMilliseconds.toDouble().clamp(0, max),
            max: max,
            secondaryTrackValue: enabled
                ? state.buffer.inMilliseconds.toDouble().clamp(0.0, max)
                : null,
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
    );
    final elapsedLabel = enabled ? formatPosition(position) : '--:--';
    final totalLabel = enabled ? formatPosition(state.duration) : '--:--';
    final timeStyle = widget.inlineTimes
        ? PlayerSeek._timeStyle.copyWith(
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          )
        : PlayerSeek._timeStyle;
    Widget time(String label, TextAlign alignment) => Text(
      label,
      style: timeStyle,
      textAlign: alignment,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final elapsed = time(elapsedLabel, TextAlign.start);
    final total = time(totalLabel, TextAlign.end);
    if (widget.inlineTimes) {
      final measure = TextPainter(
        text: TextSpan(
          text: totalLabel,
          style: DefaultTextStyle.of(context).style.merge(timeStyle),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final labelWidth = measure.width.ceilToDouble();
      measure.dispose();
      return LayoutBuilder(
        builder: (context, constraints) {
          // Equal timer slots keep the track centered on the transport buttons.
          final width = math.min(labelWidth, constraints.maxWidth * .22);
          return Row(
            spacing: math.min(12, constraints.maxWidth * .05),
            children: [
              SizedBox(width: width, child: elapsed),
              Expanded(
                child: enabled
                    ? slider
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: () {},
                        child: slider,
                      ),
              ),
              SizedBox(width: width, child: total),
            ],
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        slider,
        SizedBox(
          height: PlayerSeek._timeHeight(context),
          child: Row(
            children: [
              Expanded(child: elapsed),
              const SizedBox(width: 8),
              Expanded(child: total),
            ],
          ),
        ),
      ],
    );
  }
}

class FullPlayer extends ConsumerStatefulWidget {
  const FullPlayer({super.key});

  @override
  ConsumerState<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends ConsumerState<FullPlayer> {
  bool _showLyrics = false;

  Future<void> _openLyrics() async {
    final route = ModalRoute.of(context);
    if (_showLyrics || route == null || !route.isCurrent) return;
    route.addLocalHistoryEntry(
      LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (mounted) setState(() => _showLyrics = false);
        },
      ),
    );
    setState(() => _showLyrics = true);
  }

  void _back() => Navigator.maybePop(context);

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playbackProvider);
    final library = ref.watch(libraryProvider);
    final route = ModalRoute.of(context);
    final showLyrics = _showLyrics;
    final dismissRoute = !showLyrics && route is SlideDismissRoute
        ? route
        : null;
    if (playback == null) {
      return const Scaffold(body: Center(child: Text('播放器尚未就绪')));
    }
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final simple = playback.simpleLayout;
        final actions = PlayerActions(
          playback: playback,
          library: library,
          openLyrics: _openLyrics,
        );

        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(label: showLyrics ? '返回播放器' : '关闭播放页'):
                      _back,
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: dismissRoute == null
                      ? null
                      : (_) => dismissRoute.startDrag(),
                  onVerticalDragUpdate: dismissRoute == null
                      ? null
                      : (details) => dismissRoute.moveDrag(
                          details.primaryDelta ?? 0,
                          MediaQuery.sizeOf(context).height,
                        ),
                  onVerticalDragEnd: dismissRoute == null
                      ? null
                      : (details) => dismissRoute.finishDrag(
                          velocity: details.primaryVelocity ?? 0,
                        ),
                  onVerticalDragCancel: dismissRoute == null
                      ? null
                      : () => dismissRoute.finishDrag(cancelled: true),
                  onSecondaryTapUp: simple || showLyrics
                      ? null
                      : (details) => unawaited(
                          actions.show(
                            context,
                            globalPosition: details.globalPosition,
                          ),
                        ),
                  child: PlayerBackground(
                    playback: playback,
                    immersive: simple,
                    lyricsVisible: showLyrics,
                    builder: (context, controlColor, lyricsColor) => SafeArea(
                      child: AnimatedSwitcher(
                        duration:
                            simple && !MediaQuery.disableAnimationsOf(context)
                            ? const Duration(milliseconds: 240)
                            : Duration.zero,
                        layoutBuilder: (active, previous) => Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final child in [...previous, ?active])
                              ExcludeSemantics(
                                key: child.key,
                                excluding: child != active,
                                child: ExcludeFocus(
                                  excluding: child != active,
                                  child: IgnorePointer(
                                    ignoring: child != active,
                                    child: child,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        child: showLyrics
                            ? ImmersiveLyrics(
                                playback: playback,
                                onBack: _back,
                                foreground: lyricsColor,
                              )
                            : Column(
                                children: [
                                  _StandardPlayerControl(
                                    visible: !simple,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        6,
                                        8,
                                        0,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: playback.current == null
                                                ? const SizedBox.shrink()
                                                : _PlayerHeading(
                                                    playback: playback,
                                                    library: library,
                                                  ),
                                          ),
                                          PlayerActionsButton(actions: actions),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _PlayerBody(
                                      playback: playback,
                                      library: library,
                                      simple: simple,
                                      openLyrics: _openLyrics,
                                      controlColor: controlColor,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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

// Keep the artwork and the main controls in the same layout in both modes.
class _StandardPlayerControl extends StatelessWidget {
  const _StandardPlayerControl({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !visible,
    child: ExcludeFocus(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: playerLayoutFadeDuration(context),
          opacity: visible ? 1 : 0,
          child: TickerMode(enabled: visible, child: child),
        ),
      ),
    ),
  );
}

class _PlayerHeading extends StatelessWidget {
  const _PlayerHeading({required this.playback, required this.library});
  final PlaybackController playback;
  final LibraryController? library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final title = playbackTitle(playback);
    final source = library;
    final artists = playback.changingTrack
        ? const <String>[]
        : artistNames(playback.metadata?.artist);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayerTitle(text: title, style: theme.textTheme.titleLarge!),
        if (artists.isEmpty)
          Text(
            playbackArtist(playback),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else
          SingleChildScrollView(
            key: ValueKey(playback.queue.current?.entryId),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, artist) in artists.indexed) ...[
                  if (index > 0) Text(' / ', style: style),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: source == null
                        ? null
                        : () => openArtistTracks(
                            context,
                            source,
                            playback,
                            artist,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(artist, style: style),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PlayerTitle extends StatelessWidget {
  const _PlayerTitle({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (MediaQuery.disableAnimationsOf(context) ||
          constraints.maxWidth <= 0) {
        return title;
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final titleWidth = painter.width;
      final titleHeight = painter.height;
      painter.dispose();
      return titleWidth <= constraints.maxWidth
          ? title
          : SizedBox(
              height: titleHeight,
              child: _MarqueeTitle(
                key: ValueKey((text, titleWidth, constraints.maxWidth)),
                text: text,
                style: style,
                distance: titleWidth + 40,
              ),
            );
    },
  );
}

class _MarqueeTitle extends StatefulWidget {
  const _MarqueeTitle({
    required this.text,
    required this.style,
    required this.distance,
    super.key,
  });

  final String text;
  final TextStyle style;
  final double distance;

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    const pause = 1000.0;
    final travel = widget.distance / 34 * 1000;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (pause + travel).round()),
    )..repeat();
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: pause),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: widget.distance),
        weight: travel,
      ),
    ]).animate(_controller);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    excludeSemantics: true,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: _offset,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 40,
            children: [
              Text(widget.text, style: widget.style, maxLines: 1),
              Text(widget.text, style: widget.style, maxLines: 1),
            ],
          ),
          builder: (_, child) => Transform.translate(
            offset: Offset(-_offset.value, 0),
            child: child,
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _PlayerBody extends StatelessWidget {
  const _PlayerBody({
    required this.playback,
    required this.library,
    required this.simple,
    required this.openLyrics,
    required this.controlColor,
  });
  final Color? controlColor;
  final PlaybackController playback;
  final LibraryController? library;
  final bool simple;
  final Future<void> Function() openLyrics;

  Widget _artwork(BuildContext context, double size) {
    final current = playback.current;
    final artwork = ClipRRect(
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
                  currentArtwork: true,
                ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: current != null,
      label: '歌曲封面',
      hint: '点按查看歌词，长按查看原图',
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: current == null ? null : openLyrics,
        onLongPress: current == null
            ? null
            : () => showCoverViewer(
                context,
                documents: playback.documents,
                track: current,
                previewSize: size,
              ),
        child: current == null
            ? artwork
            : Hero(tag: playerCoverHeroTag(current), child: artwork),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.album_outlined, size: 72),
            const SizedBox(height: 20),
            Text(
              '还没有播放歌曲',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text('从曲库选择歌曲后，会在这里显示封面和播放控制。', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      showPlaybackQueue(context, playback, library),
                  icon: const Icon(Icons.queue_music),
                  label: const Text('查看播放队列'),
                ),
              ],
            ),
            if (playback.sleep.active) ...[
              const SizedBox(height: 16),
              SleepTimerStatus(playback: playback),
            ],
            PlaybackFeedback(playback: playback),
          ],
        ),
      ),
    ),
  );

  Widget _controls(BuildContext context) {
    final transport = PlaybackControls(
      playback: playback,
      onToggleLayout: playback.toggleLayout,
      large: true,
      immersiveColor: controlColor,
    );
    final mode = PlaybackModeButton(playback: playback);
    final timer = IconButton(
      tooltip: playback.sleep.active ? '睡眠定时已开启' : '睡眠定时',
      icon: Icon(
        playback.sleep.active ? Icons.bedtime : Icons.bedtime_outlined,
      ),
      onPressed: () => showSleepTimer(context, playback),
    );
    final queue = IconButton(
      tooltip: '播放队列',
      icon: const Icon(Icons.queue_music),
      onPressed: () => showPlaybackQueue(context, playback, library),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        transport,
        _StandardPlayerControl(
          visible: !simple,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [mode, timer, queue],
              ),
              if (playback.sleep.active) SleepTimerStatus(playback: playback),
            ],
          ),
        ),
        PlaybackFeedback(playback: playback, color: controlColor),
      ],
    );
  }

  Widget _coverArea(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: _artwork(
        context,
        math.min(500.0, constraints.biggest.shortestSide),
      ),
    ),
  );

  Widget _seekBar([double? width]) => _StandardPlayerControl(
    visible: !simple,
    child: SizedBox(
      width: width,
      child: PlayerSeek(playback: playback),
    ),
  );

  Widget _coverWithSeek() => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final seekHeight = PlayerSeek.heightOf(context);
      final size = math.min(
        500.0,
        math.min(
          constraints.maxWidth,
          math.max(0.0, constraints.maxHeight - seekHeight - gap),
        ),
      );
      return Column(
        children: [
          Expanded(child: Center(child: _artwork(context, size))),
          const SizedBox(height: gap),
          _seekBar(size),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (playback.current == null) return _empty(context);
      final horizontal = constraints.maxWidth < 360 ? 14.0 : 22.0;
      final width = math.max(0.0, constraints.maxWidth - horizontal * 2);
      final height = constraints.maxHeight;
      final controls = _controls(context);
      final wide = width >= 760 && height >= 320;
      final short =
          height < 355 ||
          MediaQuery.textScalerOf(context).scale(16) > 26;
      final Widget content;
      if (wide && !short) {
        content = Row(
          key: const ValueKey('player-wide-layout'),
          spacing: 32,
          children: [
            Expanded(child: _coverArea(context)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [_seekBar(), const SizedBox(height: 8), controls],
              ),
            ),
          ],
        );
      } else if (short) {
        final coverSize = math.min(width, (height * .62).clamp(92.0, 440.0));
        content = SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              _artwork(context, coverSize),
              _seekBar(coverSize),
              controls,
            ],
          ),
        );
      } else {
        content = Column(
          key: const ValueKey('player-stacked-layout'),
          children: [
            Expanded(child: _coverWithSeek()),
            const SizedBox(height: 8),
            controls,
          ],
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 10),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? 1080 : 560,
            ),
            child: content,
          ),
        ),
      );
    },
  );
}

class ImmersiveLyrics extends ConsumerStatefulWidget {
  const ImmersiveLyrics({
    required this.playback,
    required this.foreground,
    this.onBack,
    super.key,
  });

  final PlaybackController playback;
  final VoidCallback? onBack;
  final Color foreground;
  @override
  ConsumerState<ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends ConsumerState<ImmersiveLyrics> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _pageFocus = FocusNode(debugLabel: 'lyrics-page');
  final _lyricsFocus = FocusNode(debugLabel: 'lyrics-lines');
  bool _follow = true;
  int _pointers = 0, _followGeneration = 0;
  int _last = -2;
  double _swipeStartX = 0;
  Lyrics? _lyrics;
  List<double> _offsets = [], _heights = [];
  double _width = 0, _viewportHeight = 0;
  TextScaler? _textScaler;
  TextStyle? _baseStyle;
  TextDirection? _direction;
  Locale? _locale;
  bool _boldText = false;
  static const _linePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 8);
  static const _translationGap = 3.0;
  static const _original = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.28,
  );
  static const _translation = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  @override
  void initState() {
    super.initState();
    widget.playback.addListener(_changed);
    FocusManager.instance.addEarlyKeyEventHandler(_keyEvent);
  }

  // Observe before child scrolling shortcuts consume keys. Never
  // consume the event, and leave keys on other routes entirely untouched.
  KeyEventResult _keyEvent(KeyEvent event) {
    if (!mounted ||
        !_pageFocus.hasFocus ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
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
    }
    return KeyEventResult.ignored;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _goCurrent() {
    setState(() {
      _follow = true;
      _last = -2;
      _followGeneration++;
    });
  }

  void _pauseFollow() {
    if (!_follow) return;
    setState(() {
      _follow = false;
      _followGeneration++;
    });
  }

  void _releasePointer(PointerEvent _) {
    setState(() {
      _pointers = math.max(0, _pointers - 1);
      if (_pointers == 0 && _follow) _last = -2;
    });
  }

  void _metrics(
    BuildContext context,
    Lyrics lyrics,
    double width,
    TextScaler scaler,
  ) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final boldText = MediaQuery.boldTextOf(context);
    if (identical(lyrics, _lyrics) &&
        width == _width &&
        scaler == _textScaler &&
        baseStyle == _baseStyle &&
        direction == _direction &&
        locale == _locale &&
        boldText == _boldText) {
      return;
    }
    final changedTrack = !identical(lyrics, _lyrics);
    _lyrics = lyrics;
    _width = width;
    _textScaler = scaler;
    _baseStyle = baseStyle;
    _direction = direction;
    _locale = locale;
    _boldText = boldText;
    _last = -2;
    _followGeneration++;
    if (changedTrack) _follow = true;
    _offsets = [];
    _heights = [];
    var offset = 0.0;
    for (final line in lyrics.lines) {
      var height = _linePadding.vertical;
      for (var i = 0; i < line.texts.length; i++) {
        final painter = TextPainter(
          text: TextSpan(text: line.texts[i], style: _lineStyle(i)),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          textHeightBehavior: const ui.TextHeightBehavior(),
        )..layout(maxWidth: width);
        height += painter.height + (i == 0 ? 0 : _translationGap);
        painter.dispose();
      }
      _offsets.add(offset);
      _heights.add(height);
      offset += height;
    }
  }

  TextStyle _lineStyle(int index) {
    var style = _baseStyle!.merge(index == 0 ? _original : _translation);
    if (_boldText) style = style.copyWith(fontWeight: FontWeight.bold);
    return style.copyWith(inherit: false, decoration: TextDecoration.none);
  }

  Widget _lines(BuildContext context, BoxConstraints constraints) {
    final playback = widget.playback;
    final lyrics = playback.lyrics.value;
    final entryId = playback.queue.current?.entryId;
    final seekEnabled = entryId != null && playback.canSeek;
    final active = lyrics.indexAt(playback.player.state.position);
    final padding = math.max(12.0, (constraints.maxWidth - 720) / 2);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    _metrics(
      context,
      lyrics,
      math.max(
        0.0,
        constraints.maxWidth - padding * 2 - _linePadding.horizontal,
      ),
      scaler,
    );
    if (_viewportHeight != constraints.maxHeight) {
      _viewportHeight = constraints.maxHeight;
      _last = -2;
      _followGeneration++;
    }
    if (lyrics.lines.isEmpty) {
      return _lyricsStatus(lyrics);
    }
    final viewport = constraints.maxHeight;
    final lineHeight = scaler.scale(_original.fontSize!) * _original.height!;
    final anchor = viewport / 2 - math.min(lineHeight, viewport * .12);
    final headSpace = math.max(0.0, anchor - _heights.first / 2);
    final tailSpace = math.max(0.0, viewport - anchor - _heights.last / 2);
    if (_follow && _pointers == 0 && active != _last) {
      final reanchor = _last == -2;
      _last = active;
      final target = active < 0
          ? 0.0
          : headSpace + _offsets[active] + _heights[active] / 2 - anchor;
      final generation = ++_followGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_follow ||
            _pointers != 0 ||
            generation != _followGeneration ||
            !_scroll.hasClients) {
          return;
        }
        final offset = target.clamp(0.0, _scroll.position.maxScrollExtent);
        if (reducedMotion || reanchor) {
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
    final desktop = Theme.of(context).platform == TargetPlatform.windows;
    final masked = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: desktop ? const [0, .06, .84, .97] : const [0, .06, .91, 1],
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
            onPointerSignal: (_) => _pauseFollow(),
            onPointerPanZoomStart: (_) => _pauseFollow(),
            child: ListView.builder(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                padding,
                headSpace,
                padding,
                tailSpace,
              ),
              itemCount: lyrics.lines.length,
              itemExtentBuilder: (index, _) => _heights[index],
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                void seekLine() {
                  if (!seekEnabled || !playback.canSeek) return;
                  _goCurrent();
                  unawaited(
                    playback.seek(
                      Duration(milliseconds: line.milliseconds),
                      expectedEntryId: entryId,
                    ),
                  );
                }

                final distance = (index - active).abs();
                final alpha = active < 0
                    ? .84
                    : switch (distance) {
                        0 => 1.0,
                        1 => .84,
                        2 => .73,
                        _ => .63,
                      };
                return Semantics(
                  selected: index == active,
                  button: true,
                  enabled: seekEnabled,
                  onTap: seekEnabled ? seekLine : null,
                  // Reading another line with a screen reader is browsing, just
                  // like dragging the list. Do not pull focus back on each tick.
                  onDidGainAccessibilityFocus: _pauseFollow,
                  label:
                      '${line.texts.join('，')}，${formatPosition(Duration(milliseconds: line.milliseconds))}',
                  child: ExcludeSemantics(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: seekEnabled ? seekLine : null,
                        child: Padding(
                          padding: _linePadding,
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
                                    padding: EdgeInsets.only(
                                      top: i == 0 ? 0 : _translationGap,
                                    ),
                                    child: Text(
                                      line.texts[i],
                                      locale: _locale,
                                      textAlign: TextAlign.start,
                                      textHeightBehavior:
                                          const ui.TextHeightBehavior(),
                                      style: _lineStyle(i)
                                          .copyWith(color: widget.foreground),
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
              },
            ),
          ),
        ),
      ),
    );
    return desktop ? ClipRect(child: masked) : masked;
  }

  Widget _lyricsStatus(Lyrics lyrics) {
    final playback = widget.playback;
    final hasSong = playback.current != null;
    final loading = hasSong && lyrics.status == LyricsStatus.loading;
    final title = !hasSong
        ? '尚未选择歌曲'
        : switch (lyrics.status) {
            LyricsStatus.loading => '正在读取歌词',
            LyricsStatus.unreadable => '歌词暂时无法显示',
            LyricsStatus.untimed => '歌词没有可用时间戳',
            _ => '这首歌暂无同步歌词',
          };
    final name = playback.current?.name;
    final dot = name?.lastIndexOf('.') ?? -1;
    final companion = name == null
        ? null
        : '${dot > 0 ? name.substring(0, dot) : name}.lrc';
    final explanation = !hasSong
        ? '返回播放器或曲库后即可选择歌曲。'
        : switch (lyrics.status) {
            LyricsStatus.loading => '歌词读取完成后会自动显示，不影响继续播放。',
            LyricsStatus.unreadable =>
              '支持 UTF-8 或带 BOM 的 UTF-16 歌词；文件过大或内容损坏时无法显示。',
            LyricsStatus.untimed => '同步歌词需要带时间戳，例如 [00:12.30]歌词内容。',
            _ => '只读取音频同目录、同文件主名的 LRC 文件。',
          };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading && !MediaQuery.disableAnimationsOf(context))
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: widget.foreground),
                )
              else
                Icon(
                  loading ? Icons.hourglass_empty : Icons.lyrics_outlined,
                  size: 36,
                  color: widget.foreground,
                ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: widget.foreground),
                ),
              ),
              if (hasSong) ...[
                const SizedBox(height: 8),
                Text(
                  playbackTitle(playback),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Text(explanation, textAlign: TextAlign.center),
              if (hasSong && !loading && companion != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  '对应歌词文件：$companion',
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  if (lyrics.status == LyricsStatus.unreadable &&
                      lyrics.message != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: widget.foreground,
                      ),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (dialog) => CompactAlertDialog(
                          title: const Text('歌词读取详情'),
                          content: SingleChildScrollView(
                            child: SelectableText(lyrics.message!),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('查看读取详情'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _pageFocus,
    autofocus: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: widget.onBack == null
          ? null
          : (details) => _swipeStartX = details.globalPosition.dx,
      onHorizontalDragEnd: widget.onBack == null
          ? null
          : (details) {
              if (details.globalPosition.dx - _swipeStartX >= 56) {
                widget.onBack?.call();
              }
            },
      child: Material(
        type: MaterialType.transparency,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _pointers++,
          onPointerUp: _releasePointer,
          onPointerCancel: _releasePointer,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: widget.foreground),
            child: LayoutBuilder(builder: _lines),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_keyEvent);
    widget.playback.removeListener(_changed);
    _pageFocus.dispose();
    _lyricsFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
