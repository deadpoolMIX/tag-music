import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../playback/playback_controller.dart';
import '../playback/queue_actions.dart';
import 'database.dart';
import 'library_controller.dart';
import 'playlist_actions.dart';
import 'filter_rule.dart';
import 'group_pages.dart';
import 'smart_playlist_editor.dart';
import 'song_list.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    required this.library,
    required this.playback,
    this.active = true,
    this.menuButton,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  final bool active;
  final Widget? menuButton;
  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  String? openedId;
  String query = '';
  bool reorderingMode = false;
  bool busy = false;
  bool descending = false;

  Future<void> _change(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    await playlistAction(context, operation);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _delete(Playlist list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => CompactAlertDialog(
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

  Future<void> _editSmart(Playlist list) async {
    FilterPreferences initial;
    try {
      initial = widget.library.smartPreferences(list);
    } catch (error) {
      final rebuild = await showDialog<bool>(
        context: context,
        builder: (dialog) => CompactAlertDialog(
          title: const Text('重建无法读取的规则？'),
          content: Text('$error\n将从全部可用歌曲和默认排序开始编辑，保存后替换旧规则；取消会保留原记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('重建规则'),
            ),
          ],
        ),
      );
      if (rebuild != true || !mounted) return;
      initial = FilterPreferences();
    }
    if (!mounted) return;
    await editSmartPlaylist(
      context,
      widget.library,
      playlist: list,
      initial: initial,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final list = library.playlists.where((p) => p.id == openedId).firstOrNull;
      if (list == null) return _overview(library);
      final smart = list.kind == 'smart';
      String? ruleError;
      List<LibraryTrack> all = [];
      try {
        all = library.playlistTracks(list.id);
      } catch (error) {
        ruleError = '无法读取智能歌单：$error';
      }
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
      final reordering = !smart && needle.isEmpty && reorderingMode && !busy;
      final detail = LayoutBuilder(
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
                          ?widget.menuButton,
                          IconButton(
                            tooltip: '返回歌单',
                            onPressed: busy ? null : _closePlaylist,
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
                              if (action == 'edit') {
                                _editSmart(list);
                              }
                            },
                            itemBuilder: (_) => [
                              if (smart)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('编辑规则'),
                                ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('改名'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      TextField(
                        key: ValueKey('playlist-search-${list.id}'),
                        decoration: const InputDecoration(
                          hintText: '搜索歌单歌曲',
                          prefixIcon: Icon(Icons.search, size: 18),
                        ),
                        onChanged: (value) => setState(() {
                          query = value;
                          // Searching changes the displayed membership. End
                          // reorder mode so later clearing the query preserves
                          // any selection made in the search results.
                          if (value.trim().isNotEmpty) reorderingMode = false;
                        }),
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${rows.length} / ${all.length} 首'),
                          QueueAddButton(
                            key: const ValueKey('enqueue-playlist'),
                            playback: widget.playback,
                            songs: busy
                                ? const []
                                : rows
                                      .where((t) => t.available)
                                      .map((t) => t.queueSong)
                                      .toList(),
                          ),
                          if (!smart)
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
                          if (!smart)
                            TextButton(
                              key: const ValueKey('playlist-reorder'),
                              onPressed: busy || needle.isNotEmpty
                                  ? null
                                  : () => setState(
                                      () => reorderingMode = !reorderingMode,
                                    ),
                              child: Text(reorderingMode ? '结束排序' : '调整顺序'),
                            ),
                        ],
                      ),
                      Text(
                        smart
                            ? '规则和排序独立保存，结果随曲库和标签变化。'
                            : needle.isEmpty
                            ? '拖动歌曲调整顺序；多选可批量移除'
                            : '搜索中不能重排歌曲',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (ruleError != null)
                        Text(
                          ruleError,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SongList(
                scope: 'playlist',
                emptyText: ruleError != null
                    ? '修复规则后显示结果'
                    : all.isEmpty
                    ? (smart ? '没有匹配的可用歌曲' : '空歌单，添加歌曲后即可播放')
                    : '没有匹配的歌曲',
                key: ValueKey('playlist-songs-${list.id}'),
                library: library,
                playback: widget.playback,
                source: all,
                rows: rows,
                enabled: !busy && ruleError == null,
                reordering: reordering,
                onRemove: smart
                    ? null
                    : (ids) => _change(
                        () => library.removePlaylistSongs(list.id, ids),
                      ),
                onReorder: (oldIndex, newIndex) {
                  final ids = all.map((t) => t.song.id).toList();
                  ids.insert(newIndex, ids.removeAt(oldIndex));
                  _change(() => library.reorderPlaylist(list.id, ids));
                },
              ),
            ),
          ],
        ),
      );
      return PopScope(
        canPop: !widget.active,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !busy && widget.active) _closePlaylist();
        },
        child: detail,
      );
    },
  );

  void _closePlaylist() {
    FocusScope.of(context).unfocus();
    setState(() {
      openedId = null;
      query = '';

      reorderingMode = false;
    });
  }

  String _count(LibraryController library, Playlist list) {
    try {
      return '${library.playlistTracks(list.id).length} 首';
    } catch (_) {
      return '规则不可读取';
    }
  }

  Widget _overview(LibraryController library) {
    final lists = [...library.playlists]
      ..sort((a, b) {
        final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        final stable = c != 0 ? c : a.name.compareTo(b.name);
        return descending ? -stable : stable;
      });
    return GroupList(
      menuButton: widget.menuButton,
      trailing: IconButton(
        key: const ValueKey('create-playlist'),
        tooltip: '新建歌单',
        onPressed: () => savePlaylist(context, library, const []),
        icon: const Icon(Icons.playlist_add),
      ),
      storageKey: 'playlist-overview',
      descending: descending,
      onSort: () => setState(() => descending = !descending),
      itemCount: lists.length,
      emptyText: '保存喜欢的歌曲顺序，或创建空歌单',
      itemBuilder: (_, i) {
        final list = lists[i];
        return ListTile(
          key: ValueKey('playlist-${list.id}'),
          leading: Icon(
            list.kind == 'smart' ? Icons.auto_awesome : Icons.queue_music,
          ),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${list.kind == 'smart' ? '智能歌单' : '普通歌单'} · ${_count(library, list)}',
          ),
          onTap: () => setState(() {
            openedId = list.id;
            query = '';

            reorderingMode = false;
          }),
        );
      },
    );
  }
}
