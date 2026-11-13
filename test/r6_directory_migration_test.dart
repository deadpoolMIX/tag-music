import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/core/settings.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/library_page.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_test.dart' show FakeDocuments, entry;
import 'playlists_page_test.dart' show PlaylistPlayback;
import 'settings_test.dart' show MemorySettings;

const _first = '/synthetic/r6/first';
const _second = '/synthetic/r6/second';
const _added = '/synthetic/r6/added';

// Only the document boundary is fake: all scan state, cancellation, directory
// membership and messages come from the production LibraryController. This
// does not exercise Android SAF grants or a real platform picker.
class _Documents extends FakeDocuments {
  final scannedRoots = <String>[];
  String? pickedRoot;
  int picks = 0;
  String? gatedRoot;
  final consumedTen = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> pickDirectory() async {
    picks++;
    return pickedRoot;
  }

  @override
  Stream<ScannedFile> scan(
    String root, {
    required bool Function() cancelled,
  }) async* {
    scannedRoots.add(root);
    var count = 0;
    await for (final file in super.scan(root, cancelled: cancelled)) {
      yield file;
      // Reached only when the consumer requests the next item: the tenth
      // item has been processed and the real every-ten-items publish ran.
      if (++count == 10 && root == gatedRoot) {
        consumedTen.complete();
        await release.future;
      }
    }
  }

  void unblock() {
    if (!release.isCompleted) release.complete();
  }
}

Finder _home(Finder matching) =>
    find.descendant(of: find.byType(LibraryPage), matching: matching);

Finder _homeRefresh() => _home(
  find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == '刷新所有目录',
  ),
);

Finder _settings(Finder matching) =>
    find.descendant(of: find.byType(SettingsPage), matching: matching);

Future<void> _mount(
  WidgetTester tester,
  TargetPlatform platform,
  LibraryController library,
  PlaylistPlayback playback,
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
}

Future<void> _navigate(WidgetTester tester, String label) async {
  final menu = find.byKey(const ValueKey('open-navigation')).hitTestable();
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  final drawer = find.byType(Drawer);
  final destination = drawer.evaluate().isNotEmpty
      ? find.descendant(of: drawer, matching: find.text(label))
      : find.text(label).hitTestable().first;
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await tester.pumpAndSettle();
  expect(
    label == '设置' ? find.byType(SettingsPage) : find.byType(LibraryPage),
    findsOneWidget,
  );
}

// Registered before the UI action; no polling or elapsed-time assumption is
// needed while the database scan finishes outside the fake widget clock.
Future<void> _scanFinished(LibraryController library) {
  final done = Completer<void>();
  var started = false;
  void changed() {
    if (library.scanning) started = true;
    if (started && !library.scanning) {
      library.removeListener(changed);
      done.complete();
    }
  }

  library.addListener(changed);
  return done.future;
}

Future<List<(String, String, String, String, bool)>> _members(
  LibraryController library,
) async {
  final rows = await library.db.select(library.db.songLocations).get();
  final result = [
    for (final row in rows)
      (row.root, row.songId, row.location, row.relativePath, row.available),
  ];
  result.sort((a, b) => a.toString().compareTo(b.toString()));
  return result;
}

Map<String, String> _ids(LibraryController library) => {
  for (final track in library.tracks) track.song.identity: track.song.id,
};

