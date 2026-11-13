import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/core/settings.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_search_page.dart';
import 'package:tag_music/library/song_list.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_page_test.dart' as library_page_test show SnapshotController;
import 'library_test.dart' show FakeDocuments;
import 'settings_test.dart' show MemorySettings;
import 'support/r6_tracks.dart';

const _a = '10000000-0000-4000-8000-000000000001';
const _b = '10000000-0000-4000-8000-000000000002';
const _c = '10000000-0000-4000-8000-000000000003';
const _d = '10000000-0000-4000-8000-000000000004';
const _e = '10000000-0000-4000-8000-000000000005';
const _f = '10000000-0000-4000-8000-000000000006';

// Deliberately scrambled input. Each sort has a distinct, handwritten oracle.
// At time 20, filename A precedes tie; the equal tie filenames use UUID order.
List<LibraryTrack> _sortFixture() => [
  r6Track(
    _f,
    title: 'Charlie',
    artist: 'Hotel',
    modified: null,
    name: 'unknown-a.mp3',
  ),
  r6Track(_c, title: 'Delta', artist: 'Mike', modified: 20, name: 'A.mp3'),
  r6Track(_b, title: 'Bravo', artist: 'Alpha', modified: 20, name: 'tie.mp3'),
  r6Track(
    _e,
    title: 'Foxtrot',
    artist: 'Bravo',
    modified: null,
    name: 'unknown-b.mp3',
  ),
  r6Track(_d, title: 'Alpha', artist: 'Echo', modified: 10, name: 'd.mp3'),
  r6Track(_a, title: 'Echo', artist: 'Zulu', modified: 20, name: 'tie.mp3'),
];

const _cases = [
  (LibrarySort.title, '歌名', false, [_d, _b, _f, _c, _a, _e]),
  (LibrarySort.title, '歌名', true, [_e, _a, _c, _f, _b, _d]),
  (LibrarySort.artist, '歌手', false, [_b, _e, _d, _f, _c, _a]),
  (LibrarySort.artist, '歌手', true, [_a, _c, _f, _d, _e, _b]),
  (LibrarySort.modified, '修改时间', false, [_d, _c, _a, _b, _f, _e]),
  (LibrarySort.modified, '修改时间', true, [_c, _a, _b, _d, _f, _e]),
];

Finder _homeList() => find.byWidgetPredicate(
  (widget) => widget is SongList && widget.scope == 'library',
  skipOffstage: false,
);

Finder _withinHome(Finder matching) =>
    find.descendant(of: _homeList(), matching: matching, skipOffstage: false);

List<String> _ids(Iterable<LibraryTrack> tracks) =>
    tracks.map((track) => track.song.id).toList();

Future<void> _pumpHome(
  WidgetTester tester,
  TargetPlatform platform,
  LibraryController library,
  library_page_test.SnapshotController playback,
) async {
  tester.view.physicalSize = platform == TargetPlatform.android
      ? const Size(390, 844)
      : const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(MemorySettings()),
        libraryProvider.overrideWithValue(library),
        playbackProvider.overrideWithValue(playback),
      ],
      child: const TagMusicApp(),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AppShell), findsOneWidget);
  expect(_homeList().hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Finder _sheetOption(String label) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.widgetWithText(ListTile, label),
);

Finder _sheetDirection(bool descending) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.widgetWithText(ChoiceChip, descending ? '降序' : '升序'),
);

Future<void> _openSort(WidgetTester tester) async {
  await tester.tap(find.byTooltip('歌曲排序'));
  await tester.pumpAndSettle();
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  expect(
    find.descendant(of: sheet, matching: find.text('歌曲排序')),
    findsOneWidget,
  );
  final rect = tester.getRect(sheet);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.height, closeTo(screen.height * .5, 1));
  expect(rect.bottom, closeTo(screen.height, 1));
  final tiles = tester.widgetList<ListTile>(
    find.descendant(of: sheet, matching: find.byType(ListTile)),
  );
  expect(tiles.map((tile) => (tile.title! as Text).data), ['歌名', '歌手', '修改时间']);
  final chips = tester.widgetList<ChoiceChip>(
    find.descendant(of: sheet, matching: find.byType(ChoiceChip)),
  );
  expect(chips.map((chip) => (chip.label as Text).data), ['升序', '降序']);
  for (final absent in ['专辑', '文件名', 'album', 'name']) {
    expect(
      find.descendant(of: sheet, matching: find.text(absent)),
      findsNothing,
    );
  }
  expect(tester.takeException(), isNull);
}

