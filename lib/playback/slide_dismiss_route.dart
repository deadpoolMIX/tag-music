import 'dart:async';

import 'package:flutter/material.dart';

class SlideDismissRoute extends PageRouteBuilder<void> {
  SlideDismissRoute({
    required String name,
    required this.reduceMotion,
    required WidgetBuilder builder,
  }) : super(
         settings: RouteSettings(name: name),
         opaque: false,
         transitionDuration: reduceMotion
             ? Duration.zero
             : const Duration(milliseconds: 280),
         reverseTransitionDuration: reduceMotion
             ? Duration.zero
             : const Duration(milliseconds: 240),
         pageBuilder: (context, _, _) => builder(context),
         transitionsBuilder: (_, animation, _, child) => SlideTransition(
           position: animation.drive(
             Tween(begin: const Offset(0, 1), end: Offset.zero),
           ),
           child: child,
         ),
       );

  final bool reduceMotion;
  bool _dragging = false;

  bool startDrag() {
    _dragging = isCurrent && controller?.isCompleted == true;
    return _dragging;
  }

  void moveDrag(double pixels, double height) {
    if (!_dragging || !isCurrent || height <= 0) return;
    final movement = controller!;
    movement.value = (movement.value - pixels / height).clamp(0.01, 1);
  }

  void finishDrag({double velocity = 0, bool cancelled = false}) {
    if (!_dragging) return;
    _dragging = false;
    if (!isCurrent) return;
    final movement = controller!;
    if (!cancelled &&
        (movement.value <= .78 || (movement.value < .96 && velocity >= 680))) {
      navigator?.pop();
    } else if (reduceMotion) {
      movement.value = 1;
    } else {
      unawaited(
        movement.animateTo(
          1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }
}
