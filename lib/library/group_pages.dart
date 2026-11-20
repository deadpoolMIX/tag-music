import 'package:flutter/material.dart';

import '../core/fast_scrollbar.dart';
import '../core/desktop_navigation.dart';
import '../playback/cover_cache.dart';
import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'library_header.dart';
import 'library_search.dart';
import 'song_list.dart';
import 'track_cover.dart';

final _artistSeparator = RegExp(r'[;；、／]|\s+/\s*|\s*/\s+');

List<String> artistNames(String? metadata) => {
  for (final name in (metadata ?? '').split(_artistSeparator))
    if (name.trim().isNotEmpty) name.trim(),
}.toList();

Future<void> openArtistTracks(
  BuildContext context,
  LibraryController library,
  PlaybackController playback,
  String artist,
) => pushAppPage(
  context,
  () => MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) => _GroupSongs(
            name: artist,
            albums: false,
            library: library,
            playback: playback,
            rows: library.availableTracks
                .where(
                  (track) => artistNames(track.song.artist).contains(artist),
                )
                .toList(),
          ),
        ),
      ),
    ),
  ),
);

class _GroupSongs extends StatelessWidget {
  const _GroupSongs({
    required this.name,
    required this.albums,
    required this.library,
    required this.playback,
    required this.rows,
    this.menuButton,
    this.onBack,
  });

  final String? name;
  final bool albums;
  final LibraryController library;
  final PlaybackController playback;
  final List<LibraryTrack> rows;
  final Widget? menuButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SongList(
    key: ValueKey((albums, name)),
    library: library,
    playback: playback,
    source: rows,
    rows: rows,
    scope: albums ? 'album' : 'artist',
    emptyText: '没有歌曲',
    header: SongGroupHeader(
      name: name ?? (albums ? '未知专辑' : '未知歌手'),
      menuButton: menuButton,
      tracks: rows,
      playback: playback,
    ),
    onBack: onBack,
  );
}

/// A compact, consistently ordered list for library groups.
class GroupList<T> extends StatefulWidget {
  const GroupList({
    required this.storageKey,
    required this.descending,
    required this.onSort,
    required this.items,
    required this.nameOf,
    required this.searchHint,
    required this.itemBuilder,
    required this.emptyText,
    this.menuButton,
    this.heading,
    this.trailing,
    this.coverCache,
    super.key,
  });
  final String storageKey;
  final bool descending;
  final VoidCallback onSort;
  final List<T> items;
  final String Function(T) nameOf;
  final String searchHint;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyText;
  final Widget? menuButton;
  final Widget? heading;
  final Widget? trailing;
  final CoverCache? coverCache;

  @override
  State<GroupList<T>> createState() => _GroupListState<T>();
}

class _GroupListState<T> extends State<GroupList<T>> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LibrarySearch(
    hintText: widget.searchHint,
    heading: widget.heading,
    onQueryChanged: () {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    },
    builder: (context, query, heading, searchButton) {
      final items = query.isEmpty
          ? widget.items
          : widget.items
                .where(
                  (item) => widget.nameOf(item).toLowerCase().contains(query),
                )
                .toList();
      return Column(
        children: [
          LibraryHeader(
            menuButton: widget.menuButton,
            heading: heading,
            actions: [
              TextButton.icon(
                onPressed: widget.onSort,
                icon: Icon(
                  widget.descending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                ),
                label: Text(widget.descending ? '名称降序' : '名称升序'),
              ),
              searchButton,
              ?widget.trailing,
            ],
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        query.isEmpty ? widget.emptyText : '没有匹配的结果',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListTileTheme(
                    dense: true,
                    minVerticalPadding: 8,
                    contentPadding: const EdgeInsets.fromLTRB(
                      16,
                      0,
                      FastScrollbar.rowEndPadding,
                      0,
                    ),
                    child: _list(items),
                  ),
          ),
        ],
      );
    },
  );

  Widget _list(List<T> items) {
    final list = FastScrollbar(
      controller: _scroll,
      child: ListView.builder(
        key: PageStorageKey(widget.storageKey),
        controller: _scroll,
        padding: const EdgeInsets.only(right: FastScrollbar.gutter),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            widget.itemBuilder(context, items[index]),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      ),
    );
    final cache = widget.coverCache;
    return cache == null ? list : CoverScrollRegion(cache: cache, child: list);
  }
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

  void _viewGroup(bool open, String? name) {
    void show((bool, String?) view) {
      if (!mounted) return;
      setState(() {
        opened = view.$1;
        selected = view.$2;
      });
    }

    final history = DesktopNavigation.maybeOf(context);
    if (history == null) {
      show((open, name));
    } else {
      history.visit(context, this, (opened, selected), (open, name), show);
    }
  }

  Iterable<String?> groupNames(LibraryTrack track) {
    if (widget.albums) {
      final album = track.song.album;
      return [album == null || album.trim().isEmpty ? null : album];
    }
    final names = artistNames(track.song.artist);
    return names.isEmpty ? [null] : names;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final groups = <String?, List<LibraryTrack>>{};
      for (final track in widget.library.availableTracks) {
        for (final name in groupNames(track)) {
          groups.putIfAbsent(name, () => []).add(track);
        }
      }
      final unknown = widget.albums ? '未知专辑' : '未知歌手';
      if (opened) {
        final rows = groups[selected] ?? <LibraryTrack>[];
        final desktop = DesktopNavigation.maybeOf(context) != null;
        return _GroupSongs(
          menuButton: widget.menuButton,
          onBack: desktop || !widget.active
              ? null
              : () => _viewGroup(false, selected),
          name: selected,
          albums: widget.albums,
          library: widget.library,
          playback: widget.playback,
          rows: rows,
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
        coverCache: widget.albums ? widget.library.documents.coverCache : null,
        descending: descending,
        onSort: () => setState(() => descending = !descending),
        items: keys,
        nameOf: (key) => key ?? unknown,
        searchHint: widget.albums ? '搜索专辑' : '搜索歌手',
        emptyText: '暂无歌曲',
        itemBuilder: (_, key) {
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
            onTap: () => _viewGroup(true, key),
          );
        },
      );
    },
  );
}
