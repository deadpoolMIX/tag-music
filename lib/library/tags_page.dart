import 'package:flutter/material.dart';

import 'library_controller.dart';

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

class TagsPage extends StatelessWidget {
  const TagsPage({required this.library, super.key});
  final LibraryController library;

  Future<void> _delete(BuildContext context, String id, String name) async {
    final count = library.countForTag(id);
    final rule = library.filterPreferences.rule;
    final boxes = [
      if (rule.allTagIds.contains(id)) '全部具备',
      if (rule.anyTagIds.contains(id)) '任一具备',
      if (rule.excludedTagIds.contains(id)) '排除标签',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('删除标签“$name”？'),
        content: Text(
          '将移除 $count 首歌曲与该标签的关联。歌曲记录和音乐文件不会删除。'
          '${boxes.isEmpty ? '' : '\n还将从筛选的“${boxes.join('、')}”框移除此标签并重算，结果范围可能扩大或缩小；两个包含框都空时从全部可用歌曲开始筛选。已有播放队列保持不变。'}',
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
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('create-tag'),
            onPressed: () => _editName(context, library),
            icon: const Icon(Icons.add),
            label: const Text('创建标签'),
          ),
        ),
        if (library.tags.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('尚无标签。创建后可在曲库为歌曲添加标签。'),
          ),
        for (final tag in library.tags)
          ExpansionTile(
            key: ValueKey('tag-${tag.id}'),
            title: Text(tag.name),
            subtitle: Text('${library.countForTag(tag.id)} 首歌曲'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '修改${tag.name}',
                  onPressed: () => _editName(
                    context,
                    library,
                    id: tag.id,
                    initial: tag.name,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除${tag.name}',
                  onPressed: () => _delete(context, tag.id, tag.name),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            children: [
              for (final track in library.tracksForTag(tag.id))
                ListTile(
                  title: Text(track.title),
                  subtitle: Text(
                    track.available ? track.song.name : '文件失联 · 标签保留',
                  ),
                ),
              if (library.countForTag(tag.id) == 0)
                const ListTile(title: Text('尚无关联歌曲')),
            ],
          ),
      ],
    ),
  );
}
