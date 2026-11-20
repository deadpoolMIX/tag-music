import 'package:flutter/material.dart';

import '../core/desktop_navigation.dart';
import '../core/marquee_title.dart';
import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'song_list.dart';

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

class SongGroupHeader extends StatelessWidget {
  const SongGroupHeader({
    required this.name,
    required this.tracks,
    required this.playback,
    this.menuButton,
    super.key,
  });

  final String name;
  final List<LibraryTrack> tracks;
  final PlaybackController? playback;
  final Widget? menuButton;

  @override
  Widget build(BuildContext context) => LibraryHeader(
    menuButton: menuButton ?? const AppNavigationButton(),
    heading: MarqueeTitle(
      text: name,
      style: Theme.of(context).textTheme.titleLarge!,
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text('${tracks.length}首'),
      ),
      PlayAllButton(playback: playback, tracks: tracks),
    ],
  );
}
