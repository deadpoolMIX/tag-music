import 'package:flutter/material.dart';

class DesktopUiScale extends StatelessWidget {
  const DesktopUiScale({required this.factor, required this.child, super.key});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest / factor;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: size,
              child: MediaQuery(
                data: media.copyWith(
                  size: size,
                  devicePixelRatio: media.devicePixelRatio * factor,
                  padding: media.padding / factor,
                  viewPadding: media.viewPadding / factor,
                  viewInsets: media.viewInsets / factor,
                  systemGestureInsets: media.systemGestureInsets / factor,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
