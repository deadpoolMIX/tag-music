import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../playback/playback_controller.dart';
import 'filter_rule.dart';
import 'library_controller.dart';
import 'library_header.dart';
import 'rule_editor.dart';
import 'smart_playlist_editor.dart';
import 'song_list.dart';

class FilterPage extends StatelessWidget {
  const FilterPage({
    required this.library,
    required this.playback,
    this.menuButton,
    super.key,
  });

  final LibraryController library;
  final PlaybackController playback;
  final Widget? menuButton;

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => CompactAlertDialog(
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
      await library.updateFilter(
        rule: FilterRule(),
        order: LibrarySort.modified,
        reverse: true,
        reset: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final preferences = FilterPreferences(
        rule: library.filterPreferences.rule,
        sort: LibrarySort.modified,
        descending: true,
      );
      final rows = library.filterResults(
        order: preferences.sort,
        descending: preferences.descending,
      );
      final loadError = library.filterLoadError;
      final saveError = library.filterSaveError;
      final enabled = loadError == null && !library.filterDeletingTag;
      return LayoutBuilder(
        builder: (context, constraints) => SongList(
          header: Column(
            children: [
              LibraryHeader(
                menuButton: menuButton,
                actions: [
                  IconButton(
                    key: const ValueKey('save-smart-playlist'),
                    tooltip: '保存为智能歌单',
                    onPressed: enabled
                        ? () => editSmartPlaylist(
                            context,
                            library,
                            initial: preferences,
                          )
                        : null,
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                  PlayAllButton(
                    playback: playback,
                    tracks: rows,
                    tooltip: '播放筛选结果',
                    enabled: enabled,
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .65,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: RuleEditor(
                    library: library,
                    rule: preferences.rule,
                    enabled: enabled,
                    compact: true,
                    onChanged: (rule) => library.updateFilter(rule: rule),
                  ),
                ),
              ),
              if (loadError != null || saveError != null)
                ListTile(
                  dense: true,
                  title: Text(loadError ?? saveError!),
                  trailing: TextButton(
                    onPressed: loadError != null
                        ? () => _reset(context)
                        : enabled
                        ? () => library.updateFilter()
                        : null,
                    child: Text(loadError != null ? '重置' : '重试'),
                  ),
                ),
            ],
          ),
          scope: 'filter',
          library: library,
          playback: playback,
          source: library.filterQuery.trim().isEmpty
              ? rows
              : library.matchingTracks(preferences),
          rows: rows,
          enabled: enabled,
          emptyText: loadError == null ? '没有匹配的歌曲' : '',
        ),
      );
    },
  );
}
