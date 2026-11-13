import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/song_list.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

import 'audio_handler_test.dart' show HandlerController;
import 'library_test.dart' show FakeDocuments, entry;

class CoverDocuments extends DocumentAccess {
  CoverDocuments() : super(android: false);
  @override
  Future<Uint8List?> cover(ProbeTrack track) async => null;
}

class SnapshotController extends HandlerController {
  String? selectedSongId;
  @override
  String? get currentSongId => selectedSongId;
  @override
  DocumentAccess get documents => _documents;
  final _documents = CoverDocuments();
  @override
  String? get metadataWarning => null;
  @override
  int get index => 0;
  @override
  Future<void> playSongs(List<QueueSong> snapshot, int target) async {
    tracks = List.unmodifiable(snapshot.map((song) => song.track));
    current = tracks[target];
    selectedSongId = snapshot[target].songId;
    notifyListeners();
  }
}

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

void main() {
  for (final currentState in ['none', 'filtered', 'outside-source']) {
    testWidgets(
      'home disabled locate preserves query, descending sort, selection and route: $currentState',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final access = FakeDocuments()
          ..files['a'] = [
            for (var i = 0; i < 24; i++)
              entry('keep-${i.toString().padLeft(2, '0')}'),
            entry('excluded'),
          ];
        final library = LibraryController(
          LibraryDatabase(NativeDatabase.memory()),
          access,
        );
        final playback = SnapshotController()..current = null;
        final observer = _RouteObserver();
        try {
          await tester.runAsync(() async {
            await library.initialize();
            await library.scan();
          });
          library.filter(
            text: 'keep-',
            order: LibrarySort.title,
            reverse: true,
          );
          final excluded = library.tracks.singleWhere(
            (track) => track.song.identity == 'excluded',
          );
          if (currentState == 'filtered') {
            playback
              ..selectedSongId = excluded.song.id
              ..current = excluded.probe;
          } else if (currentState == 'outside-source') {
            playback
              ..selectedSongId = 'outside-library-uuid'
              ..current = const ProbeTrack(
                location: 'test://outside-library',
                name: 'outside.mp3',
              );
          }
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                libraryProvider.overrideWithValue(library),
                playbackProvider.overrideWithValue(playback),
              ],
              child: MaterialApp(
                navigatorObservers: [observer],
                home: const Scaffold(body: PlaybackPage()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final listFinder = find.descendant(
            of: find.byType(SongList),
            matching: find.byType(ListView),
          );
          await tester.drag(listFinder, const Offset(0, -300));
          await tester.pumpAndSettle();
          final selectedRow = tester.widget<SongRow>(
            find.byType(SongRow).hitTestable().first,
          );
          final selectedId = selectedRow.track.song.id;
          await tester.longPress(find.byKey(ValueKey(selectedId)));
          await tester.pumpAndSettle();
          expect(find.text('已选 1 首'), findsOneWidget);

          SongList songList() => tester.widget<SongList>(find.byType(SongList));
          List<String> selectedIds() => tester
              .widgetList<SongRow>(find.byType(SongRow))
              .where((row) => row.selected)
              .map((row) => row.track.song.id)
              .toList();
          final expectedIds = [
            for (var i = 23; i >= 0; i--)
              library.tracks
                  .singleWhere(
                    (track) =>
                        track.song.identity ==
                        'keep-${i.toString().padLeft(2, '0')}',
                  )
                  .song
                  .id,
          ];
          expect(songList().rows.map((row) => row.song.id), expectedIds);
          expect(selectedIds(), [selectedId]);
          final sourceIds = songList().source
              .map((row) => row.song.id)
              .toList();
          expect(sourceIds, contains(excluded.song.id));
          expect(expectedIds, isNot(contains(excluded.song.id)));
          expect(sourceIds, isNot(contains('outside-library-uuid')));
          final scroll = tester.widget<ListView>(listFinder).controller!;
          final offset = scroll.offset;
          expect(offset, greaterThan(0));
          final currentId = playback.currentSongId;
          final current = playback.current;
          final route = ModalRoute.of(tester.element(find.byType(SongList)))!;
          final pushes = observer.pushes;
          final pops = observer.pops;
          final locate = find.byKey(const ValueKey('locate-current-song'));
          expect(tester.widget<IconButton>(locate).onPressed, isNull);
          // The real homepage installs no observer callback. Its public widget
          // property is observable; a callback invocation count is not injected.
          expect(songList().onLocated, isNull);
          await tester.tap(locate);
          await tester.pumpAndSettle();

          expect(tester.widget<IconButton>(locate).onPressed, isNull);
          expect(library.query, 'keep-');
          expect(library.sort, LibrarySort.title);
          expect(library.descending, isTrue);
          expect(library.visible.map((row) => row.song.id), expectedIds);
          expect(songList().rows.map((row) => row.song.id), expectedIds);
          expect(songList().source.map((row) => row.song.id), sourceIds);
          expect(selectedIds(), [selectedId]);
          expect(find.text('已选 1 首'), findsOneWidget);
          expect(scroll.offset, offset);
          expect(playback.currentSongId, currentId);
          expect(playback.current, same(current));
          expect(
            tester
                .widgetList<SongRow>(find.byType(SongRow))
                .any((row) => row.highlighted),
            isFalse,
          );
          expect(
            ModalRoute.of(tester.element(find.byType(SongList))),
            same(route),
          );
          expect(route.isCurrent, isTrue);
          expect(observer.pushes, pushes);
          expect(observer.pops, pops);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          playback.dispose();
          await tester.runAsync(library.shutdown);
        }
      },
    );
  }

  testWidgets(
    'small-screen library can search while playback snapshot stays unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = FakeDocuments()..files['a'] = [entry('甲'), entry('乙')];
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        access,
      );
      final playback = SnapshotController()..current = null;
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan();
      });
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
      await tester.tap(find.byKey(const ValueKey('open-library-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-search')));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      // Exercise the connection created by a real tap, not tester.enterText's
      // helper which can repair a missing connection before injecting text.
      tester.testTextInput.enterText('甲');
      await tester.pumpAndSettle();
      expect(library.searchTracks('甲').length, 1);
      expect(library.query, isEmpty);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('歌曲 甲.mp3'));
      await tester.pumpAndSettle();
      expect(playback.tracks.length, 2);
      await tester.enterText(find.byKey(const ValueKey('library-search')), '乙');
      await tester.pumpAndSettle();
      expect(find.text('歌曲 甲.mp3'), findsNothing);
      expect(playback.current?.name, '甲.mp3');
      expect(playback.tracks.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(library.shutdown);
      playback.dispose();
    },
  );
}