void _expectSortFeedback(
  WidgetTester tester,
  LibraryController library,
  LibrarySort order,
  String label,
  bool descending,
) {
  expect(library.sort, order);
  expect(library.descending, descending);
  for (final option in ['歌名', '歌手', '修改时间']) {
    final tile = tester.widget<ListTile>(_sheetOption(option));
    expect(tile.selected, option == label, reason: option);
    if (option == label) {
      expect((tile.trailing! as Icon).icon, Icons.check);
    } else {
      expect(tile.trailing, isNull);
    }
  }
  expect(
    tester.widget<ChoiceChip>(_sheetDirection(false)).selected,
    !descending,
  );
  expect(tester.widget<ChoiceChip>(_sheetDirection(true)).selected, descending);
}

Future<void> _closeSort(WidgetTester tester) async {
  final context = tester.element(find.byType(BottomSheet));
  Navigator.of(context).pop();
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsNothing);
}

String _scrollId(int index) =>
    '20000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
const _outsideId = '30000000-0000-4000-8000-000000000000';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tag Music',
      packageName: 'app.tagmusic.player',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform homepage sort sheet exposes three sorts and both directions with UUID order and retained choices',
      (tester) async {
        final library = LibraryController(
          LibraryDatabase(NativeDatabase.memory()),
          FakeDocuments(),
        )..tracks = _sortFixture();
        final playback = library_page_test.SnapshotController()
          ..current = null
          ..notificationsEnabled = true;
        try {
          await _pumpHome(tester, platform, library, playback);
          expect(library.sort, LibrarySort.modified);
          expect(library.descending, isTrue);
          expect(_ids(tester.widget<SongList>(_homeList()).rows), [
            _c,
            _a,
            _b,
            _d,
            _f,
            _e,
          ]);
          await _openSort(tester);
          _expectSortFeedback(
            tester,
            library,
            LibrarySort.modified,
            '修改时间',
            true,
          );

          for (final (order, label, descending, expected) in _cases) {
            final previousDirection = library.descending;
            await tester.tap(_sheetOption(label));
            await tester.pumpAndSettle();
            _expectSortFeedback(
              tester,
              library,
              order,
              label,
              previousDirection,
            );
            await tester.tap(_sheetDirection(descending));
            await tester.pumpAndSettle();
            _expectSortFeedback(tester, library, order, label, descending);
            expect(_ids(library.visible), expected);
            final currentHome = tester.widget<SongList>(_homeList());
            expect(_ids(currentHome.rows), expected);
            expect(_ids(currentHome.source), expected);
            expect(tester.takeException(), isNull);
          }

          // Retention is checked with a non-default choice, not the initial sort.
          await tester.tap(_sheetOption('歌手'));
          await tester.pumpAndSettle();
          await tester.tap(_sheetDirection(true));
          await tester.pumpAndSettle();
          await _closeSort(tester);
          await _openSort(tester);
          _expectSortFeedback(tester, library, LibrarySort.artist, '歌手', true);
          expect(_ids(tester.widget<SongList>(_homeList()).rows), [
            _a,
            _c,
            _f,
            _d,
            _e,
            _b,
          ]);
          await _closeSort(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          playback.dispose();
          await tester.runAsync(library.shutdown);
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );

    testWidgets(
      '$platform independent search push, type, clear and pop preserve mounted artist-descending source state',
      (tester) async {
        final library =
            LibraryController(
                LibraryDatabase(NativeDatabase.memory()),
                FakeDocuments(),
              )
              ..tracks = [
                for (var i = 39; i >= 0; i--)
                  r6Track(
                    _scrollId(i),
                    title: 'Keep ${i.toString().padLeft(2, '0')}',
                    artist: 'Artist ${(39 - i).toString().padLeft(2, '0')}',
                    modified: i,
                  ),
                r6Track(
                  _outsideId,
                  title: 'Outside',
                  artist: 'Artist 99',
                  modified: 999,
                ),
              ];
        library.filter(text: 'keep');
        final playback = library_page_test.SnapshotController()
          ..current = null
          ..notificationsEnabled = true;
        try {
          await _pumpHome(tester, platform, library, playback);
          await _openSort(tester);
          await tester.tap(_sheetOption('歌手'));
          await tester.pumpAndSettle();
          await tester.tap(_sheetDirection(true));
          await tester.pumpAndSettle();
          _expectSortFeedback(tester, library, LibrarySort.artist, '歌手', true);
          await _closeSort(tester);
          final listFinder = _withinHome(
            find.byType(ListView, skipOffstage: false),
          );
          await tester.drag(listFinder, const Offset(0, -600));
          await tester.pumpAndSettle();
          final selectedRow = _withinHome(
            find.byType(SongRow, skipOffstage: false),
          ).hitTestable().first;
          final selectedId = tester.widget<SongRow>(selectedRow).track.song.id;
          await tester.longPress(selectedRow);
          await tester.pumpAndSettle();

          // Artist descending is UUID 0..39 here, while modified descending is
          // UUID 39..0. Neither oracle calls the production sorting function.
          final expectedRows = [for (var i = 0; i < 40; i++) _scrollId(i)];
          final expectedSource = [_outsideId, ...expectedRows];
          final homeState = tester.state(_homeList());
          final homeRoute = ModalRoute.of(tester.element(_homeList()))!;
          final offset = tester.widget<ListView>(listFinder).controller!.offset;
          expect(offset, greaterThan(0));

          void expectHomePreserved() {
            // Re-read the widget/controller now mounted behind the search
            // route; retaining only an old widget snapshot would miss resets.
            final currentHome = tester.widget<SongList>(_homeList());
            expect(tester.state(_homeList()), same(homeState));
            expect(library.query, 'keep');
            expect(library.sort, LibrarySort.artist);
            expect(library.descending, isTrue);
            expect(_ids(currentHome.rows), expectedRows);
            expect(_ids(currentHome.source), expectedSource);
            expect(_ids(library.visible), expectedRows);
            final selected = tester
                .widgetList<SongRow>(
                  _withinHome(find.byType(SongRow, skipOffstage: false)),
                )
                .where((row) => row.selected)
                .map((row) => row.track.song.id);
            expect(selected, [selectedId]);
            expect(
              _withinHome(find.text('已选 1 首', skipOffstage: false)),
              findsOneWidget,
            );
            final currentScroll = tester
                .widget<ListView>(listFinder)
                .controller!;
            expect(currentScroll.offset, offset);
            expect(ModalRoute.of(tester.element(_homeList())), same(homeRoute));
            expect(playback.selectedSongId, isNull);
            expect(tester.takeException(), isNull);
          }

          expectHomePreserved();
          await tester.tap(find.byKey(const ValueKey('open-library-search')));
          await tester.pumpAndSettle();
          expect(find.byType(LibrarySearchPage), findsOneWidget);
          expect(homeRoute.isCurrent, isFalse);
          expectHomePreserved();
          final searchField = find.byKey(const ValueKey('library-search'));
          await tester.tap(searchField);
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          tester.testTextInput.enterText('outside');
          await tester.pumpAndSettle();
          final searchList = find.byWidgetPredicate(
            (widget) => widget is SongList && widget.scope == 'search',
          );
          expect(_ids(tester.widget<SongList>(searchList).rows), [_outsideId]);
          expectHomePreserved();
          await tester.tap(find.byTooltip('清空搜索'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(searchField).controller!.text,
            isEmpty,
          );
          expect(_ids(tester.widget<SongList>(searchList).rows), [
            _outsideId,
            for (var i = 39; i >= 0; i--) _scrollId(i),
          ]);
          expectHomePreserved();
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byType(LibrarySearchPage), findsNothing);
          expect(homeRoute.isCurrent, isTrue);
          expectHomePreserved();
        } finally {
          await tester.pumpWidget(const SizedBox());
          playback.dispose();
          await tester.runAsync(library.shutdown);
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
