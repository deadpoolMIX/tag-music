import 'package:flutter/material.dart';

import 'database.dart';
import 'library_controller.dart';

Future<void> playlistAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('歌单操作失败：$error')));
    }
  }
}

/// Capture the source before opening a dialog; later search/queue changes do not
/// change what is saved. The repository performs stable-ID deduplication.
Future<void> savePlaylist(
  BuildContext context,
  LibraryController library,
  Iterable<String> songIds, {
  Playlist? rename,
}) async {
  final ids = songIds.toList();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _PlaylistNameDialog(library: library, ids: ids, rename: rename),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.library,
    required this.ids,
    this.rename,
  });
  final LibraryController library;
  final List<String> ids;
  final Playlist? rename;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final text = TextEditingController(text: widget.rename?.name ?? '');
  String? error;
  bool saving = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.rename == null) {
        await widget.library.createPlaylist(text.text, widget.ids);
      } else {
        await widget.library.renamePlaylist(widget.rename!.id, text.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = '$failure';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.rename == null ? '保存普通歌单' : '歌单改名'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('playlist-name'),
              controller: text,
              autofocus: true,
              enabled: !saving,
              decoration: InputDecoration(labelText: '歌单名称', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            if (widget.rename == null)
              Text('${widget.ids.toSet().length} 首 · 同一歌曲只保留首次出现的位置'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('save-playlist-confirm'),
          onPressed: saving ? null : submit,
          child: Text(saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}

Future<void> addToPlaylist(
  BuildContext context,
  LibraryController library,
  Iterable<String> songIds,
) async {
  final ids = songIds.toList();
  final lists = library.playlists.where((p) => p.kind == 'regular').toList();
  final target = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('添加到普通歌单'),
      content: SizedBox(
        width: 420,
        height: 300,
        child: lists.isEmpty
            ? const Center(child: Text('尚无普通歌单，可保存为新歌单'))
            : ListView.builder(
                itemCount: lists.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(lists[i].name),
                  onTap: () => Navigator.pop(dialog, lists[i].id),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, ''),
          child: const Text('新建歌单'),
        ),
      ],
    ),
  );
  if (target == null || !context.mounted) return;
  if (target.isEmpty) {
    await savePlaylist(context, library, ids);
  } else {
    await playlistAction(context, () => library.addPlaylistSongs(target, ids));
  }
}

Future<void> pickPlaylistSongs(
  BuildContext context,
  LibraryController library,
  String id,
) async {
  final rows = library.tracks.toList()
    ..sort((a, b) {
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return title == 0 ? a.song.id.compareTo(b.song.id) : title;
    });
  final selected = <String>{};
  final existing = (library.playlistSongIds[id] ?? []).toSet();
  var query = '';
  final result = await showDialog<List<String>>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final needle = query.trim().toLowerCase();
        final visible = rows
            .where(
              (t) => [
                t.title,
                t.song.name,
                t.song.artist ?? '',
                t.song.album ?? '',
              ].any((v) => v.toLowerCase().contains(needle)),
            )
            .toList();
        return AlertDialog(
          title: const Text('从曲库添加歌曲'),
          content: SizedBox(
            width: 520,
            height: 400,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('playlist-picker-search'),
                  decoration: const InputDecoration(labelText: '搜索歌曲'),
                  onChanged: (value) => setState(() => query = value),
                ),
                Text('已选 ${selected.length} 首 · 已在歌单中的歌曲不会重复添加'),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final t = visible[i];
                      return CheckboxListTile(
                        key: ValueKey('pick-${t.song.id}'),
                        title: Text(t.title),
                        subtitle: Text(
                          existing.contains(t.song.id)
                              ? '已在歌单'
                              : t.available
                              ? t.song.name
                              : '文件失联 · 仍可添加记录',
                        ),
                        value: selected.contains(t.song.id),
                        onChanged: existing.contains(t.song.id)
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  selected.add(t.song.id);
                                } else {
                                  selected.remove(t.song.id);
                                }
                              }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('playlist-picker-confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      dialog,
                      rows
                          .where((t) => selected.contains(t.song.id))
                          .map((t) => t.song.id)
                          .toList(),
                    ),
              child: const Text('添加所选歌曲'),
            ),
          ],
        );
      },
    ),
  );
  if (result != null && context.mounted) {
    await playlistAction(context, () => library.addPlaylistSongs(id, result));
  }
}
