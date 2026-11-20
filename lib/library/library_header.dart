import 'package:flutter/material.dart';

class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    this.menuButton,
    this.heading,
    this.actions = const [],
    super.key,
  });

  final Widget? menuButton;
  final Widget? heading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(
      start: menuButton == null ? 12 : 0,
      end: 4,
    ),
    child: Row(
      children: [
        ?menuButton,
        Expanded(child: heading ?? const SizedBox.shrink()),
        ...actions,
      ],
    ),
  );
}
