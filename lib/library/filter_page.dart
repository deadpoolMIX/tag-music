import 'dart:async';

import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'filter_rule.dart';
import 'library_controller.dart';
import 'playlist_actions.dart';

const _boxTitles = ['全部具备', '任一具备', '排除标签'];
const _boxHints = ['同时有这些标签', '至少有其中一个标签', '有任一标签就排除'];

Set<String> _ids(FilterRule rule, int box) => switch (box) {
  0 => rule.allTagIds,
  1 => rule.anyTagIds,
  _ => rule.excludedTagIds,
};

void _replace(LibraryController library, int box, Iterable<String> ids) {
  final rule = library.filterPreferences.rule;
  unawaited(
    library.updateFilter(
      rule: FilterRule(
        allTagIds: box == 0 ? ids : rule.allTagIds,
        anyTagIds: box == 1 ? ids : rule.anyTagIds,
        excludedTagIds: box == 2 ? ids : rule.excludedTagIds,
      ),
    ),
  );
}

class FilterPage extends StatefulWidget {
  const FilterPage({required this.library, required this.playback, super.key});
  final LibraryController library;
  final PlaybackController playback;
  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late final _search = TextEditingController(text: widget.library.filterQuery);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('重置筛选记录？'),
        content: const Text('将替换无法读取的规则，恢复全部可用歌曲和默认排序。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.library.updateFilter(
        rule: FilterRule(),
        order: LibrarySort.title,
        reverse: false,
        reset: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final preferences = library.filterPreferences;
      final rows = library.filtered;
      final enabled =
          library.filterLoadError == null && !library.filterDeletingTag;
      return CustomScrollView(
        key: const PageStorageKey('filter-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '组合筛选',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      TextButton.icon(
                        key: const ValueKey('save-filter-playlist'),
                        onPressed: enabled
                            ? () => savePlaylist(
                                context,
                                library,
                                rows.map((t) => t.song.id),
                              )
                            : null,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('保存结果为普通歌单'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('clear-filter'),
                        onPressed: enabled && !preferences.rule.isEmpty
                            ? () => library.updateFilter(rule: FilterRule())
                            : null,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('清空全部条件'),
                      ),
                    ],
                  ),
                  const Text('前两框结果合并，再扣除排除标签。前两框都空时，从全部可用歌曲中排除。'),
                  if (library.filterLoadError case final error?) ...[
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    TextButton(onPressed: _reset, child: const Text('重置筛选记录')),
                  ],
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final boxes = [
                        for (var i = 0; i < 3; i++)
                          _FilterBox(
                            library: library,
                            box: i,
                            enabled: enabled,
                          ),
                      ];
                      return constraints.maxWidth >= 840
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < boxes.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  Expanded(child: boxes[i]),
                                ],
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: boxes,
                            );
                    },
                  ),
                  if (library.filterSaveError case final error?)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: enabled
                              ? () => library.updateFilter()
                              : null,
                          child: const Text('重试保存'),
                        ),
                      ],
                    )
                  else
                    Text(
                      library.filterSaving ? '正在保存筛选…' : '当前筛选和排序会在下次启动时恢复。',
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('filter-search'),
                    controller: _search,
                    onChanged: library.searchFilter,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: '在筛选结果中搜索歌曲、歌手或专辑',
                      suffixIcon: IconButton(
                        tooltip: '清空结果搜索',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          library.searchFilter('');
                        },
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<LibrarySort>(
                        key: const ValueKey('filter-sort'),
                        value: preferences.sort,
                        onChanged: enabled
                            ? (value) => library.updateFilter(order: value)
                            : null,
                        items: [
                          for (final entry in {
                            LibrarySort.title: '歌曲名',
                            LibrarySort.artist: '歌手',
                            LibrarySort.album: '专辑',
                            LibrarySort.name: '文件名',
                          }.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: preferences.descending
                            ? '筛选结果改为升序'
                            : '筛选结果改为降序',
                        onPressed: enabled
                            ? () => library.updateFilter(
                                reverse: !preferences.descending,
                              )
                            : null,
                        icon: Icon(
                          preferences.descending ? Icons.south : Icons.north,
                        ),
                      ),
                      Text(
                        '${rows.length} / ${library.filterMatches.length} 首',
                        key: const ValueKey('filter-count'),
                      ),
                    ],
                  ),
                  if (widget.playback.error case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        library.filterLoadError != null
                            ? '修复筛选记录后显示结果'
                            : '没有匹配的可用歌曲',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final track = rows[index];
              return ListTile(
                key: ValueKey('filter-song-${track.song.id}'),
                leading: const Icon(Icons.music_note_outlined),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    track.song.artist ?? '未知歌手',
                    track.song.album,
                    track.song.name,
                  ].nonNulls.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: widget.playback.currentSongId == track.song.id,
                onTap: widget.playback.busy || !enabled
                    ? null
                    : () => widget.playback.playSongs(
                        rows.map((t) => t.queueSong).toList(),
                        index,
                      ),
              );
            },
          ),
        ],
      );
    },
  );
}

