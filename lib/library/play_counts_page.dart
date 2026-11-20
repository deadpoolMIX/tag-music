import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'song_list.dart';
import 'song_sort.dart';

class PlayCountsPage extends StatefulWidget {
  const PlayCountsPage({
    required this.library,
    required this.playback,
    this.menuButton,
    super.key,
  });

  final LibraryController library;
  final PlaybackController playback;
  final Widget? menuButton;

  @override
  State<PlayCountsPage> createState() => _PlayCountsPageState();
}

class _PlayCountsPageState extends State<PlayCountsPage> {
  LibrarySort? _order;
  bool _descending = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.library,
      widget.library.playCountChanges,
    ]),
    builder: (context, _) {
      final rows = widget.library.playedTracks(
        order: _order,
        descending: _descending,
      );
      return SongList(
        library: widget.library,
        playback: widget.playback,
        source: rows,
        rows: rows,
        scope: 'play-counts',
        showPlayCounts: true,
        emptyText: '歌曲自然播完后会显示在这里',
        header: Row(
          children: [
            ?widget.menuButton,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '播放次数',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SongSortButton(
              order: _order,
              descending: _descending,
              includePlayCount: true,
              onChanged: (order, descending) {
                if (!mounted) return;
                setState(() {
                  _order = order;
                  _descending = descending;
                });
              },
            ),
          ],
        ),
      );
    },
  );
}
