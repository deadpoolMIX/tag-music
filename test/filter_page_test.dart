import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/tags_page.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

import 'library_page_test.dart' as playback_test show SnapshotController;
import 'library_test.dart' show FakeDocuments, entry;

void main() {
  late LibraryController library;
  late playback_test.SnapshotController playback;
  late Map<String, String> tags;
  late Map<String, String> songs;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final access = FakeDocuments()
        ..files['root'] = [
          for (final name in ['甲', '乙', '丙', '丁']) entry(name),
        ];
      library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        access,
      );
      await library.initialize();
      await library.scan();
      for (final name in ['A', 'B', 'C', 'E']) {
        await library.createTag(name);
      }
      tags = {for (final tag in library.tags) tag.name: tag.id};
      songs = {
        for (final track in library.tracks) track.song.name: track.song.id,
      };
      await library.changeSongTags(tags['A']!, [
        songs['甲.mp3']!,
        songs['丙.mp3']!,
      ], add: true);
      await library.changeSongTags(tags['B']!, [songs['甲.mp3']!], add: true);
      await library.changeSongTags(tags['C']!, [songs['乙.mp3']!], add: true);
      await library.changeSongTags(tags['E']!, [songs['丙.mp3']!], add: true);
    });
    playback = playback_test.SnapshotController()..current = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWithValue(library),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: PlaybackPage(filtering: true)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    for (var i = 0; library.filterSaving && i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(library.filterSaving, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(library.shutdown);
    playback.dispose();
  }

  Future<void> pick(WidgetTester tester, int box, List<String> names) async {
    final picker = find.byKey(ValueKey('filter-pick-$box'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    for (final name in names) {
      await tester.tap(find.byKey(ValueKey('filter-tag-${tags[name]}')));
    }
    // Multiple choices before a new frame must accumulate, not overwrite.
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'three boxes edit immediately; tag search, clearing and result search are independent',
    (tester) async {
      await open(tester);
      await pick(tester, 0, ['A', 'B']);
      expect(library.filtered.map((t) => t.song.name), ['甲.mp3']);
      await pick(tester, 1, ['C']);
      expect(library.filtered.map((t) => t.song.name).toSet(), {
        '甲.mp3',
        '乙.mp3',
      });
      await pick(tester, 2, ['B']);
      expect(library.filtered.map((t) => t.song.name), ['乙.mp3']);
      final field = find.byKey(const ValueKey('filter-search'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('甲');
      await tester.pumpAndSettle();
      expect(library.filtered, isEmpty);
      expect(library.filterMatches.length, 1);
      expect(library.query, isEmpty);
      expect(library.visible.length, 4);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('filter-clear-2'));
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(library.filtered.length, 2);
      final clearAll = find.byKey(const ValueKey('clear-filter'));
      await tester.ensureVisible(clearAll);
      await tester.pumpAndSettle();
      await tester.tap(clearAll);
      await tester.pumpAndSettle();
      expect(library.filtered.length, 4);
      await tester.tap(find.byKey(const ValueKey('filter-pick-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('filter-tag-search')),
        'c',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('filter-tag-${tags['C']}')), findsOneWidget);
      expect(find.byKey(ValueKey('filter-tag-${tags['A']}')), findsNothing);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'result playback keeps exact queue and current item after rule and tag changes',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () => library.updateFilter(
          rule: FilterRule(
            allTagIds: [tags['A']!],
            anyTagIds: [tags['C']!],
            excludedTagIds: [tags['E']!],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final expected = library.filtered.map((t) => t.probe.location).toList();
      final target = find.byKey(ValueKey('filter-song-${songs['乙.mp3']}'));
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(playback.tracks.map((t) => t.location).toList(), expected);
      final current = playback.current;
      await tester.runAsync(
        () => library.updateFilter(
          rule: FilterRule(excludedTagIds: [tags['C']!]),
        ),
      );
      await tester.runAsync(() => library.deleteTag(tags['C']!));
      await tester.pumpAndSettle();
      expect(library.filtered.length, 4);
      expect(playback.tracks.map((t) => t.location).toList(), expected);
      expect(playback.current, same(current));
      await tester.runAsync(
        () => library.updateFilter(
          rule: FilterRule(
            allTagIds: [tags['A']!],
            excludedTagIds: [tags['A']!],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(library.filtered, isEmpty);
      expect(playback.current, same(current));
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  for (final configuration in [
    (const Size(320, 568), 2.0),
    (const Size(1280, 800), 1.0),
  ]) {
    testWidgets(
      'filter controls and picker usable at ${configuration.$1} scale ${configuration.$2}',
      (tester) async {
        await open(tester, size: configuration.$1, scale: configuration.$2);
        await pick(tester, 2, ['A']);
        expect(library.filtered.length, 2);
        final clear = find.byKey(const ValueKey('filter-clear-2'));
        await tester.ensureVisible(clear);
        await tester.pumpAndSettle();
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(library.filtered.length, 4);
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }

  testWidgets(
    'tag deletion confirms affected filter boxes and cancel preserves the rule',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () => library.updateFilter(
          rule: FilterRule(
            allTagIds: [tags['A']!],
            excludedTagIds: [tags['A']!],
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TagsPage(library: library)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除A'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全部具备、排除标签'), findsOneWidget);
      expect(find.textContaining('全部可用歌曲'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(library.filterPreferences.rule.referencedIds, {tags['A']});
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
