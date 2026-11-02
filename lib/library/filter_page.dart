import 'dart:async';

import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../playback/queue_actions.dart';
import 'filter_rule.dart';
import 'library_controller.dart';
import 'playlist_actions.dart';
import 'rule_editor.dart';
import 'smart_playlist_editor.dart';

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
                      QueueAddButton(
                        key: const ValueKey('enqueue-filter'),
                        playback: widget.playback,
                        songs: enabled
                            ? rows.map((t) => t.queueSong).toList()
                            : const [],
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
                        key: const ValueKey('save-smart-playlist'),
                        onPressed: enabled
                            ? () => editSmartPlaylist(
                                context,
                                library,
                                initial: preferences,
                              )
                            : null,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('保存为智能歌单'),
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
                  const Text(ruleExplanation),
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
                  RuleEditor(
                    library: library,
                    rule: preferences.rule,
                    enabled: enabled,
                    onChanged: (rule) =>
                        unawaited(library.updateFilter(rule: rule)),
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
                trailing: QueueAddButton(
                  key: ValueKey('enqueue-filter-${track.song.id}'),
                  playback: widget.playback,
                  songs: enabled ? [track.queueSong] : const [],
                  compact: true,
                ),
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
