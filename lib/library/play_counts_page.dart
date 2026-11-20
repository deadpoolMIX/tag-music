import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'library_header.dart';
import 'library_search.dart';
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
      final all = widget.library.playedTracks(
        order: _order,
        descending: _descending,
      );
      return LibrarySearch(
        hintText: '搜索已播放歌曲',
        heading: Text('播放次数', style: Theme.of(context).textTheme.titleLarge),
        builder: (context, query, heading, searchButton) => SongList(
          library: widget.library,
          playback: widget.playback,
          source: all,
          rows: searchSongRows(all, query),
          resetScrollKey: query,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          scope: 'play-counts',
          showPlayCounts: true,
          emptyText: query.isEmpty ? '歌曲自然播完后会显示在这里' : '没有匹配的歌曲',
          header: LibraryHeader(
            menuButton: widget.menuButton,
            heading: heading,
            actions: [
              SongSortButton(
                order: _order,
                descending: _descending,
                includePlayCount: true,
                onChanged: (order, descending) {
                  setState(() {
                    _order = order;
                    _descending = descending;
                  });
                },
              ),
              searchButton,
            ],
          ),
        ),
      );
    },
  );
}
