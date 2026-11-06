import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_page.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_page.dart';
import 'package:tag_music/library/playlists_page.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

import 'library_page_test.dart' as helper show SnapshotController;
import 'library_test.dart' show FakeDocuments, entry;

class PlaylistPlayback extends helper.SnapshotController {
  final _queue = PlaybackQueue();
  @override
  PlaybackQueue get queue => _queue;
  @override
  Future<void> playSongs(List<QueueSong> snapshot, int target) async {
    queue.replace(snapshot, target);
    await super.playSongs(snapshot, target);
  }
}

void main() {
  late LibraryController library;
  late PlaylistPlayback playback;
  late Map<String, String> ids;

  setUp(() async {
    final access = FakeDocuments()
      ..files['root'] = [entry('A'), entry('B'), entry('C')];
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      access,
    );
    playback = PlaylistPlayback()..current = null;
    await library.initialize();
    await library.scan();
    ids = {
      for (final track in library.tracks) track.song.identity: track.song.id,
    };
  });
  tearDown(() async {
    await library.shutdown();
    playback.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> saveName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const ValueKey('playlist-name')), name);
    await tester.tap(find.byKey(const ValueKey('save-playlist-confirm')));
    await tester.pumpAndSettle();
  }

  Widget page() => PlaylistsPage(library: library, playback: playback);

  for (final offset in [Offset.zero, const Offset(20, 0)]) {
    testWidgets(
      'holding the playlist handle at $offset before dragging changes stored order',
      (tester) async {
        final id = await library.createPlaylist('Held drag', [
          ids['A']!,
          ids['B']!,
        ]);
        await mount(tester, page());
        await tester.tap(find.byKey(ValueKey('playlist-$id')));
        await tester.pumpAndSettle();
        final start =
            tester.getCenter(find.byType(ReorderableDragStartListener).first) +
            offset;
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 800));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.moveTo(start + const Offset(0, 160));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(library.playlistSongIds[id], [ids['B'], ids['A']]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final smart in [false, true]) {
    testWidgets(
      'system back returns ${smart ? 'smart' : 'ordinary'} detail to overview',
      (tester) async {
        final id = smart
            ? await library.createSmartPlaylist('Back', FilterPreferences())
            : await library.createPlaylist('Back', [ids['A']!]);
        await mount(tester, page());
        await tester.tap(find.byKey(ValueKey('playlist-$id')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('create-playlist')), findsOneWidget);
        expect(find.byKey(ValueKey('playlist-$id')), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('playlist-$id')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('playlist-search-$id')), findsOneWidget);
        await tester.tap(find.byTooltip('返回歌单'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('create-playlist')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'empty create, searchable batch picker, drag order and selection removal',
    (tester) async {
      await mount(tester, page());
      await tester.tap(find.byKey(const ValueKey('create-playlist')));
      await tester.pumpAndSettle();
      await saveName(tester, '  常听  ');
      final id = library.playlists.single.id;
      expect(library.playlists.single.name, '常听');
      await tester.tap(find.byKey(ValueKey('playlist-$id')));
      await tester.pumpAndSettle();
      expect(find.text('空歌单，添加歌曲后即可播放'), findsOneWidget);
      // A previous library search must not hide songs from the picker.
      library.filter(text: 'B');
      await tester.tap(find.byKey(const ValueKey('playlist-add-songs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('pick-${ids['A']}')));
      await tester.enterText(
        find.byKey(const ValueKey('playlist-picker-search')),
        'C',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('pick-${ids['C']}')));
      await tester.tap(find.byKey(const ValueKey('playlist-picker-confirm')));
      await tester.pumpAndSettle();
      expect(library.playlistSongIds[id], [ids['A'], ids['C']]);
      expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
      final start = tester.getCenter(
        find.byType(ReorderableDragStartListener).first,
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(start + const Offset(0, 160));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(library.playlistSongIds[id], [ids['C'], ids['A']]);
      await tester.enterText(find.byKey(ValueKey('playlist-search-$id')), 'A');
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.text('搜索中不能重排歌曲'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('playlist-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-song-${ids['A']}')));
      await tester.enterText(find.byKey(ValueKey('playlist-search-$id')), 'C');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-song-${ids['C']}')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 首'), findsOneWidget);
      await tester.tap(find.text('移除所选歌曲'));
      await tester.pumpAndSettle();
      expect(library.playlistTracks(id), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'save complete queue by displayed order, rename validation, cancel/confirm delete keep queue',
    (tester) async {
      final rows = {
        for (final track in library.tracks) track.song.identity: track,
      };
      await playback.playSongs([
        rows['C']!.queueSong,
        rows['A']!.queueSong,
        rows['C']!.queueSong,
        rows['B']!.queueSong,
      ], 0);
      final original = playback.queue.entries.map((e) => e.entryId).toList();
      await library.createPlaylist('Other', []);
      await mount(tester, page());
      await tester.tap(find.byKey(const ValueKey('save-queue-playlist')));
      await tester.pumpAndSettle();
      await saveName(tester, 'Queue');
      final id = library.playlists.singleWhere((p) => p.name == 'Queue').id;
      expect(library.playlistSongIds[id], [ids['C'], ids['A'], ids['B']]);
      await tester.tap(find.byKey(ValueKey('playlist-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('歌单操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('改名'));
      await tester.pumpAndSettle();
      await saveName(tester, ' other ');
      expect(find.textContaining('已有同名歌单'), findsOneWidget);
      await saveName(tester, 'Renamed');
      expect(find.text('Renamed'), findsOneWidget);
      Future<void> delete() async {
        await tester.tap(find.byTooltip('歌单操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
      }

      await delete();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(library.playlists, hasLength(2));
      await delete();
      await tester.tap(find.text('删除歌单'));
      await tester.pumpAndSettle();
      expect(library.playlists, hasLength(1));
      expect(playback.queue.entries.map((e) => e.entryId), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'library list is captured before save dialog and cross-search selections all add',
    (tester) async {
      library.filter(text: 'A');
      await mount(tester, LibraryPage(library: library, playback: playback));
      await tester.tap(find.byKey(const ValueKey('save-library-playlist')));
      await tester.pumpAndSettle();
      library.filter(text: 'B');
      await saveName(tester, 'Captured');
      final id = library.playlists.single.id;
      expect(library.playlistSongIds[id], [ids['A']]);
      await tester.tap(find.byKey(const ValueKey('select-songs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(ids['B']!)));
      library.filter(text: 'C');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(ids['C']!)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('batch-add-playlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Captured'));
      await tester.pumpAndSettle();
      expect(library.playlistSongIds[id], [ids['A'], ids['B'], ids['C']]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'filter result saves current search order as ordinary membership',
    (tester) async {
      library.searchFilter('B');
      await mount(tester, FilterPage(library: library, playback: playback));
      await tester.tap(find.byKey(const ValueKey('save-filter-playlist')));
      await tester.pumpAndSettle();
      await saveName(tester, 'Filtered');
      expect(library.playlistSongIds[library.playlists.single.id], [ids['B']]);
      library.searchFilter('');
      expect(library.playlistSongIds[library.playlists.single.id], [ids['B']]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small screen song click plays ordered snapshot and keyboard keeps shared playback bar usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = await library.createPlaylist('Phone', [
        ids['C']!,
        ids['A']!,
        ids['B']!,
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWithValue(library),
            playbackProvider.overrideWithValue(playback),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PlaybackPage(playlists: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-song-${ids['A']}')));
      await tester.pumpAndSettle();
      expect(playback.queue.entries.map((e) => e.song.songId), [
        ids['C'],
        ids['A'],
        ids['B'],
      ]);
      expect(playback.currentSongId, ids['A']);
      final original = playback.queue.entries.map((e) => e.entryId).toList();
      await tester.enterText(find.byKey(ValueKey('playlist-search-$id')), 'C');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('play-pause')), findsOneWidget);
      expect(playback.queue.entries.map((e) => e.entryId), original);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
