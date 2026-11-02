import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../playback/documents.dart';
import '../playback/playback_controller.dart';
import '../playback/queue_actions.dart';
import 'library_controller.dart';
import 'library_search.dart';
import 'tags_page.dart';
import 'playlist_actions.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({required this.library, required this.playback, super.key});
  final LibraryController library;
  final PlaybackController playback;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibraryController get library => widget.library;
  PlaybackController get playback => widget.playback;
  bool selecting = false;
  final Set<String> selected = {};

  void toggle(String id) => setState(() {
    if (!selected.add(id)) selected.remove(id);
  });

  void endSelection() => setState(() {
    selected.clear();
    selecting = false;
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final rows = library.visible;
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .65,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('choose-directory'),
                            onPressed: library.scanning || library.choosing
                                ? null
                                : library.chooseDirectory,
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('添加文件夹'),
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
                          IconButton(
                            tooltip: '管理目录',
                            onPressed: () => _directories(context),
                            icon: const Icon(Icons.folder_outlined),
                          ),
                          if (library.scanning)
                            TextButton(
                              onPressed: library.cancelScan,
                              child: const Text('取消扫描'),
                            ),
                          TextButton.icon(
                            key: const ValueKey('select-songs'),
                            onPressed: () => setState(() {
                              selecting = !selecting;
                              if (!selecting) selected.clear();
                            }),
                            icon: Icon(
                              selecting ? Icons.close : Icons.checklist,
                            ),
                            label: Text(selecting ? '退出多选' : '多选歌曲'),
                          ),
                          Text('${rows.length} / ${library.tracks.length} 首'),
                          QueueAddButton(
                            key: const ValueKey('enqueue-library'),
                            playback: playback,
                            songs: rows
                                .where((t) => t.available)
                                .map((t) => t.queueSong)
                                .toList(),
                          ),
                          TextButton.icon(
                            key: const ValueKey('save-library-playlist'),
                            onPressed: () => savePlaylist(
                              context,
                              library,
                              rows.map((t) => t.song.id),
                            ),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('保存列表为歌单'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (selecting)
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('已选 ${selected.length} 首'),
                            QueueAddButton(
                              key: const ValueKey('enqueue-library-selected'),
                              playback: playback,
                              songs: library
                                  .selectedTracks(selected)
                                  .where((t) => t.available)
                                  .map((t) => t.queueSong)
                                  .toList(),
                            ),
                            TextButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => setState(selected.clear),
                              child: const Text('清空选择'),
                            ),
                            FilledButton(
                              key: const ValueKey('batch-tags'),
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => showTagActions(
                                      context,
                                      library,
                                      Set.of(selected),
                                    ),
                              child: const Text('批量编辑标签'),
                            ),
                            TextButton(
                              key: const ValueKey('batch-add-playlist'),
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => addToPlaylist(
                                      context,
                                      library,
                                      library
                                          .selectedTracks(selected)
                                          .map((t) => t.song.id),
                                    ),
                              child: const Text('添加到歌单'),
                            ),
                          ],
                        ),
                      LibrarySearch(
                        library: library,
                        documents: playback.documents,
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<LibrarySort>(
                            value: library.sort,
                            onChanged: (v) => library.filter(order: v),
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
                            tooltip: library.descending ? '改为升序' : '改为降序',
                            onPressed: () =>
                                library.filter(reverse: !library.descending),
                            icon: Icon(
                              library.descending ? Icons.south : Icons.north,
                            ),
                          ),
                          FilterChip(
                            label: const Text('显示失联'),
                            selected: library.showMissing,
                            onSelected: (v) => library.filter(missing: v),
                          ),
                        ],
                      ),
                      if (library.scanning) ...[
                        const LinearProgressIndicator(),
                        Text(
                          '发现 ${library.discovered} 首 · 读取元数据 ${library.metadataReads} 首',
                          maxLines: 1,
                        ),
                      ],
                      if (library.message != null)
                        Text(
                          library.message!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (playback.error != null)
                        Text(
                          playback.error!,
                          key: const ValueKey('playback-error'),
                          maxLines: 2,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (!playback.notificationsEnabled)
                        TextButton(
                          onPressed: playback.requestNotificationPermission,
                          child: const Text('开启播放通知'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        library.tracks.isEmpty ? '添加音乐文件夹，建立本机曲库' : '没有匹配的歌曲',
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final track = rows[index];
                        final assigned = library.tags
                            .where(
                              (tag) =>
                                  library.tagIdsBySong[track.song.id]?.contains(
                                    tag.id,
                                  ) ==
                                  true,
                            )
                            .map((tag) => tag.name)
                            .join('、');
                        return ListTile(
                          key: ValueKey(track.song.id),
                          selected: track.song.id == playback.currentSongId,
                          leading: Icon(
                            selecting
                                ? selected.contains(track.song.id)
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank
                                : track.available
                                ? Icons.music_note_outlined
                                : Icons.link_off,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if (track.available)
                                [
                                  track.song.artist ?? '未知歌手',
                                  track.song.album,
                                  track.song.name,
                                ].nonNulls.join(' · ')
                              else
                                '文件失联 · 记录仍保留',
                              if (assigned.isNotEmpty) '标签：$assigned',
                              if (track.song.metadataError != null) '元数据不可读',
                            ].join('\n'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selecting
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    QueueAddButton(
                                      key: ValueKey(
                                        'enqueue-library-${track.song.id}',
                                      ),
                                      playback: playback,
                                      songs: track.available
                                          ? [track.queueSong]
                                          : const [],
                                      compact: true,
                                    ),
                                    IconButton(
                                      tooltip: '编辑${track.title}的标签',
                                      onPressed: () => showTagActions(
                                        context,
                                        library,
                                        {track.song.id},
                                      ),
                                      icon: const Icon(Icons.sell_outlined),
                                    ),
                                  ],
                                ),
                          onLongPress: () => setState(() {
                            selecting = true;
                            selected.add(track.song.id);
                          }),
                          onTap: selecting
                              ? () => toggle(track.song.id)
                              : !track.available
                              ? null
                              : () {
                                  final snapshot = rows
                                      .where((t) => t.available)
                                      .toList();
                                  playback.playSongs(
                                    snapshot.map((t) => t.queueSong).toList(),
                                    snapshot.indexOf(track),
                                  );
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _directories(BuildContext context) => showDialog<void>(
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
                          onPressed: library.scanning
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
}

class TrackCover extends StatefulWidget {
  const TrackCover({required this.documents, required this.track, super.key});
  final DocumentAccess documents;
  final ProbeTrack track;
  @override
  State<TrackCover> createState() => _TrackCoverState();
}

class _TrackCoverState extends State<TrackCover> {
  late final Future<Uint8List?> _cover = widget.documents.cover(widget.track);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _cover,
    builder: (context, snapshot) => SizedBox(
      height: 48,
      width: 48,
      child: snapshot.data == null
          ? const Icon(Icons.album_outlined, size: 40)
          : Image.memory(
              snapshot.data!,
              cacheWidth: 96,
              cacheHeight: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.album_outlined, size: 40),
            ),
    ),
  );
}
