import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../core/desktop_navigation.dart';
import '../playback/playback_controller.dart';
import '../playback/queue_actions.dart';
import 'database.dart';
import 'library_controller.dart';
import 'library_header.dart';
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
      final reordering = !smart && reorderingMode && !busy;
      final desktop = DesktopNavigation.maybeOf(context) != null;
      final detail = SongList(
        onBack: desktop
            ? null
            : () {
                if (!busy) _closePlaylist();
              },
        header: Column(
          children: [
            LibraryHeader(
              menuButton: widget.menuButton ?? const AppNavigationButton(),
              heading: Text(
                list.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              actions: [
                if (!smart)
                  IconButton(
                    key: const ValueKey('playlist-reorder'),
                    tooltip: reorderingMode ? '结束排序' : '调整顺序',
                    isSelected: reorderingMode,
                    onPressed: busy
                        ? null
                        : () =>
                              setState(() => reorderingMode = !reorderingMode),
                    icon: const Icon(Icons.reorder),
                    selectedIcon: const Icon(Icons.check),
                  ),
                if (!smart)
                  IconButton(
                    key: const ValueKey('playlist-add-songs'),
                    tooltip: '添加歌曲',
                    onPressed: busy
                        ? null
                        : () => pickPlaylistSongs(context, library, list.id),
                    icon: const Icon(Icons.playlist_add),
                  ),
                Text('${all.length}首'),
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: '歌单操作',
                  onSelected: (action) {
                    switch (action) {
                      case 'enqueue':
                        enqueueSongs(
                          context,
                          widget.playback,
                          all
                              .where((track) => track.available)
                              .map((track) => track.queueSong)
                              .toList(),
                        );
                      case 'rename':
                        savePlaylist(context, library, const [], rename: list);
                      case 'delete':
                        _delete(list);
                      case 'edit':
                        _editSmart(list);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'enqueue',
                      enabled: all.any((track) => track.available),
                      child: const Text('添加到播放队列'),
                    ),
                    if (smart)
                      const PopupMenuItem(value: 'edit', child: Text('编辑规则')),
                    const PopupMenuItem(value: 'rename', child: Text('改名')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
                PlayAllButton(
                  playback: widget.playback,
                  tracks: all,
                  enabled: !busy && ruleError == null,
                  tooltip: '播放歌单',
                ),
              ],
            ),
            if (smart)
              Text(
                '规则和排序独立保存，结果随曲库和标签变化。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (ruleError != null)
              Text(
                ruleError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
        scope: 'playlist',
        emptyText: ruleError != null
            ? '修复规则后显示结果'
            : smart
            ? '没有匹配的可用歌曲'
            : '空歌单，添加歌曲后即可播放',
        key: ValueKey('playlist-songs-${list.id}'),
        library: library,
        playback: widget.playback,
        source: all,
        rows: all,
        enabled: !busy && ruleError == null,
        reordering: reordering,
        onRemove: smart
            ? null
            : (ids) => _change(() => library.removePlaylistSongs(list.id, ids)),
        onReorder: (oldIndex, newIndex) {
          final ids = all.map((t) => t.song.id).toList();
          ids.insert(newIndex, ids.removeAt(oldIndex));
          _change(() => library.reorderPlaylist(list.id, ids));
        },
      );
      return desktop
          ? PopScope(canPop: !widget.active || !busy, child: detail)
          : detail;
    },
  );

  void _closePlaylist() => _openPlaylist(null, returning: true);

  void _openPlaylist(String? id, {bool returning = false}) {
    void show(String? next) {
      if (!mounted) return;
      if (next == null) FocusScope.of(context).unfocus();
      setState(() {
        openedId = next;
        reorderingMode = false;
      });
    }

    final history = DesktopNavigation.maybeOf(context);
    if (history == null) {
      show(id);
    } else {
      history.visit(context, this, openedId, id, show, returning: returning);
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
      items: lists,
      nameOf: (list) => list.name,
      searchHint: '搜索歌单',
      emptyText: '保存喜欢的歌曲顺序，或创建空歌单',
      itemBuilder: (_, list) {
        List<LibraryTrack>? tracks;
        try {
          tracks = library.playlistTracks(list.id);
        } on FormatException {
          // Keep the row and let the detail page offer rule repair.
        }
        final count = tracks == null ? '规则不可读取' : '${tracks.length} 首';
        return ListTile(
          key: ValueKey('playlist-${list.id}'),
          leading: Icon(
            list.kind == 'smart' ? Icons.auto_awesome : Icons.queue_music,
          ),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${list.kind == 'smart' ? '智能歌单' : '普通歌单'} · $count'),
          trailing: PlayAllButton(
            playback: widget.playback,
            tracks: tracks ?? const [],
            tooltip: '播放歌单',
          ),
          onTap: () => _openPlaylist(list.id),
        );
      },
    );
  }
}
