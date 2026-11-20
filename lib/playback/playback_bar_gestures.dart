import 'dart:async';

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show TickerCanceled;

import 'playback_controller.dart';
import 'playback_queue.dart' show QueueEntry;

class PlaybackBarGestures extends StatefulWidget {
  const PlaybackBarGestures({
    required this.playback,
    required this.onOpenPlayer,
    required this.builder,
    super.key,
  });

  final PlaybackController? playback;
  final VoidCallback? onOpenPlayer;
  final Widget Function(BuildContext, QueueEntry? preview) builder;

  @override
  State<PlaybackBarGestures> createState() => _PlaybackBarGesturesState();
}

class _PlaybackBarGesturesState extends State<PlaybackBarGestures>
    with SingleTickerProviderStateMixin {
  static const _swipeDistance = 36.0;
  static const _settleDuration = Duration(milliseconds: 180);
  late final _slide = AnimationController(
    vsync: this,
    lowerBound: -1,
    value: 0,
  );
  Offset _start = Offset.zero;
  ({PlaybackController playback, QueueEntry entry})? _source;
  QueueEntry? _preview;
  bool _settling = false;

  bool get _showPreview =>
      _preview != null &&
      identical(widget.playback?.queue.current, _source?.entry);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.of(context) && _slide.isAnimating) _slide.stop();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _startHorizontal(DragStartDetails details) {
    if (_settling) return;
    _start = details.globalPosition;
    final playback = widget.playback;
    final entry = playback?.queue.current;
    _source = playback == null || entry == null
        ? null
        : (playback: playback, entry: entry);
  }

  void _moveHorizontal(DragUpdateDetails details, double width) {
    final source = _source;
    if (_settling ||
        source == null ||
        !identical(widget.playback, source.playback) ||
        !identical(source.playback.queue.current, source.entry) ||
        !width.isFinite ||
        width <= 0 ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final distance = details.globalPosition.dx - _start.dx;
    final target = source.playback.queue.manualNeighbor(distance < 0 ? 1 : -1);
    _preview = identical(target, source.entry) ? null : target;
    _slide.value = _preview == null ? 0 : (distance / width).clamp(-1.0, 1.0);
  }

  void _endHorizontal(DragEndDetails details) {
    final source = _source;
    if (_settling || source == null) return;
    final distance = details.globalPosition.dx - _start.dx;
    final direction = distance < 0 ? 1 : -1;
    final target =
        distance.abs() >= _swipeDistance &&
            identical(widget.playback, source.playback) &&
            identical(source.playback.queue.current, source.entry)
        ? source.playback.queue.manualNeighbor(direction)
        : null;
    unawaited(_settle(direction, target));
  }

  void _cancelHorizontal() {
    if (!_settling && _source != null) unawaited(_settle(0, null));
  }

  Future<void> _settle(int direction, QueueEntry? target) async {
    final source = _source!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _settling = true;
    try {
      if (target != null) {
        if (!reduceMotion && !identical(target, source.entry)) {
          _preview = target;
          await _slide
              .animateTo(
                -direction.toDouble(),
                duration: _settleDuration,
                curve: Curves.easeOutCubic,
              )
              .orCancel;
        }
        if (!mounted || !identical(widget.playback, source.playback)) return;
        final expected = (from: source.entry, to: target);
        if (direction > 0) {
          await source.playback.next(expected: expected);
        } else {
          await source.playback.previous(expected: expected);
        }
      }
      if (mounted && _showPreview && _slide.value != 0 && !reduceMotion) {
        await _slide
            .animateTo(0, duration: _settleDuration, curve: Curves.easeOutCubic)
            .orCancel;
      }
    } on TickerCanceled {
      // The bar was hidden or unmounted before the switch.
    } finally {
      _source = null;
      _preview = null;
      _settling = false;
      if (mounted) _slide.value = 0;
    }
  }

  Widget _panel(
    BuildContext context,
    QueueEntry? entry,
    double x, {
    bool preview = false,
  }) => FractionalTranslation(
    key: ValueKey(entry?.entryId),
    translation: Offset(x, 0),
    child: IgnorePointer(
      ignoring: preview || x != 0,
      child: ExcludeFocus(
        excluding: preview,
        child: ExcludeSemantics(
          excluding: preview,
          child: widget.builder(context, preview ? entry : null),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: widget.playback == null ? null : _startHorizontal,
      onHorizontalDragUpdate: widget.playback == null
          ? null
          : (details) => _moveHorizontal(details, constraints.maxWidth),
      onHorizontalDragEnd: widget.playback == null ? null : _endHorizontal,
      onHorizontalDragCancel: widget.playback == null
          ? null
          : _cancelHorizontal,
      onVerticalDragStart: widget.onOpenPlayer == null
          ? null
          : (details) => _start = details.globalPosition,
      onVerticalDragEnd: widget.onOpenPlayer == null
          ? null
          : (details) {
              if (_start.dy - details.globalPosition.dy >= _swipeDistance) {
                widget.onOpenPlayer?.call();
              }
            },
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            final x = _showPreview ? _slide.value : 0.0;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                _panel(context, widget.playback?.queue.current, x),
                if (x != 0)
                  _panel(
                    context,
                    _preview,
                    x + (x < 0 ? 1 : -1),
                    preview: true,
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
