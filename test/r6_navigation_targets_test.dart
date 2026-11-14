import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/core/settings.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/filter_page.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_page.dart';
import 'package:tag_music/library/playlists_page.dart';
import 'package:tag_music/library/tags_page.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_test.dart' show FakeDocuments, entry;
import 'playlists_page_test.dart' show PlaylistPlayback;
import 'settings_test.dart' show MemorySettings;

const _targets = [
  (AppDestination.songs, '歌曲'),
  (AppDestination.filter, '筛选'),
  (AppDestination.playlists, '歌单'),
  (AppDestination.albums, '专辑'),
  (AppDestination.artists, '歌手'),
  (AppDestination.tags, '标签'),
  (AppDestination.settings, '设置'),
];
const _query = 'synthetic-kept';
const _warning = '合成启动警告：请检查设置';

Finder _shellStack() => find.byWidgetPredicate(
  (widget) =>
      widget is IndexedStack &&
      widget.children.any(
        (child) => child.key == const ValueKey(AppDestination.songs),
      ),
);

Finder _branch(AppDestination destination) => find.descendant(
  of: _shellStack(),
  matching: find.byKey(ValueKey(destination)),
);

Finder _within(AppDestination destination, Finder matching) =>
    find.descendant(of: _branch(destination), matching: matching);

// Match public Tooltip widgets wrapping navigation InkWells, never framework
// RawTooltips or identical labels in hidden pages and dropdown items.
Finder _navigationTooltips() => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.child is InkWell,
);

Finder _navigation() => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is Tooltip && widget.child is InkWell && widget.message == '歌曲',
  ),
  matching: find.byType(SingleChildScrollView),
);

Finder _navigationControls() =>
    find.descendant(of: _navigation(), matching: _navigationTooltips());

void _expectDesktopNavigation() {
  expect(find.byType(Drawer), findsNothing);
  expect(find.byType(NavigationBar), findsNothing);
  expect(find.byKey(const ValueKey('open-navigation')), findsNothing);
}

Future<void> _openNavigation(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  if (platform == TargetPlatform.android) {
    final menu = find.byKey(const ValueKey('open-navigation')).hitTestable();
    expect(menu, findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer).hitTestable(), findsOneWidget);
  } else {
    _expectDesktopNavigation();
  }
  expect(_navigation(), findsOneWidget);
}

void _expectNavigationOrder(WidgetTester tester, {required bool compact}) {
  final controls = _navigationControls();
  expect(controls, findsNWidgets(7));
  expect(
    tester.widgetList<Tooltip>(controls).map((widget) => widget.message),
    _targets.map((target) => target.$2),
  );
  Rect? previous;
  for (var index = 0; index < _targets.length; index++) {
    final label = _targets[index].$2;
    final control = controls.at(index);
    final ink = find.descendant(of: control, matching: find.byType(InkWell));
    expect(ink, findsOneWidget);
    expect(ink.hitTestable(), findsOneWidget);
    final rect = tester.getRect(ink);
    if (previous != null) {
      expect(rect.top, greaterThanOrEqualTo(previous.bottom));
      expect(rect.center.dy, greaterThan(previous.center.dy));
    }
    previous = rect;
    expect(
      find.descendant(of: control, matching: find.text(label)),
      compact ? findsNothing : findsOneWidget,
    );
    if (compact) {
      final icon = find.descendant(of: control, matching: find.byType(Icon));
      expect(tester.widget<Icon>(icon).semanticLabel, label);
    }
  }
  if (compact) {
    expect(
      find.descendant(of: _navigation(), matching: find.byType(Text)),
      findsNothing,
    );
  }
}

