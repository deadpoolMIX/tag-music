import 'dart:typed_data';

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
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';
import 'package:tag_music/playback/queue_page.dart';

import 'library_test.dart' show FakeDocuments, entry;
import 'queue_playback_test.dart' show QueueDocuments, QueuePlayer, song;

class _Documents extends QueueDocuments {
  @override
  Future<Uint8List?> cover(ProbeTrack track) async => null;
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  late QueuePlayer player;
  late PlaybackController playback;
  late LibraryController library;
  late Map<String, LibraryTrack> tracks;

  setUp(() async {
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      FakeDocuments()..files['root'] = [entry('A'), entry('B'), entry('C')],
    );
    await library.initialize();
    await library.scan();
    tracks = {for (final t in library.tracks) t.song.identity: t};
  });
  tearDown(() async {
    await library.shutdown();
  });

  void queueTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      // Create the serial Future chain in the same clock zone as UI actions.
      player = QueuePlayer();
      playback = PlaybackController(player, _Documents());
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(playback.shutdown);
      }
    });
  }

  Future<void> mount(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    // Let the enqueue acknowledgement expire before targeting the bottom row.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  List<String> names() =>
      playback.queue.entries.map((e) => e.song.track.name).toList();

  queueTest(
    'cold empty queue is reachable, silent and default shuffle; modes are exclusive',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWithValue(library),
            playbackProvider.overrideWithValue(playback),
          ],
          child: const MaterialApp(home: Scaffold(body: PlaybackPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(playback.queue.mode, PlaybackMode.shuffle);
      expect(player.opens, isEmpty);
      final playPause = find.descendant(
        of: find.byKey(const ValueKey('global-minibar')),
        matching: find.byKey(const ValueKey('play-pause')),
      );
      expect(playPause, findsOneWidget);
      expect(tester.widget<IconButton>(playPause).onPressed, isNull);
      await tap(tester, find.byKey(const ValueKey('open-playback-queue')));
      expect(find.text('队列为空，从曲库、筛选或歌单添加歌曲'), findsOneWidget);
      for (final mode in PlaybackMode.values) {
        await tap(tester, find.byKey(const ValueKey('playback-mode')).last);
        final before = tester
            .widgetList<CheckedPopupMenuItem<PlaybackMode>>(
              find.byType(CheckedPopupMenuItem<PlaybackMode>),
            )
            .toList();
        expect(
          before.where((i) => i.checked).single.value,
          playback.queue.mode,
        );
        await tap(tester, find.byKey(ValueKey('playback-mode-${mode.name}')));
        expect(playback.queue.mode, mode);
        await tap(tester, find.byKey(const ValueKey('playback-mode')).last);
        final items = tester
            .widgetList<CheckedPopupMenuItem<PlaybackMode>>(
              find.byType(CheckedPopupMenuItem<PlaybackMode>),
            )
            .toList();
        expect(items, hasLength(PlaybackMode.values.length));
        expect(items.where((i) => i.checked).single.value, mode);
        for (final item in items) {
          expect(item.checked, item.value == mode);
        }
        Navigator.of(
          tester.element(find.byType(CheckedPopupMenuItem<PlaybackMode>).first),
        ).pop();
        await tester.pumpAndSettle();
      }
      await tap(tester, find.byTooltip('关闭队列'));
      expect(find.byKey(const ValueKey('open-playback-queue')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('open-playback-queue')));
      expect(find.text('队列为空，从曲库、筛选或歌单添加歌曲'), findsOneWidget);
      expect(playback.queue.entries, isEmpty);
      expect(player.opens, isEmpty);
      expect(playback.playing, isFalse);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    queueTest(
      '$platform duplicate entries, FIFO labels and reorder/mode keep playing progress',
      (tester) async {
        await playback.setMode(PlaybackMode.sequential);
        await playback.playSongs([song('original'), song('tail')], 0);
        await playback.seek(const Duration(seconds: 8));
        await playback.addToQueue([song('A'), song('A')]);
        await playback.addToQueue([song('B')]);
        final before = playback.queue.entries.toList();
        final firstA = before[1].entryId;
        final secondA = before[2].entryId;
        expect(firstA, isNot(secondA));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: QueuePage(playback: playback, library: library),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('A.flac'), findsNWidgets(2));
        expect(find.text('优先待播 1'), findsOneWidget);
        expect(find.text('优先待播 2'), findsOneWidget);
        final stops = player.stops;
        final start = tester.getCenter(
          find.byType(ReorderableDragStartListener).first,
        );
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 800));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.moveTo(Offset(start.dx, start.dy + 160));
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          playback.queue.entries.map((e) => e.entryId).toList(),
          isNot(before.map((e) => e.entryId).toList()),
        );
        expect(playback.queue.priorityIds, [
          firstA,
          secondA,
          before[3].entryId,
        ]);
        await tap(tester, find.byKey(const ValueKey('playback-mode')));
        await tap(
          tester,
          find.byKey(const ValueKey('playback-mode-repeatOne')),
        );
        expect(player.stops, stops);
        expect(player.state.position.inSeconds, 8);
        await tap(tester, find.byTooltip('下一首'));
        expect(playback.queue.current?.entryId, firstA);
        expect(find.text('优先待播 1'), findsOneWidget);
        expect(find.text('当前 · 已暂停'), findsNothing);
        await tap(tester, find.byKey(ValueKey('queue-entry-$secondA')));
        expect(playback.queue.current?.entryId, secondA);
        expect(playback.playing, isTrue);
        expect(playback.queue.entries, hasLength(5));
        await tap(tester, find.byTooltip('更多播放操作'));
        await tap(tester, find.text('停止播放'));
        expect(playback.queue.entries, hasLength(5));
        expect(player.state.position, Duration.zero);
        await tap(tester, find.byTooltip('播放'));
        expect(playback.queue.current?.entryId, secondA);
        expect(playback.playing, isTrue);
      },
    );
  }

  queueTest(
    'remove current retains pause/play, full queue save deduplicates, clear confirms',
    (tester) async {
      await playback.addToQueue([
        tracks['A']!.queueSong,
        tracks['B']!.queueSong,
        tracks['A']!.queueSong,
      ]);
      await mount(tester, QueuePage(playback: playback, library: library));
      expect(player.opens, isEmpty);
      await tap(tester, find.byKey(const ValueKey('save-full-queue')));
      await tester.enterText(
        find.byKey(const ValueKey('playlist-name')),
        '完整队列',
      );
      await tap(tester, find.byKey(const ValueKey('save-playlist-confirm')));
      expect(library.playlistSongIds[library.playlists.single.id], [
        tracks['A']!.song.id,
        tracks['B']!.song.id,
      ]);
      final first = playback.queue.current!.entryId;
      await tap(tester, find.byKey(ValueKey('queue-remove-$first')));
      expect(playback.currentSongId, tracks['B']!.song.id);
      expect(playback.playing, isFalse);
      await tap(tester, find.byTooltip('播放'));
      final second = playback.queue.current!.entryId;
      await tap(tester, find.byKey(ValueKey('queue-remove-$second')));
      expect(playback.currentSongId, tracks['A']!.song.id);
      expect(playback.playing, isTrue);
      await tap(tester, find.byKey(const ValueKey('clear-playback-queue')));
      await tap(tester, find.text('取消'));
      expect(playback.queue.entries, hasLength(1));
      await tap(tester, find.byKey(const ValueKey('clear-playback-queue')));
      await tap(tester, find.widgetWithText(FilledButton, '清空队列'));
      expect(playback.queue.entries, isEmpty);
      expect(playback.playing, isFalse);
      expect(player.state.playlist.medias, isEmpty);
    },
  );

  queueTest(
    'library hidden selection, filter search and both playlist kinds append in source order',
    (tester) async {
      await playback.playSongs([song('old')], 0);
      final original = playback.queue.current!.entryId;
      final stops = player.stops;
      library.filter(order: LibrarySort.title, reverse: true);
      await mount(tester, LibraryPage(library: library, playback: playback));
      await tester.longPress(find.byKey(ValueKey(tracks['A']!.song.id)));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(ValueKey(tracks['C']!.song.id)));
      library.filter(text: 'B');
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('enqueue-library-selected')));
      expect(names().skip(1), [tracks['C']!.song.name, tracks['A']!.song.name]);
      await tap(
        tester,
        find.byKey(ValueKey('enqueue-library-${tracks['B']!.song.id}')),
      );
      expect(names().last, tracks['B']!.song.name);
      await tap(tester, find.text('退出多选'));
      await tap(
        tester,
        find.byKey(ValueKey('enqueue-library-${tracks['B']!.song.id}')),
      );
      expect(names().last, tracks['B']!.song.name);
      library.filter(text: '');
      await library.updateFilter(order: LibrarySort.title, reverse: true);
      library.searchFilter('A');
      await mount(tester, FilterPage(library: library, playback: playback));
      await tap(tester, find.byKey(const ValueKey('enqueue-filter')));
      expect(names().last, tracks['A']!.song.name);
      final beforeSingle = names().length;
      await tap(
        tester,
        find.byKey(ValueKey('enqueue-filter-${tracks['A']!.song.id}')),
      );
      expect(names(), hasLength(beforeSingle + 1));
      expect(names().last, tracks['A']!.song.name);
      final regular = await library.createPlaylist('Regular', [
        tracks['B']!.song.id,
        tracks['C']!.song.id,
        tracks['A']!.song.id,
      ]);
      final smart = await library.createSmartPlaylist(
        'Smart',
        FilterPreferences(descending: true),
      );
      for (final id in [regular, smart]) {
        await mount(
          tester,
          PlaylistsPage(
            key: ValueKey(id),
            library: library,
            playback: playback,
          ),
        );
        await tap(tester, find.byKey(ValueKey('playlist-$id')));
        final expected = library
            .playlistTracks(id)
            .map((t) => t.song.name)
            .toList();
        final length = names().length;
        await tap(tester, find.byKey(const ValueKey('enqueue-playlist')));
        expect(names().skip(length), expected);
        await tester.enterText(
          find.byKey(ValueKey('playlist-search-$id')),
          'B',
        );
        await tester.pumpAndSettle();
        await tap(
          tester,
          find.byKey(ValueKey('enqueue-playlist-${tracks['B']!.song.id}')),
        );
        expect(names().last, tracks['B']!.song.name);
        if (id == regular) {
          await tester.longPress(
            find.byKey(ValueKey('playlist-song-${tracks['B']!.song.id}')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(ValueKey('playlist-search-$id')),
            'A',
          );
          await tester.pumpAndSettle();
          await tap(
            tester,
            find.byKey(ValueKey('playlist-song-${tracks['A']!.song.id}')),
          );
          final selectedStart = names().length;
          await tap(
            tester,
            find.byKey(const ValueKey('enqueue-playlist-selected')),
          );
          expect(names().skip(selectedStart), [
            tracks['B']!.song.name,
            tracks['A']!.song.name,
          ]);
        }
      }
      expect(playback.queue.current?.entryId, original);
      expect(playback.playing, isTrue);
      expect(player.stops, stops);
      expect(
        playback.queue.priorityIds,
        playback.queue.entries.skip(1).map((e) => e.entryId),
      );
    },
  );

  queueTest(
    'small queue supports duplicate removal and empty result without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await playback.addToQueue([song('A'), song('A')]);
      await mount(tester, QueuePage(playback: playback, library: library));
      final last = playback.queue.entries.last.entryId;
      await tap(tester, find.byKey(ValueKey('queue-remove-$last')));
      expect(playback.queue.entries, hasLength(1));
      await tap(
        tester,
        find.byKey(ValueKey('queue-remove-${playback.queue.current!.entryId}')),
      );
      expect(playback.queue.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
