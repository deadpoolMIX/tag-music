import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/tags_page.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

import 'library_page_test.dart' as helper show SnapshotController;
import 'library_test.dart' show FakeDocuments, entry;

void main() {
  testWidgets('create, rename and confirmed deletion work on tags page', (
    tester,
  ) async {
    final library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      FakeDocuments(),
    );
    await tester.runAsync(library.initialize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TagsPage(library: library)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('create-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' Rock ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Rock'), findsOneWidget);
    await tester.tap(find.byTooltip('修改Rock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Jazz');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('Jazz'), findsOneWidget);
    await tester.tap(find.byTooltip('删除Jazz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 首歌曲'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(library.tags.length, 1);
    await tester.tap(find.byTooltip('删除Jazz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(library.tags, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(library.shutdown);
  });

  testWidgets('select across searches and add tags without changing playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final access = FakeDocuments()..files['root'] = [entry('甲'), entry('乙')];
    final library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      access,
    );
    final playback = helper.SnapshotController()..current = null;
    await tester.runAsync(() async {
      await library.initialize();
      await library.scan();
      await library.createTag('收藏');
    });
    await playback.playSongs(
      library.tracks.map((track) => track.queueSong).toList(),
      0,
    );
    final originalQueue = playback.tracks;
    final originalCurrent = playback.current;
    final ids = {
      for (final track in library.tracks) track.song.identity: track.song.id,
    };
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
    await tester.tap(find.byKey(const ValueKey('select-songs')));
    await tester.pumpAndSettle();
    library.filter(text: '甲');
    await tester.pumpAndSettle();
    expect(library.visible.length, 1);
    expect(ids['甲'], isNotNull);
    expect(find.text('歌曲 甲.mp3'), findsWidgets);
    await tester.tap(find.byKey(ValueKey<String>(ids['甲']!)));
    library.filter(text: '乙');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(ids['乙']!)));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('batch-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加收藏'));
    await tester.pumpAndSettle();
    expect(library.countForTag(library.tags.single.id), 2);
    expect(playback.current, same(originalCurrent));
    expect(playback.tracks, same(originalQueue));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TagsPage(library: library)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 首歌曲'), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('歌曲 甲.mp3'), findsOneWidget);
    expect(find.text('歌曲 乙.mp3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(library.shutdown);
    playback.dispose();
  });
}
