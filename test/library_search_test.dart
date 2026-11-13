import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_search_page.dart';
import 'package:tag_music/library/song_list.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_page_test.dart' as library_page_test show SnapshotController;
import 'library_test.dart' show FakeDocuments;
import 'support/r6_tracks.dart';

class _SearchPlaybackController extends library_page_test.SnapshotController {
  final playCalls = <List<String>>[];
  final playTargets = <int>[];
  final enqueueCalls = <List<String>>[];

  @override
  Future<void> playSongs(List<QueueSong> snapshot, int target) async {
    playCalls.add(List.unmodifiable(snapshot.map((song) => song.songId)));
    playTargets.add(target);
    queue.replace(snapshot, target);
    await super.playSongs(snapshot, target);
  }

  @override
  Future<void> addToQueue(List<QueueSong> songs) async {
    enqueueCalls.add(List.unmodifiable(songs.map((song) => song.songId)));
    queue.add(songs);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryController library;
  setUp(() {
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      FakeDocuments(),
    );
    library.tracks = [
      r6Track('a', title: 'Needle title', modified: 10),
      r6Track('b', artist: 'NEEDLE singer', modified: 20),
      r6Track('c', album: 'needle album', available: false, modified: 30),
      r6Track('d', name: 'Needle file.mp3', modified: null),
    ];
  });
  tearDown(() => library.shutdown());

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'search empty state and missing-row actions preserve playback and source filters on ${platform.name}',
      (tester) async {
        final playback = _SearchPlaybackController();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          playback.dispose();
          tester.view.resetViewInsets();
        });
        final initial = library.tracks.singleWhere((t) => t.song.id == 'a');
        playback.queue.replace([initial.queueSong], 0);
        playback.current = initial.probe;
        playback.selectedSongId = initial.song.id;
        playback.tracks = List.unmodifiable([initial.probe]);
        final initialCurrent = playback.current;
        final initialTracks = playback.tracks;
        final initialEntries = playback.queue.entries.toList();
        final initialQueueCurrent = playback.queue.current;
        final initialPriority = playback.queue.priorityIds.toList();
        final initialMode = playback.queue.mode;
        library.filter(
          text: 'source',
          missing: false,
          order: LibrarySort.artist,
          reverse: false,
        );
        library.searchFilter('kept');
        final preferences = library.filterPreferences;

        void expectSourceUnchanged() {
          expect(library.query, 'source');
          expect(library.showMissing, isFalse);
          expect(library.sort, LibrarySort.artist);
          expect(library.descending, isFalse);
          expect(library.filterQuery, 'kept');
          expect(library.filterPreferences, same(preferences));
        }

        void expectPlaybackUnchanged() {
          expect(playback.playCalls, isEmpty);
          expect(playback.playTargets, isEmpty);
          expect(playback.enqueueCalls, isEmpty);
          expect(playback.current, same(initialCurrent));
          expect(playback.currentSongId, 'a');
          expect(playback.tracks, same(initialTracks));
          expect(playback.queue.entries, orderedEquals(initialEntries));
          expect(playback.queue.current, same(initialQueueCurrent));
          expect(playback.queue.priorityIds, initialPriority);
          expect(playback.queue.mode, initialMode);
        }

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              libraryProvider.overrideWithValue(library),
              playbackProvider.overrideWithValue(playback),
            ],
            child: MaterialApp(
              home: LibrarySearchPage(library: library, playback: playback),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SongRow), findsNWidgets(4));
        await tester.enterText(
          find.byKey(const ValueKey('library-search')),
          'absent',
        );
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的歌曲'), findsOneWidget);
        expect(find.byType(SongRow), findsNothing);
        expectPlaybackUnchanged();
        expectSourceUnchanged();

        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的歌曲'), findsNothing);
        expect(find.byType(SongRow), findsNWidgets(4));
        for (final id in ['a', 'b', 'c', 'd']) {
          expect(find.byKey(ValueKey(id)), findsOneWidget);
        }
        expectPlaybackUnchanged();
        expectSourceUnchanged();

        await tester.enterText(
          find.byKey(const ValueKey('library-search')),
          'needle album',
        );
        await tester.pumpAndSettle();
        final missing = find.byKey(const ValueKey('c'));
        expect(find.byType(SongRow), findsOneWidget);
        expect(missing, findsOneWidget);
        expect(find.byTooltip('文件失联 · 记录仍保留'), findsOneWidget);
        // Missing songs remain selectable in multi-select mode; this assertion
        // specifically exercises the normal playback mode.
        expect(find.text('退出多选'), findsNothing);
        expect(tester.widget<SongRow>(missing).selecting, isFalse);
        final missingAdd = find.byKey(const ValueKey('enqueue-search-c'));
        expect(missingAdd, findsOneWidget);
        final missingInk = find.ancestor(
          of: missingAdd,
          matching: find.byType(InkWell),
        );
        expect(missingInk, findsOneWidget);
        expect(tester.widget<InkWell>(missingInk).onTap, isNull);
        expect(tester.widget<IconButton>(missingAdd).onPressed, isNull);
        await tester.tap(missing);
        await tester.pumpAndSettle();
        expectPlaybackUnchanged();
        await tester.tap(missingAdd);
        await tester.pumpAndSettle();
        expectPlaybackUnchanged();
        expectSourceUnchanged();

        await tester.enterText(
          find.byKey(const ValueKey('library-search')),
          'singer',
        );
        await tester.pumpAndSettle();
        final available = find.byKey(const ValueKey('b'));
        expect(find.byType(SongRow), findsOneWidget);
        expect(available, findsOneWidget);
        expect(tester.widget<SongRow>(available).selecting, isFalse);
        final availableAdd = find.byKey(const ValueKey('enqueue-search-b'));
        expect(tester.widget<IconButton>(availableAdd).onPressed, isNotNull);
        await tester.tap(availableAdd);
        await tester.pumpAndSettle();
        expect(playback.enqueueCalls, [
          ['b'],
        ]);
        expect(playback.playCalls, isEmpty);
        expect(playback.current, same(initialCurrent));
        expect(playback.currentSongId, 'a');
        expect(playback.tracks, same(initialTracks));
        expect(playback.queue.entries.map((e) => e.song.songId), ['a', 'b']);
        expect(playback.queue.current, same(initialQueueCurrent));
        expectSourceUnchanged();

        await tester.tap(available);
        await tester.pumpAndSettle();
        expect(playback.playCalls, [
          ['b'],
        ]);
        expect(playback.playTargets, [0]);
        expect(playback.enqueueCalls, [
          ['b'],
        ]);
        expect(playback.currentSongId, 'b');
        expect(playback.current?.location, '/synthetic/b');
        expect(playback.tracks.map((track) => track.location), [
          '/synthetic/b',
        ]);
        expect(playback.queue.entries.map((e) => e.song.songId), ['b']);
        expect(playback.queue.current?.song.songId, 'b');
        expect(find.byType(SongRow), findsOneWidget);
        expect(find.byKey(const ValueKey('b')), findsOneWidget);
        expectSourceUnchanged();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  test('full-library search matches four fields, includes missing, caches immutable snapshots and mutates no page state', () {
    library.filter(
      text: 'source',
      missing: false,
      order: LibrarySort.name,
      reverse: false,
    );
    library.searchFilter('kept');
    final preferences = library.filterPreferences;
    final result = library.searchTracks('  nEeDlE  ');
    expect(result.map((t) => t.song.id), ['c', 'b', 'a', 'd']);
    expect(result.first.available, isFalse);
    expect(library.searchTracks('needle'), same(result));
    expect(() => result.clear(), throwsUnsupportedError);
    expect(library.searchTracks('absent'), isEmpty);
    expect(library.searchTracks('  '), hasLength(4));
    expect(library.query, 'source');
    expect(library.showMissing, isFalse);
    expect(library.sort, LibrarySort.name);
    expect(library.descending, isFalse);
    expect(library.filterQuery, 'kept');
    expect(library.filterPreferences, same(preferences));
    library.tracks = [r6Track('new', title: 'Needle new')];
    expect(library.searchTracks('needle').single.song.id, 'new');
    expect(
      result,
      hasLength(4),
      reason: 'existing playback/source snapshot stays fixed',
    );
  });

  testWidgets(
    'real IME, clear, keyboard inset and data refresh stay independent of source filters',
    (tester) async {
      final playback = library_page_test.SnapshotController()..current = null;
      library.filter(text: 'source', order: LibrarySort.artist, missing: false);
      library.searchFilter('kept');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWithValue(library),
            playbackProvider.overrideWithValue(playback),
          ],
          child: MaterialApp(
            home: LibrarySearchPage(library: library, playback: playback),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-search')));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('singer');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('b')), findsOneWidget);
      expect(find.byKey(const ValueKey('a')), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('title');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('a')));
      await tester.pumpAndSettle();
      expect(playback.selectedSongId, 'a');
      expect(playback.tracks, hasLength(1));
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(playback.tracks, hasLength(1));
      library.tracks = [...library.tracks, r6Track('new', modified: 40)];
      library.filter(text: 'source');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new')), findsOneWidget);
      expect(library.query, 'source');
      expect(library.showMissing, isFalse);
      expect(library.sort, LibrarySort.artist);
      expect(library.filterQuery, 'kept');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
    },
  );
}
