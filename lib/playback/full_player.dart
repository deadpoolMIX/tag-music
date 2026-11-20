import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/compact_dialog.dart';
import '../library/library_controller.dart';
import '../library/track_cover.dart';
import 'playback_controller.dart';
import 'playback_page.dart' show formatPosition;
import 'queue_page.dart';
import 'player_actions.dart';
import 'playback_status.dart';
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: ValueKey(enabled),
          child: Semantics(
            label: enabled ? '播放进度' : '播放进度暂不可用',
            child: Slider(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  enabled ? formatPosition(position) : '--:--',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  enabled ? formatPosition(state.duration) : '--:--',
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
        final actions = PlayerActions(
          playback: playback,
          library: library,
          toggleLayout: playback.toggleLayout,
          openLyrics: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: '/lyrics'),
              builder: (_) => ImmersiveLyrics(playback: playback),
            ),
          ),
        );
        Widget more() => PlayerActionsButton(actions: actions);
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
                onSecondaryTapUp: (details) => unawaited(
                  actions.show(context, globalPosition: details.globalPosition),
                ),
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
                  settings: const RouteSettings(name: '/lyrics'),
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
      Tooltip(
        message: playbackTitle(playback),
        child: Text(
          playbackTitle(playback),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 6),
      Tooltip(
        message: playbackArtist(playback),
        child: Text(
          playbackArtist(playback),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

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
                if (Navigator.canPop(context))
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回上一页'),
                  ),
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

  Widget _controls(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!simple) ...[
        PlaybackActivity(playback: playback),
        PlayerSeek(playback: playback),
      ],
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
        PlaybackFeedback(playback: playback),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (playback.current == null) return _empty(context);
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

class ImmersiveLyrics extends ConsumerStatefulWidget {
  const ImmersiveLyrics({required this.playback, super.key});
  final PlaybackController playback;
  @override
  ConsumerState<ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends ConsumerState<ImmersiveLyrics> {
  final _scroll = ScrollController();
  final _pageFocus = FocusNode(debugLabel: 'lyrics-page');
  final _lyricsFocus = FocusNode(debugLabel: 'lyrics-lines');
  bool _follow = true;
  int _pointers = 0, _followGeneration = 0;
  int _last = -2;
  Lyrics? _lyrics;
  List<double> _offsets = [], _heights = [];
  double _width = 0, _viewportHeight = 0;
  TextScaler? _textScaler;
  TextStyle? _baseStyle;
  TextDirection? _direction;
  Locale? _locale;
  bool _boldText = false;
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
      var height = 32.0;
      for (var i = 0; i < line.texts.length; i++) {
        final painter = TextPainter(
          text: TextSpan(text: line.texts[i], style: _lineStyle(i)),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          textHeightBehavior: const ui.TextHeightBehavior(),
        )..layout(maxWidth: width);
        height += painter.height + (i == 0 ? 0 : 6);
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
    final padding = math.max(24.0, (constraints.maxWidth - 720) / 2);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _metrics(
      context,
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
            _pointers != 0 ||
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
      return _lyricsStatus(lyrics);
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
            onPointerSignal: (_) => _pauseFollow(),
            onPointerPanZoomStart: (_) => _pauseFollow(),
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
                  enabled: seekEnabled,
                  onTap: seekEnabled ? seekLine : null,
                  // Reading another line with a screen reader is browsing, just
                  // like dragging the list. Do not pull focus back on each tick.
                  onDidGainAccessibilityFocus: _pauseFollow,
                  label:
                      '${line.texts.join('，')}，${formatPosition(Duration(milliseconds: line.milliseconds))}',
                  child: ExcludeSemantics(
                    child: InkWell(
                      onTap: seekEnabled ? seekLine : null,
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
                                    locale: _locale,
                                    textAlign: TextAlign.start,
                                    textHeightBehavior:
                                        const ui.TextHeightBehavior(),
                                    style: _lineStyle(i).copyWith(
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
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(),
                )
              else
                Icon(
                  loading ? Icons.hourglass_empty : Icons.lyrics_outlined,
                  size: 36,
                ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
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
                  TextButton.icon(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回播放器'),
                  ),
                  if (lyrics.status == LyricsStatus.unreadable &&
                      lyrics.message != null)
                    TextButton.icon(
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
  Widget build(BuildContext context) => CallbackShortcuts(
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
          child: Material(
            type: MaterialType.transparency,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _pointers++,
              onPointerUp: _releasePointer,
              onPointerCancel: _releasePointer,
              child: SafeArea(
                child: Column(
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: BackButton(),
                    ),
                    Expanded(child: LayoutBuilder(builder: _lines)),
                  ],
                ),
              ),
            ),
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
