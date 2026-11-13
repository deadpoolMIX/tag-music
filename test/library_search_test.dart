import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_search_page.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_page_test.dart' as library_page_test show SnapshotController;
import 'library_test.dart' show FakeDocuments;
import 'support/r6_tracks.dart';

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