class _FilterBox extends StatelessWidget {
  const _FilterBox({
    required this.library,
    required this.box,
    required this.enabled,
  });
  final LibraryController library;
  final int box;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final ids = _ids(library.filterPreferences.rule, box);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _boxTitles[box],
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(_boxHints[box]),
            Wrap(
              spacing: 4,
              children: [
                for (final tag in library.tags.where(
                  (tag) => ids.contains(tag.id),
                ))
                  InputChip(
                    key: ValueKey('filter-chip-$box-${tag.id}'),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: enabled
                        ? () => _replace(
                            library,
                            box,
                            _ids(
                              library.filterPreferences.rule,
                              box,
                            ).where((id) => id != tag.id),
                          )
                        : null,
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: ValueKey('filter-pick-$box'),
                  onPressed: enabled
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _TagPicker(library: library, box: box),
                        )
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('选择标签'),
                ),
                TextButton(
                  key: ValueKey('filter-clear-$box'),
                  onPressed: enabled && ids.isNotEmpty
                      ? () => _replace(library, box, [])
                      : null,
                  child: const Text('清空此框'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPicker extends StatefulWidget {
  const _TagPicker({required this.library, required this.box});
  final LibraryController library;
  final int box;
  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('选择${_boxTitles[widget.box]}的标签'),
    content: SizedBox(
      width: 520,
      height: MediaQuery.sizeOf(context).height * .5,
      child: Column(
        children: [
          TextField(
            key: const ValueKey('filter-tag-search'),
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              labelText: '搜索标签',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.library,
              builder: (context, _) {
                final library = widget.library;
                final tags = library.tags
                    .where((tag) => tag.name.toLowerCase().contains(query))
                    .toList();
                final selected = _ids(
                  library.filterPreferences.rule,
                  widget.box,
                );
                return tags.isEmpty
                    ? Center(
                        child: Text(
                          library.tags.isEmpty ? '尚无标签，请先在标签页创建。' : '没有匹配的标签',
                        ),
                      )
                    : ListView.builder(
                        itemCount: tags.length,
                        itemBuilder: (context, index) {
                          final tag = tags[index];
                          return CheckboxListTile(
                            key: ValueKey('filter-tag-${tag.id}'),
                            title: Text(tag.name),
                            value: selected.contains(tag.id),
                            onChanged: library.filterDeletingTag
                                ? null
                                : (value) {
                                    final next = {
                                      ..._ids(
                                        library.filterPreferences.rule,
                                        widget.box,
                                      ),
                                    };
                                    if (value == true) {
                                      next.add(tag.id);
                                    } else {
                                      next.remove(tag.id);
                                    }
                                    _replace(library, widget.box, next);
                                  },
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
