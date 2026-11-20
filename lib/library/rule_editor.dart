import 'package:flutter/material.dart';

import 'filter_rule.dart';
import 'library_controller.dart';
import 'tag_picker.dart';

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
    final result = await showTagPicker(
      context,
      library,
      title: _pickerTitles[box],
      prefix: prefix,
      initial: _ids(rule, box),
    );
    if (context.mounted && result != null) _replace(box, result.selected);
  }

  Widget _compactBox(BuildContext context, int box) {
    final ids = _ids(rule, box);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final desktop = theme.platform == TargetPlatform.windows;
    return Tooltip(
      message: _titles[box],
      excludeFromSemantics: true,
      child: OutlinedButton(
        key: ValueKey('$prefix-pick-$box'),
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, desktop ? 72 : 48),
          alignment: AlignmentDirectional.topStart,
          padding: desktop
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
              : const EdgeInsets.all(6),
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
            if (desktop && ids.isNotEmpty) const SizedBox(height: 4),
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
      ? Theme.of(context).platform == TargetPlatform.windows
            ? Table(
                defaultVerticalAlignment:
                    TableCellVerticalAlignment.intrinsicHeight,
                columnWidths: const {
                  1: FixedColumnWidth(6),
                  3: FixedColumnWidth(6),
                },
                children: [
                  TableRow(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox.shrink(),
                        _compactBox(context, i),
                      ],
                    ],
                  ),
                ],
              )
            : IntrinsicHeight(
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
