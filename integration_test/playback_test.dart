import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/main.dart' as app;
import 'package:tag_music/playback/playback_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows native formats, seek, pause, bad file recovery and repeated switching',
    (tester) async {
      if (!Platform.isWindows) return;
      final fixtures = Platform.environment['TAG_MUSIC_FIXTURES'];
      expect(fixtures, isNotNull);
      await app.main();
      await tester.pumpAndSettle();
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      ).read(playbackProvider)!;
      await tester.runAsync(() async {
        await controller.player.setVolume(20);
        final ready = Platform.environment['TAG_MUSIC_CAPTURE_READY'];
        if (ready != null) {
          await File('$ready.app').writeAsString('ready');
          for (
            var attempt = 0;
            attempt < 600 && !await File(ready).exists();
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            await File(ready).exists(),
            isTrue,
            reason: 'Loopback recorder must be ready',
          );
        }
        await controller.refresh(fixtures!);
        expect(controller.tracks.length, 7);
        for (final extension in ['mp3', 'flac', 'm4a', 'wav', 'ogg', 'opus']) {
          final index = controller.tracks.indexWhere(
            (track) =>
                track.name.endsWith('.$extension') &&
                !track.name.startsWith('坏'),
          );
          await controller.select(index);
          for (
            var attempt = 0;
            attempt < 40 &&
                controller.player.state.position.inMilliseconds < 400;
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(controller.error, isNull, reason: extension);
          expect(controller.metadata?.title, '中文测试音', reason: extension);
          expect(
            controller.player.state.duration.inSeconds,
            inInclusiveRange(23, 25),
            reason: extension,
          );
          expect(
            controller.player.state.position.inMilliseconds,
            greaterThan(300),
            reason: extension,
          );
          await controller.seek(const Duration(seconds: 8));
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(
            controller.player.state.position.inSeconds,
            greaterThanOrEqualTo(7),
            reason: extension,
          );
          await controller.pause();
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final position = controller.player.state.position;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(
            (controller.player.state.position - position).inMilliseconds.abs(),
            lessThan(150),
          );
        }
        final bad = controller.tracks.indexWhere(
          (track) => track.name.startsWith('坏'),
        );
        await controller.select(bad);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(controller.metadataWarning, isNotNull);
        final good = controller.tracks.indexWhere(
          (track) => track.name.endsWith('.flac'),
        );
        final other = controller.tracks.indexWhere(
          (track) => track.name.endsWith('.mp3') && !track.name.startsWith('坏'),
        );
        await Future.wait([
          for (var i = 0; i < 20; i++)
            controller.select(i.isEven ? good : other),
        ]);
        await controller.select(good);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(controller.error, isNull);
        expect(controller.player.state.playing, isTrue);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('中文测试音'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['TAG_MUSIC_EVIDENCE'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .ancestor(
                of: find.byType(AppShell),
                matching: find.byType(RepaintBoundary),
              )
              .first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$directory/windows-native-playback.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      await tester.runAsync(controller.stop);
    },
  );
}