void _expectDestination(WidgetTester tester, AppDestination destination) {
  expect(_shellStack(), findsOneWidget);
  final stack = tester.widget<IndexedStack>(_shellStack());
  expect(
    stack.children.map((child) => child.key),
    _targets.map((target) => ValueKey(target.$1)),
  );
  expect(stack.index, destination.index);
  expect(stack.children[stack.index!].key, ValueKey(destination));
  expect(_branch(destination), findsOneWidget);
  final (Type? page, Finder content) = switch (destination) {
    AppDestination.songs => (LibraryPage, find.text('歌曲 synthetic-kept.mp3')),
    AppDestination.filter => (
      FilterPage,
      find.byKey(const ValueKey('filter-search')),
    ),
    AppDestination.playlists => (
      PlaylistsPage,
      find.byKey(const ValueKey('create-playlist')),
    ),
    AppDestination.albums => (
      null,
      find.byKey(const ValueKey('albums-heading')),
    ),
    AppDestination.artists => (
      null,
      find.byKey(const ValueKey('artists-heading')),
    ),
    AppDestination.tags => (TagsPage, find.byKey(const ValueKey('create-tag'))),
    AppDestination.settings => (
      SettingsPage,
      find.byKey(const ValueKey('theme-system')),
    ),
  };
  if (page != null) {
    expect(_within(destination, find.byType(page)), findsOneWidget);
  }
  expect(_within(destination, content), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _select(
  WidgetTester tester,
  TargetPlatform platform,
  AppDestination destination,
) async {
  final label = _targets.singleWhere((target) => target.$1 == destination).$2;
  final control = find.descendant(
    of: _navigation(),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip &&
          widget.child is InkWell &&
          widget.message == label,
    ),
  );
  expect(control, findsOneWidget);
  final ink = find.descendant(of: control, matching: find.byType(InkWell));
  await tester.ensureVisible(ink);
  await tester.pumpAndSettle();
  expect(ink.hitTestable(), findsOneWidget);
  await tester.tap(ink);
  await tester.pumpAndSettle();
  _expectDestination(tester, destination);
  if (platform == TargetPlatform.android) {
    final scaffold = find.byWidgetPredicate(
      (widget) => widget is Scaffold && widget.drawer != null,
    );
    expect(tester.state<ScaffoldState>(scaffold).isDrawerOpen, isFalse);
    expect(find.byType(Drawer).hitTestable(), findsNothing);
  } else {
    _expectDesktopNavigation();
  }
}

Future<void> _withApp(
  WidgetTester tester,
  Size screen,
  Future<void> Function(LibraryController library) exercise, {
  String? warning,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final documents = FakeDocuments()
    ..files['/synthetic/r6/navigation'] = [entry(_query)];
  final library = LibraryController(
    LibraryDatabase(NativeDatabase.memory()),
    documents,
  );
  final playback = PlaylistPlayback()..current = null;
  try {
    await tester.runAsync(() async {
      await library.initialize();
      await library.scan();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(MemorySettings()),
          startupWarningProvider.overrideWithValue(warning),
          libraryProvider.overrideWithValue(library),
          playbackProvider.overrideWithValue(playback),
        ],
        child: const TagMusicApp(),
      ),
    );
    await tester.pumpAndSettle();
    await exercise(library);
    expect(tester.takeException(), isNull);
  } finally {
    try {
      await tester.pumpWidget(const SizedBox());
    } finally {
      try {
        await tester.runAsync(library.shutdown);
      } finally {
        playback.dispose();
      }
    }
  }
}

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

  for (final (platform, screen) in [
    (TargetPlatform.android, const Size(390, 844)),
    (TargetPlatform.windows, const Size(1280, 800)),
    (TargetPlatform.windows, const Size(720, 800)),
  ]) {
    testWidgets(
      '$platform $screen orders and clicks all seven real destinations',
      (tester) => _withApp(tester, screen, (_) async {
        _expectDestination(tester, AppDestination.songs);
        for (final target in [..._targets.skip(1), _targets.first]) {
          final activeIndex = tester.widget<IndexedStack>(_shellStack()).index;
          expect(activeIndex, isNot(target.$1.index));
          await _openNavigation(tester, platform);
          _expectNavigationOrder(
            tester,
            compact: platform == TargetPlatform.windows && screen.width < 1000,
          );
          await _select(tester, platform, target.$1);
        }
      }),
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform startup warning actually opens settings and diagnostics',
      (tester) => _withApp(
        tester,
        platform == TargetPlatform.android
            ? const Size(390, 844)
            : const Size(1280, 800),
        (_) async {
          _expectDestination(tester, AppDestination.songs);
          final banner = find.byType(MaterialBanner);
          expect(banner, findsOneWidget);
          expect(
            find.descendant(of: banner, matching: find.text(_warning)),
            findsOneWidget,
          );
          final action = find.descendant(
            of: banner,
            matching: find.widgetWithText(TextButton, '查看设置'),
          );
          expect(action.hitTestable(), findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
          _expectDestination(tester, AppDestination.settings);
          final version = _within(
            AppDestination.settings,
            find.text('版本 0.1.0+1'),
          );
          await tester.ensureVisible(version);
          await tester.pumpAndSettle();
          expect(version.hitTestable(), findsOneWidget);
          final diagnostics = _within(
            AppDestination.settings,
            find.byKey(const ValueKey('copy-diagnostics')),
          );
          await tester.ensureVisible(diagnostics);
          await tester.pumpAndSettle();
          expect(diagnostics.hitTestable(), findsOneWidget);
          expect(tester.widget<TextButton>(diagnostics).onPressed, isNotNull);
          if (platform == TargetPlatform.windows) {
            _expectDesktopNavigation();
          }
          expect(tester.takeException(), isNull);
        },
        warning: _warning,
      ),
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'mounted Windows shell narrows and restores without replacing filter state',
    (tester) => _withApp(tester, const Size(1280, 800), (library) async {
      await _openNavigation(tester, TargetPlatform.windows);
      _expectNavigationOrder(tester, compact: false);
      await _select(tester, TargetPlatform.windows, AppDestination.filter);
      final input = _within(
        AppDestination.filter,
        find.byKey(const ValueKey('filter-search')),
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, _query);
      await tester.pumpAndSettle();
      final filter = _within(AppDestination.filter, find.byType(FilterPage));
      final originalState = tester.state<State<FilterPage>>(filter);
      final originalController = tester.widget<TextField>(input).controller!;
      final originalShellState = tester.state(find.byType(AppShell));

      void expectSession() {
        _expectDestination(tester, AppDestination.filter);
        expect(tester.state(find.byType(AppShell)), same(originalShellState));
        expect(tester.state<State<FilterPage>>(filter), same(originalState));
        expect(
          tester.widget<TextField>(input).controller,
          same(originalController),
        );
        expect(originalController.text, _query);
        expect(library.filterQuery, _query);
        _expectDesktopNavigation();
      }

      expectSession();
      tester.view.physicalSize = const Size(720, 800);
      await tester.pumpAndSettle();
      expectSession();
      _expectNavigationOrder(tester, compact: true);
      await _select(tester, TargetPlatform.windows, AppDestination.tags);
      await _select(tester, TargetPlatform.windows, AppDestination.filter);
      expectSession();

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expectSession();
      _expectNavigationOrder(tester, compact: false);
      await _select(tester, TargetPlatform.windows, AppDestination.playlists);
      await _select(tester, TargetPlatform.windows, AppDestination.filter);
      expectSession();
    }),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
