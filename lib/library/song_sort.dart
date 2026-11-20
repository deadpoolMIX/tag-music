import 'package:flutter/material.dart';

import 'filter_rule.dart';

class SongSortButton extends StatelessWidget {
  const SongSortButton({
    required this.order,
    required this.descending,
    required this.onChanged,
    this.includePlayCount = false,
    super.key,
  });

  final LibrarySort? order;
  final bool descending;
  final void Function(LibrarySort?, bool) onChanged;
  final bool includePlayCount;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '歌曲排序',
    icon: const Icon(Icons.sort),
    onPressed: () {
      var selected = order;
      var reverse = descending;
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) {
              void change(LibrarySort? field, bool descending) {
                setState(() {
                  selected = field;
                  reverse = descending;
                });
                onChanged(field, descending);
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('歌曲排序'),
                    ),
                    for (final option in <(LibrarySort?, String)>[
                      (LibrarySort.title, '歌名'),
                      (LibrarySort.artist, '歌手'),
                      (LibrarySort.modified, '修改时间'),
                      if (includePlayCount) (null, '播放次数'),
                    ])
                      ListTile(
                        dense: true,
                        title: Text(option.$2),
                        selected: selected == option.$1,
                        trailing: selected == option.$1
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => change(option.$1, reverse),
                      ),
                    Wrap(
                      children: [
                        ChoiceChip(
                          label: Text(selected == null ? '少到多' : '升序'),
                          selected: !reverse,
                          onSelected: (_) => change(selected, false),
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: Text(selected == null ? '多到少' : '降序'),
                          selected: reverse,
                          onSelected: (_) => change(selected, true),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