void _expectIdle(WidgetTester tester) {
  expect(_home(find.byType(LinearProgressIndicator)), findsNothing);
  expect(_home(find.text('取消扫描')), findsNothing);
  expect(_homeRefresh(), findsOneWidget);
  expect(tester.widget<IconButton>(_homeRefresh()).onPressed, isNotNull);
  expect(_home(find.text('添加文件夹')), findsNothing);
  expect(_home(find.text('管理目录')), findsNothing);
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

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform home refresh publishes progress and cancels without partial root membership',
      (tester) async {
        final documents = _Documents()
          ..files[_first] = [entry('synthetic-old-first')]
          ..files[_second] = [entry('synthetic-old-second')];
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
          final originalIds = _ids(library);
          final originalMembers = (await tester.runAsync(
            () => _members(library),
          ))!;
          final firstRoot = library.roots.first.location;
          documents.scannedRoots.clear();
          documents.gatedRoot = firstRoot;
          documents.files[firstRoot] = [
            for (var i = 0; i < 12; i++) entry('synthetic-new-$i'),
          ];
          await _mount(tester, platform, library, playback);
          _expectIdle(tester);
          final finished = _scanFinished(library);
          expect(_homeRefresh(), findsOneWidget);
          expect(_homeRefresh().hitTestable(), findsOneWidget);
          await tester.tap(_homeRefresh());
          await tester.runAsync(() => documents.consumedTen.future);
          await tester.pump();
          expect(library.scanning, isTrue);
          expect(library.discovered, 10);
          expect(documents.scannedRoots, [firstRoot]);
          expect(_home(find.byType(LinearProgressIndicator)), findsOneWidget);
          expect(_home(find.text('发现 10 首 · 读取元数据 10 首')), findsOneWidget);
          expect(_homeRefresh(), findsOneWidget);
          expect(tester.widget<IconButton>(_homeRefresh()).onPressed, isNull);
          expect(_home(find.text('取消扫描')).hitTestable(), findsOneWidget);
          await tester.tap(_home(find.text('取消扫描')));
          await tester.pump();
          expect(_home(find.text('正在取消，已提交的目录仍保留…')), findsOneWidget);
          expect(library.scanning, isTrue);
          documents.unblock();
          await tester.runAsync(() => finished);
          await tester.pumpAndSettle();
          _expectIdle(tester);
          expect(_home(find.text('扫描已取消；未完成目录的原曲库保持不变。')), findsOneWidget);
          expect(documents.scannedRoots, [firstRoot]);
          expect(_ids(library), originalIds);
          expect(library.tracks.every((track) => track.available), isTrue);
          expect(
            await tester.runAsync(() => _members(library)),
            originalMembers,
          );
          expect(tester.takeException(), isNull);
        } finally {
          documents.unblock();
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(library.shutdown);
          playback.dispose();
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );

    testWidgets(
      '$platform settings adds only picked root and single-root failure preserves membership and home result',
      (tester) async {
        final documents = _Documents()
          ..files[_first] = [entry('synthetic-old-first')]
          ..files[_second] = [entry('synthetic-old-second')];
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
          final originalIds = _ids(library);
          expect(
            library.roots.map((root) => root.location),
            isNot(contains(_added)),
          );
          documents
            ..pickedRoot = _added
            ..files[_added] = [entry('synthetic-added')]
            ..scannedRoots.clear();
          await _mount(tester, platform, library, playback);
          _expectIdle(tester);
          await _navigate(tester, '设置');
          final add = _settings(find.byKey(const ValueKey('choose-directory')));
          await tester.ensureVisible(add);
          final added = _scanFinished(library);
          await tester.tap(add);
          await tester.runAsync(() => added);
          await tester.pumpAndSettle();
          expect(documents.picks, 1);
          expect(documents.scannedRoots, [_added]);
          expect(library.roots.map((root) => root.location), contains(_added));
          expect(_ids(library).keys, contains('synthetic-added'));
          for (final old in originalIds.entries) {
            expect(_ids(library)[old.key], old.value);
          }
          final beforeFailure = (await tester.runAsync(
            () => _members(library),
          ))!;
          final idsBeforeFailure = _ids(library);
          documents
            ..files[_first] = [entry('synthetic-uncommitted')]
            ..brokenRoots.add(_first)
            ..scannedRoots.clear();
          final manage = _settings(find.text('管理目录'));
          await tester.ensureVisible(manage);
          await tester.tap(manage);
          await tester.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          final rootTile = find.descendant(
            of: dialog,
            matching: find.widgetWithText(ListTile, _first),
          );
          final refresh = find.descendant(
            of: rootTile,
            matching: find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '刷新该目录',
            ),
          );
          expect(refresh, findsOneWidget);
          await tester.ensureVisible(refresh);
          final failed = _scanFinished(library);
          expect(refresh.hitTestable(), findsOneWidget);
          await tester.tap(refresh);
          await tester.runAsync(() => failed);
          await tester.pumpAndSettle();
          expect(documents.scannedRoots, [_first]);
          expect(
            find.descendant(
              of: rootTile,
              matching: find.textContaining('不可访问，已保留原曲库'),
            ),
            findsOneWidget,
          );
          expect(
            library.roots
                .singleWhere((root) => root.location == _first)
                .accessible,
            isFalse,
          );
          expect(_ids(library), idsBeforeFailure);
          expect(await tester.runAsync(() => _members(library)), beforeFailure);
          expect(
            library.tracks
                .singleWhere(
                  (track) => track.song.identity == 'synthetic-old-second',
                )
                .available,
            isTrue,
          );
          expect(
            library.tracks
                .singleWhere(
                  (track) => track.song.identity == 'synthetic-added',
                )
                .available,
            isTrue,
          );
          final result = library.message!;
          expect(result, contains('扫描结束：发现 1 首'));
          expect(result, contains('失败目录 1 个'));
          await tester.tap(
            find.descendant(of: dialog, matching: find.text('关闭')),
          );
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          expect(_settings(find.text(result)), findsOneWidget);
          await _navigate(tester, '歌曲');
          _expectIdle(tester);
          expect(_home(find.text(result)), findsOneWidget);
          expect(
            _home(find.text('歌曲 synthetic-old-second.mp3')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          documents.unblock();
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(library.shutdown);
          playback.dispose();
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
