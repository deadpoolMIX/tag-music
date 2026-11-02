import 'package:flutter/material.dart';

import 'database.dart';
import 'filter_rule.dart';
import 'library_controller.dart';
import 'rule_editor.dart';

Future<void> editSmartPlaylist(
  BuildContext context,
  LibraryController library, {
  Playlist? playlist,
  FilterPreferences? initial,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SmartEditor(
    library: library,
    playlist: playlist,
    initial: initial ?? FilterPreferences(),
  ),
);

class _SmartEditor extends StatefulWidget {
  const _SmartEditor({
    required this.library,
    required this.initial,
    this.playlist,
  });
  final LibraryController library;
  final FilterPreferences initial;
  final Playlist? playlist;
  @override
  State<_SmartEditor> createState() => _SmartEditorState();
}

class _SmartEditorState extends State<_SmartEditor> {
  late final name = TextEditingController(text: widget.playlist?.name ?? '');
  late FilterPreferences preferences = widget.initial;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _change({FilterRule? rule, LibrarySort? sort, bool? descending}) =>
      setState(() {
        preferences = FilterPreferences(
          rule: rule ?? preferences.rule,
          sort: sort ?? preferences.sort,
          descending: descending ?? preferences.descending,
        );
      });

  Future<void> _save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.playlist == null) {
        await widget.library.createSmartPlaylist(name.text, preferences);
      } else {
        await widget.library.editSmartPlaylist(
          widget.playlist!.id,
          preferences,
        );
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
      title: Text(widget.playlist == null ? '新建智能歌单' : '编辑智能规则'),
      content: SizedBox(
        width: 900,
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListenableBuilder(
          listenable: widget.library,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.playlist == null)
                  TextField(
                    key: const ValueKey('smart-name'),
                    controller: name,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: '歌单名称'),
                  ),
                const Text(ruleExplanation),
                const Text('只保存规则和排序；搜索词不会保存。歌曲或标签变化时更新结果。'),
                RuleEditor(
                  library: widget.library,
                  rule: preferences.rule,
                  prefix: 'smart',
                  enabled: !saving && !widget.library.filterDeletingTag,
                  onChanged: (rule) => _change(rule: rule),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<LibrarySort>(
                      key: const ValueKey('smart-sort'),
                      value: preferences.sort,
                      onChanged: saving ? null : (sort) => _change(sort: sort),
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
                      key: const ValueKey('smart-direction'),
                      tooltip: preferences.descending ? '改为升序' : '改为降序',
                      onPressed: saving
                          ? null
                          : () => _change(descending: !preferences.descending),
                      icon: Icon(
                        preferences.descending ? Icons.south : Icons.north,
                      ),
                    ),
                    Text(
                      '${widget.library.matchingTracks(preferences).length} 首可用歌曲',
                      key: const ValueKey('smart-preview'),
                    ),
                  ],
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('save-smart-confirm'),
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
