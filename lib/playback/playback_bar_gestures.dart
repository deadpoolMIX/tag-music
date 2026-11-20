import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;
import 'package:flutter/material.dart';

import 'playback_controller.dart';

class PlaybackBarGestures extends StatefulWidget {
  const PlaybackBarGestures({
    required this.playback,
    required this.onOpenPlayer,
    required this.child,
    super.key,
  });

  final PlaybackController? playback;
  final VoidCallback? onOpenPlayer;
  final Widget child;

  @override
  State<PlaybackBarGestures> createState() => _PlaybackBarGesturesState();
}

class _PlaybackBarGesturesState extends State<PlaybackBarGestures> {
  static const _swipeDistance = 36.0;
  Offset _start = Offset.zero;

  void _startDrag(DragStartDetails details) => _start = details.globalPosition;

  void _switchTrack(DragEndDetails details) {
    final playback = widget.playback;
    if (playback == null) return;
    final distance = details.globalPosition.dx - _start.dx;
    if (distance <= -_swipeDistance && playback.canNext) {
      playback.next();
    } else if (distance >= _swipeDistance && playback.canPrevious) {
      playback.previous();
    }
  }

  void _openPlayer(DragEndDetails details) {
    if (_start.dy - details.globalPosition.dy >= _swipeDistance) {
      widget.onOpenPlayer?.call();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    supportedDevices: const {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    },
    dragStartBehavior: DragStartBehavior.down,
    onHorizontalDragStart: widget.playback == null ? null : _startDrag,
    onHorizontalDragEnd: widget.playback == null ? null : _switchTrack,
    onVerticalDragStart: widget.onOpenPlayer == null ? null : _startDrag,
    onVerticalDragEnd: widget.onOpenPlayer == null ? null : _openPlayer,
    child: widget.child,
  );
}
