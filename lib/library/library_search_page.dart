import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../playback/playback_minibar.dart';
import 'library_controller.dart';
import 'song_list.dart';

class LibrarySearchPage extends StatefulWidget {
  const LibrarySearchPage({
    required this.library,
    required this.playback,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  @override
  State<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends State<LibrarySearchPage> {
  final _editing = TextEditingController();
  final _focus = FocusNode(debugLabel: 'full-library-search');
  @override
  void dispose() {
    _editing.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextField(
        key: const ValueKey('library-search'),
        controller: _editing,
        focusNode: _focus,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索歌曲、歌手、专辑或文件名',
          suffixIcon: IconButton(
            tooltip: '清空搜索',
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(_editing.clear);
              _focus.requestFocus();
            },
          ),
        ),
      ),
    ),
    body: ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) => SongList(
        scope: 'search',
        library: widget.library,
        playback: widget.playback,
        source: widget.library.searchTracks(''),
        rows: widget.library.searchTracks(_editing.text),
      ),
    ),
    bottomNavigationBar: const PlaybackMinibar(),
  );
}
