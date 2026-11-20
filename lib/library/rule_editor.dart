import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';

import 'filter_rule.dart';
import 'library_controller.dart';

const ruleExplanation = '前两框结果合并，再扣除排除标签。前两框都空时，从全部可用歌曲中排除。';
const _titles = ['全部具备', '任一具备', '排除标签'];
const _symbols = ['∧', '∨', '−'];
const _pickerTitles = ['同时包含', '包含其一', '排除标签'];
const _hints = ['同时有这些标签', '至少有其中一个标签', '有任一标签就排除'];

Set<String> _ids(FilterRule rule, int box) => switch (box) {
  0 => rule.allTagIds,
  1 => rule.anyTagIds,
  _ => rule.excludedTagIds,
};

/// The same three-box editor serves the current filter and independent drafts.
class RuleEditor extends StatelessWidget {
  const RuleEditor({
    required this.library,
    required this.rule,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
    this.prefix = 'filter',
    super.key,
  });
  final LibraryController library;
  final FilterRule rule;
  final ValueChanged<FilterRule> onChanged;
  final bool enabled;
  final bool compact;
  final String prefix;

  void _replace(int box, Iterable<String> ids) => onChanged(
    FilterRule(
      allTagIds: box == 0 ? ids : rule.allTagIds,
      anyTagIds: box == 1 ? ids : rule.anyTagIds,
      excludedTagIds: box == 2 ? ids : rule.excludedTagIds,
    ),
  );

  Future<void> _pickTags(BuildContext context, int box) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _RuleTagPicker(
        library: library,
        box: box,
        prefix: prefix,
        initial: _ids(rule, box),
      ),
    );
    if (context.mounted && selected != null) _replace(box, selected);
  }

  Widget _compactBox(BuildContext context, int box) {
    final ids = _ids(rule, box);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _titles[box],
      excludeFromSemantics: true,
      child: OutlinedButton(
        key: ValueKey('$prefix-pick-$box'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          alignment: AlignmentDirectional.topStart,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: enabled ? () => _pickTags(context, box) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _symbols[box],
              semanticsLabel: _titles[box],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in library.tags.where(
                  (tag) => ids.contains(tag.id),
                ))
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const StadiumBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: Text(
                        tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(BuildContext context, int box) {
    final ids = _ids(rule, box);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_titles[box], style: Theme.of(context).textTheme.titleSmall),
            Text(_hints[box], style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 4,
              children: [
                for (final tag in library.tags.where((t) => ids.contains(t.id)))
                  InputChip(
                    key: ValueKey('$prefix-chip-$box-${tag.id}'),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        tag.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: enabled
                        ? () => _replace(box, ids.where((id) => id != tag.id))
                        : null,
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: ValueKey('$prefix-pick-$box'),
                  onPressed: enabled ? () => _pickTags(context, box) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('选择标签'),
                ),
                TextButton(
                  key: ValueKey('$prefix-clear-$box'),
                  onPressed: enabled && ids.isNotEmpty
                      ? () => _replace(box, [])
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

  @override
  Widget build(BuildContext context) => compact
      ? IntrinsicHeight(
          child: Row(
            spacing: 6,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(child: _compactBox(context, i)),
            ],
          ),
        )
      : LayoutBuilder(
          builder: (context, constraints) {
            final boxes = [for (var i = 0; i < 3; i++) _box(context, i)];
            return constraints.maxWidth >= 840
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final box in boxes) Expanded(child: box)],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: boxes,
                  );
          },
        );
}

class _RuleTagPicker extends StatefulWidget {
  const _RuleTagPicker({
    required this.library,
    required this.box,
    required this.prefix,
    required this.initial,
  });
  final LibraryController library;
  final int box;
  final String prefix;
  final Set<String> initial;
  @override
  State<_RuleTagPicker> createState() => _RuleTagPickerState();
}

class _RuleTagPickerState extends State<_RuleTagPicker> {
  late final selected = {...widget.initial};
  String query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final library = widget.library;
      final tags = library.tags;
      final counts = library.tagCounts;
      final chosen = tags.where((tag) => selected.contains(tag.id)).toList();
      final choices =
          tags
              .where(
                (tag) =>
                    !selected.contains(tag.id) &&
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
      final enabled = !library.filterDeletingTag;

      return CompactAlertDialog(
        title: Text(_pickerTitles[widget.box]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chosen.isNotEmpty) ...[
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in chosen)
                          Tooltip(
                            message: '取消选择 ${tag.name}',
                            child: ActionChip(
                              label: Text(
                                tag.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              shape: const StadiumBorder(),
                              side: BorderSide.none,
                              backgroundColor: scheme.primaryContainer,
                              labelStyle: TextStyle(
                                color: scheme.onPrimaryContainer,
                              ),
                              onPressed: enabled
                                  ? () =>
                                        setState(() => selected.remove(tag.id))
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              TextField(
                key: ValueKey('${widget.prefix}-tag-search'),
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: '搜索标签',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
                  flex: 3,
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: (choices.length + 1) ~/ 2,
                    itemBuilder: (context, row) => Row(
                      spacing: 8,
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
                                          bottom: 4,
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
                                            minimumSize: const Size(0, 42),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: enabled
                ? () =>
                      Navigator.pop(context, {for (final tag in chosen) tag.id})
                : null,
            child: const Text('确认'),
          ),
        ],
      );
    },
  );
}
