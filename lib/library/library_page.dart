import 'package:flutter/material.dart';

import '../core/compact_dialog.dart';
import '../core/desktop_navigation.dart';
import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'database.dart';
import 'library_search_page.dart';
import 'relocation_dialog.dart';
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
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('歌曲排序')),
              for (final option in [
                (LibrarySort.title, '歌名'),
                (LibrarySort.artist, '歌手'),
                (LibrarySort.modified, '修改时间'),
              ])
                ListTile(
                  dense: true,
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
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final rows = library.visible;
      return SongList(
        header: Column(
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
                  onPressed: () => pushAppPage(
                    context,
                    () => MaterialPageRoute<void>(
                      builder: (_) => LibrarySearchPage(
                        library: library,
                        playback: playback,
                      ),
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
                      library.directoryBusy ||
                          !library.roots.any(
                            (root) => !root.requiresReselection,
                          )
                      ? null
                      : () => library.scan(),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: library.showMissing ? '返回可播放歌曲' : '查看失联歌曲',
                  isSelected: library.showMissing,
                  onPressed: () =>
                      library.filter(missing: !library.showMissing),
                  icon: const Icon(Icons.link_off),
                ),
                const Spacer(),
                Text(
                  library.showMissing
                      ? '${rows.length} 首失联'
                      : '${rows.length}首',
                ),
                const SizedBox(width: 16),
              ],
            ),
            LibraryStatus(library: library),
          ],
        ),
        emptyText: library.showMissing
            ? '没有失联歌曲'
            : library.roots.isEmpty
            ? '添加音乐文件夹，建立本机曲库'
            : '没有匹配的歌曲',
        library: library,
        playback: playback,
        source: library.searchTracks(
          '',
          order: library.sort,
          descending: library.descending,
        ),
        rows: rows,
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
      if (library.hashingBaselines) ...[
        const LinearProgressIndicator(),
        Row(
          children: [
            Expanded(
              child: Text('正在保存歌曲指纹 · 已处理 ${library.baselineProcessed} 首'),
            ),
            TextButton(
              onPressed: library.baselineCancelling
                  ? null
                  : library.cancelBaselines,
              child: const Text('取消'),
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
              onPressed: library.directoryBusy ? null : library.chooseDirectory,
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
  builder: (context) => CompactAlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('音乐目录')),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    content: SizedBox(
      width: 380,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) => library.roots.isEmpty
            ? const Text('尚未添加目录')
            : ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final root in library.roots)
                    _DirectoryRow(
                      key: ValueKey(root.location),
                      library: library,
                      root: root,
                    ),
                ],
              ),
      ),
    ),
    actions: [
      ListenableBuilder(
        listenable: library,
        builder: (context, _) => Tooltip(
          message: '搬走或重命名文件前保存，方便以后按文件内容找回',
          child: TextButton.icon(
            onPressed: library.hashingBaselines
                ? (library.baselineCancelling ? null : library.cancelBaselines)
                : (library.directoryBusy || library.availableTracks.isEmpty
                      ? null
                      : library.startBaselines),
            icon: const Icon(Icons.fingerprint),
            label: Text(
              library.hashingBaselines
                  ? '取消保存（${library.baselineProcessed} 首）'
                  : '保存搬家指纹',
            ),
          ),
        ),
      ),
    ],
  ),
);

class _DirectoryRow extends StatefulWidget {
  const _DirectoryRow({required this.library, required this.root, super.key});
  final LibraryController library;
  final LibraryRoot root;

  @override
  State<_DirectoryRow> createState() => _DirectoryRowState();
}

class _DirectoryRowState extends State<_DirectoryRow> {
  late final _name = widget.library.documents.directoryName(
    widget.root.location,
  );

  Future<void> _confirmRemoval(String name) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => CompactAlertDialog(
        title: const Text('移除音乐目录？'),
        content: Text('将「$name」从曲库移除。音乐文件、标签和歌单记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted || remove != true) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await widget.library.removeDirectory(widget.root.location)) {
      messenger?.showSnackBar(const SnackBar(content: Text('目录未能移除，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: widget.root.requiresReselection ? null : _name,
    builder: (context, snapshot) {
      final root = widget.root;
      final name = root.requiresReselection
          ? root.location
          : snapshot.data ?? (snapshot.hasError ? '无法读取名称' : '正在读取名称…');
      final enabled = !widget.library.directoryBusy;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          root.requiresReselection || root.accessible ? root.status : '目录不可访问',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '刷新该目录',
              onPressed: enabled && !root.requiresReselection
                  ? () => widget.library.scan([root.location])
                  : null,
              icon: const Icon(Icons.refresh, size: 20),
            ),
            IconButton(
              tooltip: '重新定位',
              onPressed: enabled
                  ? () => showDirectoryRelocation(context, widget.library, root)
                  : null,
              icon: const Icon(Icons.drive_file_move_outline, size: 20),
            ),
            IconButton(
              tooltip: '移除该目录',
              onPressed: enabled ? () => _confirmRemoval(name) : null,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ),
      );
    },
  );
}
