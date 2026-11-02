import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_page.dart';
import 'package:tag_music/library/filter_rule.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/playlists_page.dart';
import 'package:tag_music/library/tags_page.dart';
import 'package:tag_music/library/smart_playlist_editor.dart';

import 'library_test.dart' show FakeDocuments, entry;
import 'playlists_page_test.dart' show PlaylistPlayback;

void main() {
  late LibraryController library;
  late PlaylistPlayback playback;
  late Map<String, String> tags;
  late Map<String, String> songs;
  setUp(() async {
    final documents = FakeDocuments()
      ..files['root'] = [entry('A'), entry('B'), entry('C')];
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      documents,
    );
    await library.initialize();
    await library.scan();
    await library.createTag('X');
    await library.createTag('Y');
    tags = {for (final t in library.tags) t.name: t.id};
    songs = {for (final t in library.tracks) t.song.identity: t.song.id};
    await library.changeSongTags(tags['X']!, [
      songs['A']!,
      songs['B']!,
    ], add: true);
    await library.changeSongTags(tags['Y']!, [songs['C']!], add: true);
    playback = PlaylistPlayback()..current = null;
  });
  tearDown(() async {
    await library.shutdown();
    playback.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, int box, List<String> names) async {
    await tap(tester, find.byKey(ValueKey('smart-pick-$box')));
    for (final name in names) {
      await tap(tester, find.byKey(ValueKey('smart-tag-${tags[name]}')));
    }
    await tap(tester, find.text('关闭'));
  }

  Widget page() => PlaylistsPage(library: library, playback: playback);

  testWidgets(
    'create/edit independent smart rule, dynamic play snapshot, rename and delete',
    (tester) async {
      await mount(tester, page());
      await tap(tester, find.byKey(const ValueKey('create-smart-playlist')));
      await tester.enterText(
        find.byKey(const ValueKey('smart-name')),
        'Dynamic',
      );
      await choose(tester, 0, ['X']);
      await tap(tester, find.byKey(const ValueKey('smart-sort')));
      await tap(tester, find.text('文件名').last);
      await tap(tester, find.byKey(const ValueKey('smart-direction')));
      expect(find.text('2 首可用歌曲'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      final id = library.playlists.single.id;
      expect(library.filterPreferences.rule.isEmpty, isTrue);
      expect(library.playlists.single.descending, isTrue);
      expect(library.playlists.single.sortOrder, 'name');
      await tap(tester, find.byKey(ValueKey('playlist-$id')));
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(find.byKey(const ValueKey('playlist-add-songs')), findsNothing);
      await tap(tester, find.byKey(ValueKey('playlist-song-${songs['B']}')));
      expect(playback.tracks.map((t) => t.name), ['B.mp3', 'A.mp3']);
      final oldIds = playback.queue.entries.map((e) => e.entryId).toList();
      await library.changeSongTags(tags['X']!, [songs['C']!], add: true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('playlist-song-${songs['C']}')),
        findsOneWidget,
      );
      expect(playback.queue.entries.map((e) => e.entryId), oldIds);
      await tap(tester, find.byTooltip('歌单操作'));
      await tap(tester, find.text('编辑规则'));
      await tap(tester, find.byKey(const ValueKey('smart-clear-0')));
      await choose(tester, 1, ['Y']);
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      expect(
        find.byKey(ValueKey('playlist-song-${songs['C']}')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('playlist-song-${songs['A']}')), findsNothing);
      await tap(tester, find.byTooltip('歌单操作'));
      await tap(tester, find.text('改名'));
      await tester.enterText(
        find.byKey(const ValueKey('playlist-name')),
        'Renamed',
      );
      await tap(tester, find.byKey(const ValueKey('save-playlist-confirm')));
      expect(find.text('Renamed'), findsOneWidget);
      await tap(tester, find.byTooltip('歌单操作'));
      await tap(tester, find.text('删除'));
      await tap(tester, find.text('删除歌单'));
      expect(library.playlists, isEmpty);
      expect(playback.queue.entries.map((e) => e.entryId), oldIds);
    },
  );

  testWidgets(
    'save filter rule ignores query, keeps sorting and leaves current filter independent',
    (tester) async {
      await library.updateFilter(
        rule: FilterRule(allTagIds: [tags['X']!]),
        order: LibrarySort.name,
        reverse: true,
      );
      library.searchFilter('A');
      await mount(tester, FilterPage(library: library, playback: playback));
      await tap(tester, find.byKey(const ValueKey('save-smart-playlist')));
      await tester.enterText(find.byKey(const ValueKey('smart-name')), 'Saved');
      expect(find.text('2 首可用歌曲'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      final id = library.playlists.single.id;
      expect(
        library.smartPreferences(library.playlists.single).sort,
        LibrarySort.name,
      );
      expect(library.playlistTracks(id).map((t) => t.song.identity), [
        'B',
        'A',
      ]);
      await library.updateFilter(rule: FilterRule(anyTagIds: [tags['Y']!]));
      expect(library.playlistTracks(id).map((t) => t.song.identity), [
        'B',
        'A',
      ]);
      expect(library.filterQuery, 'A');
    },
  );

  testWidgets(
    'tag deletion dialog lists current and all affected smart ranges; cancel preserves rules',
    (tester) async {
      final x = tags['X']!;
      await library.updateFilter(rule: FilterRule(allTagIds: [x]));
      await library.createSmartPlaylist(
        'Expand',
        FilterPreferences(rule: FilterRule(allTagIds: [x])),
      );
      await library.createSmartPlaylist(
        'Shrink',
        FilterPreferences(rule: FilterRule(anyTagIds: [x, tags['Y']!])),
      );
      await mount(tester, TagsPage(library: library));
      await tap(tester, find.byTooltip('删除X'));
      expect(find.textContaining('当前筛选：2 → 3 首'), findsOneWidget);
      expect(find.textContaining('智能歌单“Expand”：2 → 3 首'), findsOneWidget);
      expect(find.textContaining('智能歌单“Shrink”：3 → 1 首'), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(library.tags.map((t) => t.id), contains(x));
      await tap(tester, find.byTooltip('删除X'));
      await tap(tester, find.widgetWithText(FilledButton, '删除'));
      expect(library.tags.map((t) => t.id), isNot(contains(x)));
      expect(library.filterPreferences.rule.isEmpty, isTrue);
      expect(
        library.playlists.every(
          (p) => !library.smartPreferences(p).rule.referencedIds.contains(x),
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'small screen keyboard, duplicate name retry, cancel draft and bad-rule display',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await library.createPlaylist('Taken', []);
      await mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => editSmartPlaylist(context, library),
            child: const Text('open'),
          ),
        ),
      );
      await tap(tester, find.text('open'));
      await tester.enterText(find.byKey(const ValueKey('smart-name')), 'taken');
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      final error = find.textContaining('已有同名歌单');
      expect(error, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('smart-name')));
      await tester.enterText(
        find.byKey(const ValueKey('smart-name')),
        'Unique',
      );
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      final id = library.playlists.singleWhere((p) => p.kind == 'smart').id;
      await tap(tester, find.text('open'));
      await choose(tester, 0, ['X']);
      await tap(tester, find.text('取消'));
      expect(library.playlists.length, 2);
      expect(library.filterPreferences.rule.isEmpty, isTrue);
      await library.db.customStatement(
        'UPDATE playlists SET rule_json = ? WHERE id = ?',
        ['bad', id],
      );
      await library.reloadPlaylists();
      tester.view.resetViewInsets();
      await mount(tester, page());
      await tap(tester, find.byKey(ValueKey('playlist-$id')));
      expect(find.textContaining('无法读取智能歌单'), findsOneWidget);
      expect(find.byKey(ValueKey('playlist-song-${songs['A']}')), findsNothing);
      expect(tester.takeException(), isNull);
      await tap(tester, find.byTooltip('歌单操作'));
      await tap(tester, find.text('编辑规则'));
      await tap(tester, find.text('取消'));
      expect(library.playlists.singleWhere((p) => p.id == id).ruleJson, 'bad');
      await tap(tester, find.byTooltip('歌单操作'));
      await tap(tester, find.text('编辑规则'));
      await tap(tester, find.text('重建规则'));
      await choose(tester, 1, ['Y']);
      await tap(tester, find.byKey(const ValueKey('save-smart-confirm')));
      expect(library.playlistTracks(id).map((t) => t.song.identity), ['C']);
      expect(find.textContaining('无法读取智能歌单'), findsNothing);
    },
  );
}
