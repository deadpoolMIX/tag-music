import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/main.dart' as app;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/playback/playback_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'R2 Windows real recursive library, artwork, playback and reopen',
    (tester) async {
      if (!Platform.isWindows) return;
      final fixtures = Platform.environment['TAG_MUSIC_LIBRARY_FIXTURES']!;
      final report = Platform.environment['TAG_MUSIC_LIBRARY_RUNTIME_REPORT']!;
      final temp = await Directory.systemTemp.createTemp(
        'tag-music-r2-runtime-',
      );
      final file = File('${temp.path}/library.sqlite');
      final playback = await app.initializePlayback();
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.createInBackground(file)),
        playback.documents,
      );
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan([
          '$fixtures/primary',
          '$fixtures/secondary',
          '$fixtures/primary/子目录',
        ]);
        expect(library.tracks.length, 9);
        expect(library.tracks.every((t) => t.available), isTrue);
        final ids = library.tracks.map((t) => t.song.id).toSet();
        await library.scan(['$fixtures/primary', '$fixtures/secondary']);
        expect(library.tracks.map((t) => t.song.id).toSet(), ids);
        expect(library.metadataReads, 1, reason: 'only broken MP3 is retried');
        final art = library.tracks.singleWhere(
          (t) => t.song.name == '内嵌封面.flac',
        );
        expect(
          (await playback.documents.cover(art.probe))?.length,
          greaterThan(0),
        );
        final queue = library.visible.where((t) => t.available).toList();
        await playback.player.setVolume(20);
        await playback.playSongs(
          queue.map((t) => t.queueSong).toList(),
          queue.indexOf(art),
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        expect(playback.error, isNull);
        expect(playback.playing, isTrue);
        expect(playback.player.state.position.inMilliseconds, greaterThan(300));
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackProvider.overrideWithValue(playback),
            libraryProvider.overrideWithValue(library),
          ],
          child: RepaintBoundary(key: boundary, child: const TagMusicApp()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        '封面',
      );
      await tester.pumpAndSettle();
      expect(find.text('封面测试音'), findsWidgets);
      expect(library.visible.length, 1);
      expect(
        playback.tracks.length,
        9,
        reason: 'search must not replace playback snapshot',
      );
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final screenshot = await render.toImage(pixelRatio: 1);
      final bytes = (await screenshot.toByteData(
        format: ui.ImageByteFormat.png,
      ))!;
      await tester.runAsync(() async {
        await File('$report/windows-library.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        final ready = Platform.environment['TAG_MUSIC_CAPTURE_READY'];
        if (ready != null) {
          await playback.pause();
          await File('$ready.app').writeAsString('ready');
          for (var i = 0; i < 600 && !await File(ready).exists(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            await File(ready).exists(),
            isTrue,
            reason: 'authorized loopback must be ready',
          );
          await playback.seek(Duration.zero);
          await playback.play();
          await Future<void>.delayed(const Duration(seconds: 14));
        }
        await playback.pause();
        final oldIds = library.tracks.map((t) => t.song.id).toSet();
        await library.shutdown();
        final reopened = LibraryController(
          LibraryDatabase(NativeDatabase.createInBackground(file)),
          playback.documents,
        );
        try {
          await reopened.initialize();
          expect(reopened.tracks.map((t) => t.song.id).toSet(), oldIds);
          expect(reopened.tracks.length, 9);
          expect(playback.playing, isFalse);
        } finally {
          await reopened.shutdown();
        }
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await playback.shutdown();
        await temp.delete(recursive: true);
      });
    },
  );
}
