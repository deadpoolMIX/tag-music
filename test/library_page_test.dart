import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

import 'audio_handler_test.dart' show HandlerController;
import 'library_test.dart' show FakeDocuments, entry;

class CoverDocuments extends DocumentAccess {
  CoverDocuments() : super(android: false);
  @override
  Future<Uint8List?> cover(ProbeTrack track) async => null;
}

class SnapshotController extends HandlerController {
  String? selectedSongId;
  @override
  String? get currentSongId => selectedSongId;
  @override
  DocumentAccess get documents => _documents;
  final _documents = CoverDocuments();
  @override
  String? get metadataWarning => null;
  @override
  int get index => 0;
  @override
  Future<void> playSongs(List<QueueSong> snapshot, int target) async {
    tracks = List.unmodifiable(snapshot.map((song) => song.track));
    current = tracks[target];
    selectedSongId = snapshot[target].songId;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'small-screen library can search while playback snapshot stays unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = FakeDocuments()..files['a'] = [entry('甲'), entry('乙')];
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        access,
      );
      final playback = SnapshotController()..current = null;
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan();
      });
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
      await tester.tap(find.byKey(const ValueKey('library-search')));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      // Exercise the connection created by a real tap, not tester.enterText's
      // helper which can repair a missing connection before injecting text.
      tester.testTextInput.enterText('甲');
      await tester.pumpAndSettle();
      expect(library.visible.length, 1);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('歌曲 甲.mp3'));
      await tester.pumpAndSettle();
      expect(playback.tracks.length, 2);
      await tester.enterText(find.byKey(const ValueKey('library-search')), '乙');
      await tester.pumpAndSettle();
      expect(find.text('歌曲 甲.mp3'), findsNothing);
      expect(playback.current?.name, '甲.mp3');
      expect(playback.tracks.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(library.shutdown);
      playback.dispose();
    },
  );
}
