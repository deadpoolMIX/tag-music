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

  void _pickTags(BuildContext context, int box) => showDialog<void>(
    context: context,
    builder: (_) => _RuleTagPicker(
      library: library,
      box: box,
      prefix: prefix,
      initial: _ids(rule, box),
      onChanged: (ids) => _replace(box, ids),
    ),
  );

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
    required this.onChanged,
  });
  final LibraryController library;
  final int box;
  final String prefix;
  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;
  @override
  State<_RuleTagPicker> createState() => _RuleTagPickerState();
}

class _RuleTagPickerState extends State<_RuleTagPicker> {
  late final selected = {...widget.initial};
  String query = '';
  @override
  Widget build(BuildContext context) => CompactAlertDialog(
    title: Text(_pickerTitles[widget.box]),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: ValueKey('${widget.prefix}-tag-search'),
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: '搜索标签',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          Flexible(
            child: ListenableBuilder(
              listenable: widget.library,
              builder: (context, _) {
                final tags = widget.library.tags
                    .where((t) => t.name.toLowerCase().contains(query))
                    .toList();
                return tags.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          widget.library.tags.isEmpty
                              ? '尚无标签，请先在标签页创建。'
                              : '没有匹配的标签',
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: tags.length,
                        itemBuilder: (_, i) {
                          final tag = tags[i];
                          return CheckboxListTile(
                            key: ValueKey('${widget.prefix}-tag-${tag.id}'),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            title: Text(tag.name),
                            value: selected.contains(tag.id),
                            onChanged: widget.library.filterDeletingTag
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        selected.add(tag.id);
                                      } else {
                                        selected.remove(tag.id);
                                      }
                                    });
                                    widget.onChanged({...selected});
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
