import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import 'library_controller.dart';

typedef TagSelection = ({Set<String> selected, Set<String> mixed});

Future<TagSelection?> showTagPicker(
  BuildContext context,
  LibraryController library, {
  required String title,
  required String prefix,
  required Set<String> initial,
  Set<String> initialMixed = const {},
}) => showDialog<TagSelection>(
  context: context,
  builder: (_) => _TagPicker(
    library: library,
    title: title,
    prefix: prefix,
    initial: initial,
    initialMixed: initialMixed,
  ),
);

class _TagPicker extends StatefulWidget {
  const _TagPicker({
    required this.library,
    required this.title,
    required this.prefix,
    required this.initial,
    required this.initialMixed,
  });
  final LibraryController library;
  final String title;
  final String prefix;
  final Set<String> initial, initialMixed;
  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  late final selected = {...widget.initial};
  late final mixed = {...widget.initialMixed};
  String query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final tags = library.tags;
      final counts = library.tagCounts;
      final chosen = tags
          .where((tag) => (selected.contains(tag.id) || mixed.contains(tag.id)))
          .toList();
      final choices =
          tags
              .where(
                (tag) =>
                    !selected.contains(tag.id) &&
                    !mixed.contains(tag.id) &&
                    tag.name.toLowerCase().contains(query),
              )
              .toList()
            ..sort((a, b) {
              final byCount = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
              if (byCount != 0) return byCount;
              final byName = a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              );
              return byName != 0 ? byName : a.id.compareTo(b.id);
            });
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      final screen = MediaQuery.of(context);
      final availableHeight = (screen.size.height - screen.viewInsets.vertical)
          .clamp(0.0, screen.size.height);
      final enabled = !library.filterDeletingTag;

      final compactAction = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(56, 34)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      );
      return CompactAlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 600,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (availableHeight * .36).clamp(0.0, 360.0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chosen.isNotEmpty) ...[
                  if (mixed.isNotEmpty)
                    Text('带 − 的标签仅存在于部分所选歌曲', style: textTheme.labelSmall),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: availableHeight * .16,
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final tag in chosen)
                            Tooltip(
                              message: mixed.contains(tag.id)
                                  ? '部分歌曲已有 ${tag.name}，点击移除'
                                  : '取消选择 ${tag.name}',
                              child: Material(
                                shape: const StadiumBorder(),
                                clipBehavior: Clip.antiAlias,
                                color: mixed.contains(tag.id)
                                    ? scheme.secondaryContainer
                                    : scheme.primaryContainer,
                                child: InkWell(
                                  customBorder: const StadiumBorder(),
                                  onTap: enabled
                                      ? () => setState(() {
                                          selected.remove(tag.id);
                                          mixed.remove(tag.id);
                                        })
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      mixed.contains(tag.id)
                                          ? '− ${tag.name}'
                                          : tag.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelMedium?.copyWith(
                                        color: mixed.contains(tag.id)
                                            ? scheme.onSecondaryContainer
                                            : scheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                TextField(
                  key: ValueKey('${widget.prefix}-tag-search'),
                  style: textTheme.bodySmall,
                  onChanged: (value) =>
                      setState(() => query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: '搜索标签',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 26,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                if (choices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      tags.isEmpty
                          ? '尚无标签'
                          : query.isEmpty
                          ? '已选中全部标签'
                          : '没有匹配的可选标签',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: (choices.length + 1) ~/ 2,
                      itemBuilder: (context, row) => Row(
                        spacing: 3,
                        children: [
                          for (var column = 0; column < 2; column++)
                            Expanded(
                              child: row * 2 + column >= choices.length
                                  ? const SizedBox.shrink()
                                  : Builder(
                                      builder: (context) {
                                        final tag = choices[row * 2 + column];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 1,
                                          ),
                                          child: OutlinedButton(
                                            key: ValueKey(
                                              '${widget.prefix}-tag-${tag.id}',
                                            ),
                                            onPressed: enabled
                                                ? () => setState(
                                                    () => selected.add(tag.id),
                                                  )
                                                : null,
                                            style: OutlinedButton.styleFrom(
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              minimumSize: Size.zero,
                                              visualDensity:
                                                  VisualDensity.standard,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: .75,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              side: BorderSide(
                                                color: scheme.outlineVariant,
                                              ),
                                            ),
                                            child: Row(
                                              spacing: 4,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    tag.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  '${counts[tag.id] ?? 0}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: compactAction,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: compactAction,
            onPressed: enabled
                ? () => Navigator.pop<TagSelection>(context, (
                    selected: {
                      for (final tag in tags)
                        if (selected.contains(tag.id)) tag.id,
                    },
                    mixed: {
                      for (final tag in tags)
                        if (mixed.contains(tag.id)) tag.id,
                    },
                  ))
                : null,
            child: const Text('确认'),
          ),
        ],
      );
    },
  );
}
