import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'library_header.dart';
import 'song_list.dart';
import 'track_cover.dart';

/// A compact, consistently ordered list for library groups.
class GroupList extends StatelessWidget {
  const GroupList({
    required this.storageKey,
    required this.descending,
    required this.onSort,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyText,
    this.menuButton,
    this.heading,
    this.trailing,
    super.key,
  });
  final String storageKey;
  final bool descending;
  final VoidCallback onSort;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String emptyText;
  final Widget? menuButton;
  final Widget? heading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LibraryHeader(
        menuButton: menuButton,
        heading: heading,
        actions: [
          TextButton.icon(
            onPressed: onSort,
            icon: Icon(
              descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
            ),
            label: Text(descending ? '名称降序' : '名称升序'),
          ),
          ?trailing,
        ],
      ),
      Expanded(
        child: itemCount == 0
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(emptyText, textAlign: TextAlign.center),
                ),
              )
            : ListTileTheme(
                dense: true,
                minVerticalPadding: 8,
                child: ListView.builder(
                  key: PageStorageKey(storageKey),
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
              ),
      ),
    ],
  );
}

class MetadataGroupsPage extends StatefulWidget {
  const MetadataGroupsPage({
    required this.library,
    required this.playback,
    required this.albums,
    required this.active,
    this.menuButton,
    super.key,
  });
  final LibraryController library;
  final PlaybackController playback;
  final bool albums;
  final bool active;
  final Widget? menuButton;
  @override
  State<MetadataGroupsPage> createState() => _MetadataGroupsPageState();
}

class _MetadataGroupsPageState extends State<MetadataGroupsPage> {
  bool descending = false;
  bool opened = false;
  String? selected;

  String? groupName(LibraryTrack track) {
    final value = widget.albums ? track.song.album : track.song.artist;
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final groups = <String?, List<LibraryTrack>>{};
      for (final track in widget.library.tracks) {
        groups.putIfAbsent(groupName(track), () => []).add(track);
      }
      final unknown = widget.albums ? '未知专辑' : '未知歌手';
      if (opened) {
        final rows = groups[selected] ?? <LibraryTrack>[];
        return PopScope(
          canPop: !widget.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.active) setState(() => opened = false);
          },
          child: Column(
            children: [
              Row(
                children: [
                  ?widget.menuButton,
                  IconButton(
                    tooltip: '返回分组',
                    onPressed: () => setState(() => opened = false),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      selected ?? unknown,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('${rows.length} 首'),
                  ),
                ],
              ),
              Expanded(
                child: SongList(
                  key: ValueKey((widget.albums, selected)),
                  library: widget.library,
                  playback: widget.playback,
                  source: rows,
                  rows: rows,
                  scope: widget.albums ? 'album' : 'artist',
                  emptyText: '没有歌曲',
                ),
              ),
            ],
          ),
        );
      }
      final keys = groups.keys.toList()
        ..sort((a, b) {
          final c = (a ?? unknown).toLowerCase().compareTo(
            (b ?? unknown).toLowerCase(),
          );
          final stable = c != 0
              ? c
              : (a == null
                    ? -1
                    : b == null
                    ? 1
                    : a.compareTo(b));
          return descending ? -stable : stable;
        });
      return GroupList(
        menuButton: widget.menuButton,
        heading: Text(
          widget.albums ? '专辑' : '歌手',
          key: ValueKey(widget.albums ? 'albums-heading' : 'artists-heading'),
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        storageKey: widget.albums ? 'albums-overview' : 'artists-overview',
        descending: descending,
        onSort: () => setState(() => descending = !descending),
        itemCount: keys.length,
        emptyText: '暂无歌曲',
        itemBuilder: (_, index) {
          final key = keys[index];
          final tracks = groups[key]!;
          final coverTracks = widget.albums
              ? tracks
                    .where((track) => track.available)
                    .map((track) => track.probe)
                    .toList()
              : null;
          return ListTile(
            leading: coverTracks == null
                ? const Icon(Icons.person_outline)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TrackCover.album(
                      documents: widget.library.documents,
                      tracks: coverTracks,
                      size: 42,
                    ),
                  ),
            title: Text(
              key ?? unknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${tracks.length} 首${key == null ? (widget.albums ? ' · 未提供专辑信息' : ' · 未提供歌手信息') : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() {
              selected = key;
              opened = true;
            }),
          );
        },
      );
    },
  );
}
