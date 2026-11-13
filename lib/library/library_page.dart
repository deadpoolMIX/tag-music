import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'library_search_page.dart';
import 'song_list.dart';
export 'track_cover.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    required this.library,
    required this.playback,
    this.menuButton,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  final Widget? menuButton;

  Future<void> _sort(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .5,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              children: [
                const Padding(padding: EdgeInsets.all(16), child: Text('歌曲排序')),
                for (final option in [
                  (LibrarySort.title, '歌名'),
                  (LibrarySort.artist, '歌手'),
                  (LibrarySort.modified, '修改时间'),
                ])
                  ListTile(
                    title: Text(option.$2),
                    selected: library.sort == option.$1,
                    trailing: library.sort == option.$1
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => library.filter(order: option.$1),
                  ),
                Wrap(
                  children: [
                    ChoiceChip(
                      label: const Text('升序'),
                      selected: !library.descending,
                      onSelected: (_) => library.filter(reverse: false),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('降序'),
                      selected: library.descending,
                      onSelected: (_) => library.filter(reverse: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final rows = library.visible;
      return Column(
        children: [
          Row(
            children: [
              ?menuButton,
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '歌曲',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const ValueKey('open-library-search'),
                tooltip: '搜索全曲库',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LibrarySearchPage(library: library, playback: playback),
                  ),
                ),
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: '歌曲排序',
                onPressed: () => _sort(context),
                icon: const Icon(Icons.sort),
              ),
              IconButton(
                tooltip: '刷新所有目录',
                onPressed:
                    library.scanning ||
                        library.choosing ||
                        library.roots.isEmpty
                    ? null
                    : () => library.scan(),
                icon: const Icon(Icons.refresh),
              ),
              const Spacer(),
              Text('${rows.length}首'),
              const SizedBox(width: 16),
            ],
          ),
          LibraryStatus(library: library),
          Expanded(
            child: SongList(
              emptyText: library.tracks.isEmpty ? '添加音乐文件夹，建立本机曲库' : '没有匹配的歌曲',
              library: library,
              playback: playback,
              source: library.searchTracks(
                '',
                order: library.sort,
                descending: library.descending,
              ),
              rows: rows,
            ),
          ),
        ],
      );
    },
  );
}

class LibraryStatus extends StatelessWidget {
  const LibraryStatus({required this.library, super.key});
  final LibraryController library;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (library.scanning) ...[
        const LinearProgressIndicator(),
        Row(
          children: [
            Expanded(
              child: Text(
                '发现 ${library.discovered} 首 · 读取元数据 ${library.metadataReads} 首',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: library.cancelScan,
              child: const Text('取消扫描'),
            ),
          ],
        ),
      ],
      if (library.message != null)
        Text(library.message!, maxLines: 2, overflow: TextOverflow.ellipsis),
    ],
  );
}

class DirectorySettings extends StatelessWidget {
  const DirectorySettings({required this.library, super.key});
  final LibraryController library;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          children: [
            FilledButton.icon(
              key: const ValueKey('choose-directory'),
              onPressed: library.scanning || library.choosing
                  ? null
                  : library.chooseDirectory,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加文件夹'),
            ),
            TextButton.icon(
              onPressed: () => showDirectoryManager(context, library),
              icon: const Icon(Icons.folder_outlined),
              label: const Text('管理目录'),
            ),
          ],
        ),
        LibraryStatus(library: library),
      ],
    ),
  );
}

Future<void> showDirectoryManager(
  BuildContext context,
  LibraryController library,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('音乐目录'),
    content: SizedBox(
      width: 520,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.roots.isEmpty
            ? const Text('尚未添加目录')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final root in library.roots)
                    ListTile(
                      title: Text(
                        root.location,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(root.status),
                      trailing: IconButton(
                        tooltip: '刷新该目录',
                        onPressed: library.scanning || library.choosing
                            ? null
                            : () => library.scan([root.location]),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                ],
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
