import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'database.dart';
import 'library_controller.dart';
import 'playlist_actions.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    required this.library,
    required this.playback,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  String? openedId;
  String query = '';
  bool selecting = false;
  bool busy = false;
  final selected = <String>{};

  Future<void> _change(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    await playlistAction(context, operation);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _delete(Playlist list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('删除“${list.name}”？'),
        content: const Text('仅删除歌单，音乐、标签和已有播放队列保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除歌单'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change(() => widget.library.deletePlaylist(list.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final list = library.playlists.where((p) => p.id == openedId).firstOrNull;
      if (list == null) return _overview(library);
      final all = library.playlistTracks(list.id);
      final needle = query.trim().toLowerCase();
      final rows = all
          .where(
            (t) =>
                needle.isEmpty ||
                [
                  t.title,
                  t.song.name,
                  t.song.artist ?? '',
                  t.song.album ?? '',
                ].any((value) => value.toLowerCase().contains(needle)),
          )
          .toList();
      final reordering = needle.isEmpty && !selecting && !busy;
      Widget row(int i) {
        final track = rows[i];
        return ListTile(
          key: ValueKey('playlist-song-${track.song.id}'),
          selected: widget.playback.currentSongId == track.song.id,
          leading: selecting
              ? Checkbox(
                  value: selected.contains(track.song.id),
                  onChanged: busy ? null : (_) => _toggle(track.song.id),
                )
              : Icon(track.available ? Icons.music_note : Icons.link_off),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.available ? track.song.name : '文件失联 · 记录仍保留',
            maxLines: 1,
          ),
          trailing: reordering
              ? ReorderableDragStartListener(
                  index: i,
                  child: Tooltip(
                    message: '拖动${track.title}排序',
                    child: const Icon(Icons.drag_handle),
                  ),
                )
              : null,
          onTap: busy
              ? null
              : selecting
              ? () => _toggle(track.song.id)
              : !track.available
              ? null
              : () {
                  final snapshot = rows.where((t) => t.available).toList();
                  widget.playback.playSongs(
                    snapshot.map((t) => t.queueSong).toList(),
                    snapshot.indexOf(track),
                  );
                },
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .65,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: '返回歌单',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    openedId = null;
                                    query = '';
                                    selected.clear();
                                    selecting = false;
                                  }),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          Expanded(
                            child: Text(
                              list.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          PopupMenuButton<String>(
                            enabled: !busy,
                            tooltip: '歌单操作',
                            onSelected: (action) {
                              if (action == 'rename') {
                                savePlaylist(
                                  context,
                                  library,
                                  const [],
                                  rename: list,
                                );
                              }
                              if (action == 'delete') _delete(list);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('改名')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ],
                      ),
                      TextField(
                        key: ValueKey('playlist-search-${list.id}'),
                        decoration: const InputDecoration(
                          labelText: '搜索歌单歌曲',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${rows.length} / ${all.length} 首'),
                          TextButton.icon(
                            key: const ValueKey('playlist-add-songs'),
                            onPressed: busy
                                ? null
                                : () => pickPlaylistSongs(
                                    context,
                                    library,
                                    list.id,
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('添加歌曲'),
                          ),
                          TextButton(
                            key: const ValueKey('playlist-select'),
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    selecting = !selecting;
                                    selected.clear();
                                  }),
                            child: Text(selecting ? '退出多选' : '多选'),
                          ),
                          if (selecting) ...[
                            Text('已选 ${selected.length} 首'),
                            TextButton(
                              onPressed: busy || selected.isEmpty
                                  ? null
                                  : () {
                                      final ids = Set<String>.of(selected);
                                      _change(() async {
                                        await library.removePlaylistSongs(
                                          list.id,
                                          ids,
                                        );
                                        if (mounted) setState(selected.clear);
                                      });
                                    },
                              child: const Text('移除所选歌曲'),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        needle.isEmpty ? '拖动歌曲调整顺序；多选可批量移除' : '搜索中不能重排歌曲',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(all.isEmpty ? '空歌单，添加歌曲后即可播放' : '没有匹配的歌曲'),
                    )
                  : reordering
                  ? ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      key: ValueKey('playlist-order-${list.id}'),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => row(i),
                      onReorderItem: (oldIndex, newIndex) {
                        final ids = all.map((t) => t.song.id).toList();
                        ids.insert(newIndex, ids.removeAt(oldIndex));
                        _change(() => library.reorderPlaylist(list.id, ids));
                      },
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) => row(i),
                    ),
            ),
          ],
        ),
      );
    },
  );

  void _toggle(String id) => setState(() {
    if (!selected.add(id)) selected.remove(id);
  });

  Widget _overview(LibraryController library) {
    final lists = library.playlists.where((p) => p.kind == 'regular').toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('create-playlist'),
                onPressed: () => savePlaylist(context, library, const []),
                icon: const Icon(Icons.add),
                label: const Text('新建普通歌单'),
              ),
              TextButton.icon(
                key: const ValueKey('save-queue-playlist'),
                onPressed: widget.playback.queue.entries.isEmpty
                    ? null
                    : () => savePlaylist(
                        context,
                        library,
                        widget.playback.queue.entries.map((e) => e.song.songId),
                      ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存完整队列'),
              ),
            ],
          ),
        ),
        Expanded(
          child: lists.isEmpty
              ? const Center(child: Text('保存喜欢的歌曲顺序，或创建空歌单'))
              : ListView.builder(
                  itemCount: lists.length,
                  itemBuilder: (_, i) {
                    final list = lists[i];
                    return ListTile(
                      key: ValueKey('playlist-${list.id}'),
                      leading: const Icon(Icons.queue_music),
                      title: Text(list.name),
                      subtitle: Text(
                        '${library.playlistSongIds[list.id]?.length ?? 0} 首',
                      ),
                      onTap: () => setState(() {
                        openedId = list.id;
                        query = '';
                        selected.clear();
                        selecting = false;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
