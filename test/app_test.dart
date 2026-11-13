import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/core/settings.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/song_list.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'settings_test.dart' show MemorySettings;
import 'library_test.dart' show FakeDocuments, entry;
import 'playlists_page_test.dart' show PlaylistPlayback;

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
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> navigate(WidgetTester tester, String label) async {
    if (find.byKey(const ValueKey('open-navigation')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('open-navigation')));
      await tester.pumpAndSettle();
    }
    final drawer = find.byType(Drawer);
    final destination = drawer.evaluate().isNotEmpty
        ? find.descendant(of: drawer, matching: find.text(label))
        : find.text(label).first;
    await tester.ensureVisible(destination);
    await tester.pumpAndSettle();
    expect(destination.hitTestable(), findsOneWidget);
    await tester.tap(destination);
    await tester.pumpAndSettle();
    final navigationStack = find.byWidgetPredicate(
      (widget) =>
          widget is IndexedStack &&
          widget.children.any(
            (child) => child.key == const ValueKey(AppDestination.songs),
          ),
    );
    expect(navigationStack, findsOneWidget);
    expect(
      tester.widget<IndexedStack>(navigationStack).index,
      ['歌曲', '筛选', '歌单', '专辑', '歌手', '标签', '设置'].indexOf(label),
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final screen in [const Size(390, 844), const Size(1280, 800)]) {
      testWidgets(
        '$platform $screen keeps seven destinations and fixed minibar, settings theme and diagnostics',
        (tester) async {
          await size(tester, screen);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                settingsStoreProvider.overrideWithValue(MemorySettings()),
              ],
              child: const TagMusicApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NavigationBar), findsNothing);
          final before = tester.getRect(
            find.byKey(const ValueKey('global-minibar')),
          );
          if (platform == TargetPlatform.android) {
            await tester.tap(find.byKey(const ValueKey('open-navigation')));
            await tester.pumpAndSettle();
            expect(
              tester.getSize(find.byType(Drawer)).width,
              closeTo(screen.width * .52, .1),
            );
            expect(
              tester.getRect(find.byKey(const ValueKey('global-minibar'))),
              before,
            );
          }
          final labels = ['歌曲', '筛选', '歌单', '专辑', '歌手', '标签', '设置'];
          if (platform == TargetPlatform.windows && screen.width < 1000) {
            for (final label in labels) {
              expect(find.byTooltip(label), findsOneWidget);
            }
          } else {
            for (final label in labels) {
              expect(find.text(label), findsWidgets);
            }
          }
          if (platform == TargetPlatform.android) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byKey(const ValueKey('global-minibar'))),
              before,
            );
            // The drawer also opens from the left edge.
            await tester.dragFrom(
              const Offset(1, 150),
              Offset(screen.width * .45, 0),
            );
            await tester.pumpAndSettle();
            expect(find.byType(Drawer), findsOneWidget);
            await tester.tap(find.text('设置'));
            await tester.pumpAndSettle();
          } else {
            await tester.tap(
              screen.width < 1000
                  ? find.byTooltip('设置')
                  : find.text('设置').first,
            );
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(find.text('版本 0.1.0+1'));
          expect(find.text('版本 0.1.0+1'), findsOneWidget);
          await tester.ensureVisible(find.byKey(const ValueKey('theme-dark')));
          await tester.tap(find.byKey(const ValueKey('theme-dark')));
          await tester.pumpAndSettle();
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
            ThemeMode.dark,
          );
          expect(
            find.byKey(const ValueKey('copy-diagnostics')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  testWidgets(
    'mounted branches retain source query, selection and scroll, search and playlist details return without resetting them',
    (tester) async {
      await size(tester, const Size(390, 844));
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        FakeDocuments()
          ..files['root'] = [
            for (var i = 0; i < 160; i++) entry(i.toString().padLeft(3, '0')),
          ],
      );
      final playback = PlaylistPlayback()..current = null;
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan();
        await library.createPlaylist(
          '导航歌单',
          library.tracks.take(2).map((t) => t.song.id),
        );
      });
      try {
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
        await tester.drag(find.byType(SongList).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        final list = tester.widget<ListView>(
          find.descendant(
            of: find.byType(SongList),
            matching: find.byType(ListView),
          ),
        );
        final offset = list.controller!.offset;
        final firstRow = find
            .descendant(
              of: find.byType(SongList),
              matching: find.byType(SongRow),
            )
            .hitTestable()
            .first;
        await tester.longPress(firstRow);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-library-search')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('library-search')));
        await tester.pump();
        expect(tester.testTextInput.hasAnyClients, isTrue);
        tester.testTextInput.enterText('001');
        await tester.pumpAndSettle();
        final backButton = find.byType(BackButton);
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pumpAndSettle();
        expect(library.query, isEmpty);
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(list.controller!.offset, offset);
        await navigate(tester, '筛选');
        await tester.enterText(
          find.byKey(const ValueKey('filter-search')),
          'kept',
        );
        await tester.pumpAndSettle();
        await navigate(tester, '歌单');
        await tester.tap(find.text('导航歌单'));
        await tester.pumpAndSettle();
        await navigate(tester, '歌曲');
        expect(find.text('已选 1 首'), findsOneWidget);
        expect(list.controller!.offset, offset);
        // An inactive playlist PopScope must not consume back on the songs branch.
        await navigate(tester, '歌单');
        expect(find.byTooltip('返回歌单'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('create-playlist')), findsOneWidget);
        await navigate(tester, '筛选');
        expect(library.filterQuery, 'kept');
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('filter-search')))
              .controller!
              .text,
          'kept',
        );
        await tester.tap(find.byKey(const ValueKey('open-playback-queue')));
        await tester.pumpAndSettle();
        expect(find.text('队列为空，从曲库、筛选或歌单添加歌曲'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(library.shutdown);
        playback.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'small screen, doubled font, dark theme and directory controls remain reachable',
    (tester) async {
      await size(tester, const Size(320, 568));
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        FakeDocuments(),
      );
      final playback = PlaylistPlayback()..current = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(MemorySettings()),
            libraryProvider.overrideWithValue(library),
            playbackProvider.overrideWithValue(playback),
          ],
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: TagMusicApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await navigate(tester, '设置');
      final settingsList = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(ListView),
      );
      expect(settingsList, findsOneWidget);
      final settingsListElement = tester.element(settingsList);
      final settingsScrollable = find.byElementPredicate((element) {
        if (element.widget is! Scrollable) return false;
        var belongsToSettingsList = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is Scrollable) return false;
          if (identical(ancestor, settingsListElement)) {
            belongsToSettingsList = true;
            return false;
          }
          return true;
        });
        return belongsToSettingsList;
      });
      expect(settingsScrollable, findsOneWidget);
      final chooseDirectory = find.byKey(const ValueKey('choose-directory'));
      await tester.scrollUntilVisible(
        chooseDirectory,
        180,
        scrollable: settingsScrollable,
      );
      await tester.pumpAndSettle();
      expect(chooseDirectory.hitTestable(), findsOneWidget);
      expect(find.text('添加文件夹'), findsOneWidget);
      await tester.ensureVisible(find.text('管理目录'));
      await tester.pumpAndSettle();
      expect(find.text('管理目录').hitTestable(), findsOneWidget);
      await tester.tap(find.text('管理目录'));
      await tester.pumpAndSettle();
      expect(find.text('尚未添加目录'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      final licenses = find.text('开源许可');
      await tester.scrollUntilVisible(
        licenses,
        180,
        scrollable: settingsScrollable,
      );
      await tester.pumpAndSettle();
      expect(licenses.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(library.shutdown);
      playback.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
