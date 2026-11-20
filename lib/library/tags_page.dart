import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../core/desktop_navigation.dart';

import 'library_controller.dart';
import '../playback/playback_controller.dart';
import 'group_pages.dart';
import 'library_header.dart';
import 'song_list.dart';
import 'tag_picker.dart';

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('标签操作失败：$error')));
    }
  }
}

Future<void> _editName(
  BuildContext context,
  LibraryController library, {
  String? id,
  String initial = '',
}) async {
  var input = initial;
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => CompactAlertDialog(
      title: Text(id == null ? '创建标签' : '修改标签名称'),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '标签名称'),
        onChanged: (value) => input = value,
        onFieldSubmitted: (value) => Navigator.pop(dialog, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, input),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (result == null || !context.mounted) return;
  await _run(
    context,
    () =>
        id == null ? library.createTag(result) : library.renameTag(id, result),
  );
}

Future<void> showTagActions(
  BuildContext context,
  LibraryController library,
  Set<String> songIds, {
  String? title,
}) async {
  if (songIds.isEmpty) return;
  final totals = <String, int>{};
  for (final songId in songIds) {
    for (final tagId in library.tagsForSong(songId)) {
      totals.update(tagId, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final selected = {
    for (final entry in totals.entries)
      if (entry.value == songIds.length) entry.key,
  };
  final mixed = totals.keys.toSet().difference(selected);
  final result = await showTagPicker(
    context,
    library,
    title:
        title ??
        (songIds.length == 1 ? '编辑歌曲标签' : '为 ${songIds.length} 首歌曲编辑标签'),
    prefix: 'song-tags',
    initial: selected,
    initialMixed: mixed,
  );
  if (!context.mounted || result == null) return;
  final remainingTags = library.tags.map((tag) => tag.id).toSet();
  await _run(
    context,
    () => library.editSongTags(
      songIds,
      add: result.selected.difference(selected),
      remove: totals.keys
          .toSet()
          .difference(result.selected.union(result.mixed))
          .intersection(remainingTags),
    ),
  );
}

class TagsPage extends StatefulWidget {
  const TagsPage({
    required this.library,
    this.playback,
    this.active = true,
    this.menuButton,
    super.key,
  });
  final LibraryController library;
  final PlaybackController? playback;
  final bool active;
  final Widget? menuButton;
  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  LibraryController get library => widget.library;
  String? openedId;
  bool descending = false;

  void _openTag(String? id) {
    void show(String? next) {
      if (mounted) setState(() => openedId = next);
    }

    final history = DesktopNavigation.maybeOf(context);
    if (history == null) {
      show(id);
    } else {
      history.visit(context, this, openedId, id, show);
    }
  }

  Future<void> _delete(BuildContext context, String id, String name) async {
    final count = library.countForTag(id);
    late final List<String> effects;
    try {
      effects = library.tagDeletionEffects(id);
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法预览删除影响：$error')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => CompactAlertDialog(
        scrollable: true,
        title: Text('删除标签“$name”？'),
        content: Text(
          '将移除 $count 首歌曲与该标签的关联。歌曲记录和音乐文件不会删除。'
          '${effects.isEmpty ? '' : '\n将从以下规则的所有框移除此标签并重算（当前可用歌曲）：\n${effects.join('\n')}\n结果范围可能扩大或缩小；两个包含框都空时从全部可用歌曲开始筛选。'}\n已有播放队列保持不变。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => library.deleteTag(id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final tag = library.tags.where((t) => t.id == openedId).firstOrNull;
      if (tag != null) {
        final rows = library.tracksForTag(tag.id);
        final desktop = DesktopNavigation.maybeOf(context) != null;
        final header = SongGroupHeader(
          name: tag.name,
          tracks: rows,
          playback: widget.playback,
          menuButton: widget.menuButton,
        );
        final playback = widget.playback;
        if (playback == null) {
          return PopScope(
            canPop: desktop || !widget.active,
            onPopInvokedWithResult: (didPop, _) {
              if (!desktop && !didPop && widget.active) _openTag(null);
            },
            child: Column(
              children: [
                header,
                const Expanded(child: Center(child: Text('播放器尚未就绪'))),
              ],
            ),
          );
        }
        return SongList(
          key: ValueKey('tag-songs-${tag.id}'),
          library: library,
          playback: playback,
          source: rows,
          rows: rows,
          scope: 'tag',
          emptyText: '尚无关联歌曲',
          header: header,
          onBack: desktop || !widget.active ? null : () => _openTag(null),
        );
      }
      final tags = [...library.tags]
        ..sort((a, b) {
          final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          final stable = c != 0 ? c : a.name.compareTo(b.name);
          return descending ? -stable : stable;
        });
      return GroupList(
        menuButton: widget.menuButton,
        trailing: IconButton(
          key: const ValueKey('create-tag'),
          tooltip: '创建标签',
          onPressed: () => _editName(context, library),
          icon: const Icon(Icons.add),
        ),
        storageKey: 'tags-overview',
        descending: descending,
        onSort: () => setState(() => descending = !descending),
        items: tags,
        nameOf: (tag) => tag.name,
        searchHint: '搜索标签',
        emptyText: '尚无标签。创建后可在曲库为歌曲添加标签。',
        itemBuilder: (_, tag) {
          return ListTile(
            key: ValueKey('tag-${tag.id}'),
            leading: const Icon(Icons.sell_outlined),
            title: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${library.tracksForTag(tag.id).length} 首'),
            onTap: () => _openTag(tag.id),
            trailing: PopupMenuButton<String>(
              tooltip: '标签操作',
              onSelected: (action) {
                if (action == 'rename') {
                  _editName(context, library, id: tag.id, initial: tag.name);
                }
                if (action == 'delete') {
                  _delete(context, tag.id, tag.name);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('改名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          );
        },
      );
    },
  );
}
