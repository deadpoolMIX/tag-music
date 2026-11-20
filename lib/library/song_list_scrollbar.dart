import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SongListScrollbar extends StatefulWidget {
  const SongListScrollbar({
    required this.controller,
    required this.visible,
    required this.child,
    super.key,
  });

  static const double dragWidth = 20;

  final ScrollController controller;
  final bool visible;
  final Widget child;

  @override
  State<SongListScrollbar> createState() => _SongListScrollbarState();
}

class _SongListScrollbarState extends State<SongListScrollbar> {
  static const double _barWidth = 4;
  static const double _endInset = 4;
  static const double _minThumbHeight = 36;

  Drag? _drag;
  double? _grabFraction;

  ScrollPosition? get _position {
    final controller = widget.controller;
    if (!controller.hasClients) return null;
    final position = controller.position;
    return position.hasContentDimensions && position.hasPixels
        ? position
        : null;
  }

  void _startDrag(
    DragStartDetails details,
    ScrollPosition position,
    double thumbTop,
    double thumbHeight,
  ) {
    final grab = (details.localPosition.dy - thumbTop) / thumbHeight;
    // Keep the point under the pointer when grabbed next to the thumb. Elsewhere
    // on the edge, bring the middle of the thumb to the pointer.
    setState(() => _grabFraction = grab >= 0 && grab <= 1 ? grab : .5);
    _drag = position.drag(details, () => _drag = null);
  }

  void _updateDrag(
    DragUpdateDetails details,
    ScrollPosition position,
    double thumbHeight,
    double travel,
  ) {
    final grab = _grabFraction;
    if (grab == null || _drag == null) return;
    final targetFraction =
        ((details.localPosition.dy - _endInset - thumbHeight * grab) / travel)
            .clamp(0.0, 1.0);
    final target =
        position.minScrollExtent +
        (position.maxScrollExtent - position.minScrollExtent) * targetFraction;
    final delta = position.pixels - target;
    if (delta == 0) return;
    // Use the ScrollPosition's drag so cover loading sees one continuous scroll.
    _drag?.update(
      DragUpdateDetails(
        delta: Offset(0, delta),
        primaryDelta: delta,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _endDrag() {
    if (_grabFraction == null) return;
    _drag?.cancel();
    setState(() => _grabFraction = null);
  }

  void _onPointerSignal(PointerSignalEvent event, ScrollPosition position) {
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (_) => position.pointerScroll(event.scrollDelta.dy),
      );
    }
  }

  Widget _rail(BuildContext context, BoxConstraints constraints) {
    final position = _position;
    if (position == null) return const SizedBox.shrink();
    final range = position.maxScrollExtent - position.minScrollExtent;
    final height = constraints.maxHeight - 2 * _endInset;
    if (range <= 0 || !range.isFinite || height <= 0) {
      return const SizedBox.shrink();
    }
    final visibleFraction =
        position.viewportDimension / (position.viewportDimension + range);
    final thumbHeight = math.min(
      height / 2,
      math.max(_minThumbHeight, height * visibleFraction),
    );
    final travel = height - thumbHeight;
    final offsetFraction =
        ((position.pixels - position.minScrollExtent) / range).clamp(0.0, 1.0);
    final thumbTop = _endInset + travel * offsetFraction;
    final primary = Theme.of(context).colorScheme.primary;
    final dragging = _grabFraction != null;
    const barDecoration = BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(_barWidth / 2)),
    );

    return Listener(
      onPointerSignal: (event) => _onPointerSignal(event, position),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        dragStartBehavior: DragStartBehavior.down,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        onVerticalDragStart: (details) =>
            _startDrag(details, position, thumbTop, thumbHeight),
        onVerticalDragUpdate: (details) =>
            _updateDrag(details, position, thumbHeight, travel),
        onVerticalDragEnd: (_) => _endDrag(),
        onVerticalDragCancel: _endDrag,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (dragging)
              Positioned(
                right: 3,
                top: _endInset,
                bottom: _endInset,
                width: _barWidth,
                child: DecoratedBox(
                  decoration: barDecoration.copyWith(
                    color: primary.withValues(alpha: .18),
                  ),
                ),
              ),
            Positioned(
              right: 3,
              top: thumbTop,
              width: _barWidth,
              height: thumbHeight,
              child: DecoratedBox(
                decoration: barDecoration.copyWith(
                  color: primary.withValues(alpha: dragging ? 1 : .6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            setState(() {});
          }
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (widget.visible || _grabFraction != null)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: SongListScrollbar.dragWidth,
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => LayoutBuilder(builder: _rail),
                ),
              ),
          ],
        ),
      );
}
