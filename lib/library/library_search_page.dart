import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('library-search'),
          controller: _editing,
          focusNode: _focus,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _focus.unfocus(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索歌曲、歌手、专辑或文件名',
            suffixIcon: _editing.text.isEmpty
                ? null
                : IconButton(
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
        builder: (context, _) {
          final rows = widget.library.searchTracks(_editing.text);
          final query = _editing.text.trim().toLowerCase();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    query.isEmpty
                        ? '全部歌曲 · ${rows.length} 首'
                        : '搜索结果 · ${rows.length} 首',
                    key: const ValueKey('search-result-count'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: SongList(
                  scope: 'search',
                  library: widget.library,
                  playback: widget.playback,
                  source: widget.library.searchTracks(''),
                  rows: rows,
                  resetScrollKey: query,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  emptyText: query.isEmpty ? '曲库中暂无歌曲' : '没有匹配的歌曲，可尝试歌手、专辑或文件名',
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Theme.of(context).platform == TargetPlatform.windows
          ? null
          : const PlaybackMinibar(),
    ),
  );
}
