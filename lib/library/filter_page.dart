import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'filter_rule.dart';
import 'library_controller.dart';
import 'rule_editor.dart';
import 'smart_playlist_editor.dart';
import 'song_list.dart';

class FilterPage extends StatelessWidget {
  const FilterPage({required this.library, required this.playback, super.key});

  final LibraryController library;
  final PlaybackController playback;

  Future<void> _reset(BuildContext context) async {
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
      await library.updateFilter(
        rule: FilterRule(),
        order: LibrarySort.title,
        reverse: false,
        reset: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final preferences = library.filterPreferences;
      final rows = library.filtered;
      final loadError = library.filterLoadError;
      final saveError = library.filterSaveError;
      final enabled = loadError == null && !library.filterDeletingTag;
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .65,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Column(
                  children: [
                    RuleEditor(
                      library: library,
                      rule: preferences.rule,
                      enabled: enabled,
                      compact: true,
                      onChanged: (rule) => library.updateFilter(rule: rule),
                    ),
                    FilledButton(
                      key: const ValueKey('save-smart-playlist'),
                      onPressed: enabled
                          ? () => editSmartPlaylist(
                              context,
                              library,
                              initial: preferences,
                            )
                          : null,
                      child: const Text('保存为智能歌单'),
                    ),
                  ],
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
            Expanded(
              child: SongList(
                scope: 'filter',
                library: library,
                playback: playback,
                source: library.matchingTracks(preferences),
                rows: rows,
                enabled: enabled,
                emptyText: loadError == null ? '没有匹配的歌曲' : '',
              ),
            ),
          ],
        ),
      );
    },
  );
}
