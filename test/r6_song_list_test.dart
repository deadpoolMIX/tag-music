import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/song_list.dart';
import 'package:tag_music/library/track_cover.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_page_test.dart' as library_page_test show SnapshotController;
import 'library_test.dart' show FakeDocuments;
import 'queue_playback_test.dart' show QueueDocuments, QueuePlayer, song;
import 'support/r6_tracks.dart';

class _Covers extends QueueDocuments {
  int reads = 0;
  @override
  Future<Uint8List?> cover(ProbeTrack track) async {
    reads++;
    return Uint8List.fromList([0, 1, 2]);
  }
}

void main() {
  late LibraryController library;
  setUp(() {
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      FakeDocuments(),
    );
  });
  tearDown(() => library.shutdown());

  testWidgets(
    'shared row layout, long press, secondary tap, menu and empty selection actions',
    (tester) async {
      final playback = library_page_test.SnapshotController()..current = null;
      final rows = [r6Track('a'), r6Track('b')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongList(
              library: library,
              playback: playback,
              source: rows,
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('歌曲a')).style!.fontSize, 16);
      expect(
        tester.widget<Text>(find.text('歌曲a')).style!.fontWeight,
        FontWeight.normal,
      );
      expect(tester.widget<TrackCover>(find.byType(TrackCover).first).size, 44);
      expect(
        tester.getSize(find.byKey(const ValueKey('enqueue-library-a'))),
        const Size(48, 48),
      );
      await tester.longPress(find.byKey(const ValueKey('a')));
      await tester.pumpAndSettle();
      expect(playback.selectedSongId, isNull);
      expect(find.text('已选 1 首'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('a')));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 首'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('batch-tags')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('退出多选'));
      await tester.tap(find.text('退出多选'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('b')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);
      expect(playback.selectedSongId, isNull);
      await tester.ensureVisible(find.text('退出多选'));
      await tester.tap(find.text('退出多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('歌曲操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('多选歌曲'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 首'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
    },
  );

  testWidgets(
    'source order, cross-query union, missing filtering and FIFO preserve the active queue',
    (tester) async {
      final documents = _Covers();
      final player = QueuePlayer();
      final playback = PlaybackController(player, documents);
      final source = [
        r6Track('c', available: false),
        r6Track('b'),
        r6Track('a'),
      ];
      var rows = source.reversed.toList();
      late StateSetter update;
      try {
        await playback.playSongs([song('old'), song('tail')], 0);
        final current = playback.queue.current!.entryId;
        final opens = player.opens.length;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SongList(
                    library: library,
                    playback: playback,
                    source: source,
                    rows: rows,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('enqueue-library-a')));
        await tester.tap(find.byKey(const ValueKey('enqueue-library-b')));
        await tester.tap(find.byKey(const ValueKey('enqueue-library-a')));
        await tester.pumpAndSettle();
        expect(playback.queue.entries.map((e) => e.song.songId), [
          'old',
          'a',
          'b',
          'a',
          'tail',
        ]);
        expect(playback.queue.entries.map((e) => e.entryId).toSet().length, 5);
        expect(player.opens.length, opens);
        expect(playback.queue.current!.entryId, current);
        await tester.longPress(find.byKey(const ValueKey('a')));
        await tester.pumpAndSettle();
        update(() => rows = [source[1]]);
        await tester.pumpAndSettle();
        await tester.tap(find.text('全选'));
        await tester.pumpAndSettle();
        update(() => rows = [source[0]]);
        await tester.pumpAndSettle();
        await tester.tap(find.text('全选'));
        await tester.pumpAndSettle();
        expect(find.text('已选 3 首'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('enqueue-library-selected')),
        );
        await tester.tap(
          find.byKey(const ValueKey('enqueue-library-selected')),
        );
        await tester.pumpAndSettle();
        expect(playback.queue.entries.map((e) => e.song.songId), [
          'old',
          'a',
          'b',
          'a',
          'b',
          'a',
          'tail',
        ]);
        expect(playback.queue.current!.entryId, current);
        expect(playback.playing, isTrue);
        expect(
          documents.reads,
          lessThanOrEqualTo(4),
          reason: 'playback notifications reuse visible cover futures',
        );
        await playback.next();
        expect(playback.currentSongId, 'a');
        await playback.next();
        expect(playback.currentSongId, 'b');
        await playback.next();
        expect(playback.currentSongId, 'a');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(playback.shutdown);
      }
    },
  );

  testWidgets(
    'locate highlight expires after two virtual seconds without moving its target',
    (tester) async {
      final playback = library_page_test.SnapshotController()
        ..current = null
        ..selectedSongId = '10';
      final rows = [for (var i = 0; i < 30; i++) r6Track('$i')];
      final originalIds = rows.map((row) => row.song.id).toList();
      final located = <String>[];
      DateTime? locatedAt;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SongList(
                library: library,
                playback: playback,
                source: rows,
                rows: rows,
                onLocated: (id, _) {
                  located.add(id);
                  locatedAt = tester.binding.clock.now();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('locate-current-song')));
        await tester.pumpAndSettle();
        final target = find.byKey(const ValueKey('10'));
        expect(located, ['10']);
        expect(tester.widget<SongRow>(target).highlighted, isTrue);
        expect(find.byKey(const ValueKey('located-10')), findsOneWidget);
        final rect = tester.getRect(target);
        final viewport = tester.getRect(find.byType(ListView));
        expect(rect.top, greaterThanOrEqualTo(viewport.top));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
        final list = tester.widget<ListView>(find.byType(ListView));
        final offset = list.controller!.offset;

        // These are widget-clock lifecycle assertions, not device timings.
        final elapsed = tester.binding.clock.now().difference(locatedAt!);
        final untilJustBeforeExpiry =
            const Duration(milliseconds: 1999) - elapsed;
        expect(untilJustBeforeExpiry, greaterThan(Duration.zero));
        await tester.pump(untilJustBeforeExpiry);
        expect(tester.widget<SongRow>(target).highlighted, isTrue);
        expect(find.byKey(const ValueKey('located-10')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.widget<SongRow>(target).highlighted, isFalse);
        expect(find.byKey(const ValueKey('located-10')), findsNothing);
        expect(tester.getRect(target), rect);
        expect(list.controller!.offset, offset);
        expect(located, ['10']);
        expect(playback.currentSongId, '10');
        expect(
          tester
              .widget<SongList>(find.byType(SongList))
              .rows
              .map((row) => row.song.id),
          originalIds,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        playback.dispose();
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '10000 rows locate first, middle and final at text scale $scale; invalidated actions never highlight stale targets',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final playback = library_page_test.SnapshotController()..current = null;
        var rows = [
          for (var i = 0; i < 10000; i++)
            r6Track('$i', title: '很长的歌名$i' * 3, artist: '很长歌手' * 8),
        ];
        final source = rows;
        late StateSetter update;
        final located = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return SongList(
                      library: library,
                      playback: playback,
                      source: source,
                      rows: rows,
                      onLocated: (id, _) => located.add(id),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final id in ['0', '5000', '9999']) {
          playback.selectedSongId = id;
          playback.notifyListeners();
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('locate-current-song')));
          await tester.pumpAndSettle();
          final target = find.byKey(ValueKey('located-$id'));
          expect(target, findsOneWidget);
          final rect = tester.getRect(target);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(844));
        }
        expect(located, ['0', '5000', '9999']);
        playback.selectedSongId = '5000';
        playback.notifyListeners();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('locate-current-song')));
        await tester.pump(const Duration(milliseconds: 50));
        update(() => rows = rows.reversed.toList());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('located-5000')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('locate-current-song')));
        await tester.pump(const Duration(milliseconds: 50));
        playback.selectedSongId = '0';
        playback.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('located-5000')), findsNothing);
        update(() => rows = [source[1]]);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('locate-current-song')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        playback.dispose();
      },
    );
  }
}
