import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import 'database.dart';
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
          tags.where((tag) => tag.name.toLowerCase().contains(query)).toList()
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
      final availableHeight =
          (screen.size.height -
                  screen.viewInsets.vertical -
                  screen.padding.vertical)
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
        alignment: Alignment.bottomCenter,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chosen.isNotEmpty) ...[
                if (mixed.isNotEmpty)
                  Text('带 − 的标签仅存在于部分所选歌曲', style: textTheme.labelSmall),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (availableHeight * .19).clamp(0.0, 160.0),
                  ),
                  child: SingleChildScrollView(
                    primary: false,
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
                const SizedBox(height: 9),
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
              SizedBox(
                height: (availableHeight * .36).clamp(0.0, 320.0),
                child: choices.isEmpty
                    ? Center(child: Text(tags.isEmpty ? '尚无标签' : '没有匹配的标签'))
                    : ListView.builder(
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: (choices.length + 1) ~/ 2,
                        itemBuilder: (context, row) => Row(
                          spacing: 4,
                          children: [
                            for (var column = 0; column < 2; column++)
                              Expanded(
                                child: row * 2 + column >= choices.length
                                    ? const SizedBox.shrink()
                                    : _choice(
                                        context,
                                        choices[row * 2 + column],
                                        counts,
                                        enabled,
                                      ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
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

  Widget _choice(
    BuildContext context,
    Tag tag,
    Map<String, int> counts,
    bool enabled,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = selected.contains(tag.id);
    final isMixed = mixed.contains(tag.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: isSelected,
        mixed: isMixed,
        child: OutlinedButton(
          key: ValueKey('${widget.prefix}-tag-${tag.id}'),
          onPressed: enabled
              ? () => setState(() {
                  if (!selected.remove(tag.id)) {
                    mixed.remove(tag.id);
                    selected.add(tag.id);
                  }
                })
              : null,
          style: OutlinedButton.styleFrom(
            alignment: AlignmentDirectional.centerStart,
            minimumSize: const Size(0, 44),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            side: BorderSide(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
            ),
            backgroundColor: isSelected
                ? scheme.primary
                : isMixed
                ? scheme.secondaryContainer
                : null,
            foregroundColor: isSelected
                ? scheme.onPrimary
                : isMixed
                ? scheme.onSecondaryContainer
                : scheme.onSurface,
          ),
          child: Row(
            spacing: 4,
            children: [
              if (isSelected) const Icon(Icons.check, size: 16),
              if (isMixed) const Icon(Icons.remove, size: 16),
              Expanded(
                child: Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${counts[tag.id] ?? 0}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
