import 'package:flutter/material.dart';

import 'library_controller.dart';
import '../playback/playback_controller.dart';
import 'group_pages.dart';
import 'song_list.dart';

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
    builder: (dialog) => AlertDialog(
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
  Set<String> songIds,
) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: Text(songIds.length == 1 ? '编辑歌曲标签' : '为 ${songIds.length} 首歌曲编辑标签'),
    content: SizedBox(
      width: 520,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.tags.isEmpty
            ? const Text('尚无标签。请先在“标签”页创建。')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final tag in library.tags)
                    ListTile(
                      title: Text(tag.name),
                      subtitle: Text(
                        '已标记 ${songIds.where((id) => library.tagsForSong(id).contains(tag.id)).length} / ${songIds.length} 首',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '添加${tag.name}',
                            onPressed: () => _run(
                              dialog,
                              () => library.changeSongTags(
                                tag.id,
                                songIds,
                                add: true,
                              ),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          IconButton(
                            tooltip: '移除${tag.name}',
                            onPressed: () => _run(
                              dialog,
                              () => library.changeSongTags(
                                tag.id,
                                songIds,
                                add: false,
                              ),
                            ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('完成'),
      ),
    ],
  ),
);

class TagsPage extends StatefulWidget {
  const TagsPage({
    required this.library,
    this.playback,
    this.active = true,
    super.key,
  });
  final LibraryController library;
  final PlaybackController? playback;
  final bool active;
  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  LibraryController get library => widget.library;
  String? openedId;
  bool descending = false;

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
      builder: (dialog) => AlertDialog(
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
        return PopScope(
          canPop: !widget.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.active) setState(() => openedId = null);
          },
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '返回标签',
                    onPressed: () => setState(() => openedId = null),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      tag.name,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('${rows.length} 首'),
                  ),
                ],
              ),
              Expanded(
                child: widget.playback == null
                    ? const Center(child: Text('播放器尚未就绪'))
                    : SongList(
                        key: ValueKey('tag-songs-${tag.id}'),
                        library: library,
                        playback: widget.playback!,
                        source: rows,
                        rows: rows,
                        scope: 'tag',
                        emptyText: '尚无关联歌曲',
                      ),
              ),
            ],
          ),
        );
      }
      final tags = [...library.tags]
        ..sort((a, b) {
          final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          final stable = c != 0 ? c : a.name.compareTo(b.name);
          return descending ? -stable : stable;
        });
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                key: const ValueKey('create-tag'),
                onPressed: () => _editName(context, library),
                icon: const Icon(Icons.add),
                label: const Text('创建标签'),
              ),
            ),
          ),
          Expanded(
            child: GroupList(
              storageKey: 'tags-overview',
              descending: descending,
              onSort: () => setState(() => descending = !descending),
              itemCount: tags.length,
              emptyText: '尚无标签。创建后可在曲库为歌曲添加标签。',
              itemBuilder: (_, index) {
                final tag = tags[index];
                return ListTile(
                  key: ValueKey('tag-${tag.id}'),
                  leading: const Icon(Icons.sell_outlined),
                  title: Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${library.tracksForTag(tag.id).length} 首'),
                  onTap: () => setState(() => openedId = tag.id),
                  trailing: PopupMenuButton<String>(
                    tooltip: '标签操作',
                    onSelected: (action) {
                      if (action == 'rename') {
                        _editName(
                          context,
                          library,
                          id: tag.id,
                          initial: tag.name,
                        );
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
            ),
          ),
        ],
      );
    },
  );
}
