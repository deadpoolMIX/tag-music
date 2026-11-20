import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'audio_handler_test.dart'
    show TransitionDocuments, TransitionPlayer, TransitionStreams;

QueueSong song(String id) => QueueSong(
  songId: id,
  track: ProbeTrack(location: 'test://$id', name: '$id.flac'),
);

class QueueStreams extends TransitionStreams {
  final endings = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get completed => endings.stream;
}

class QueuePlayer extends TransitionPlayer {
  QueuePlayer() {
    state = PlayerState();
  }
  @override
  QueueStreams get stream => _stream;
  final _stream = QueueStreams();
  final opens = <String>[];
  final seeks = <Duration>[];
  final rejected = <String>{};
  bool rejectAll = false;
  bool emitErrorOnOpen = false;
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final uri = (playable as Media).uri;
    opens.add(uri);
    if (rejectAll || rejected.contains(uri)) {
      if (emitErrorOnOpen) {
        stream.failures.add('decoder rejected $uri');
        return;
      }
      throw StateError('cannot open $uri');
    }
    await super.open(playable, play: play);
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    state = state.copyWith(position: position);
  }

  void end() {
    state = state.copyWith(playing: false, completed: true);
    stream.endings.add(true);
  }

  @override
  Future<void> dispose() async {
    await stream.endings.close();
    await super.dispose();
  }
}

class QueueDocuments extends TransitionDocuments {
  QueueDocuments() : super(android: true);
  int peakDescriptors = 0;
  final openedUris = <String>[];
  @override
  Future<int> open(String uri) async {
    openedUris.add(uri);
    final fd = await super.open(uri);
    if (descriptors.length > peakDescriptors) {
      peakDescriptors = descriptors.length;
    }
    return fd;
  }
}

class DeniedSession implements AudioSession {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setActive) return Future<bool>.value(false);
    throw UnsupportedError('unused session method');
  }
}

void main() {
  late QueuePlayer player;
  late QueueDocuments documents;
  late PlaybackController controller;

  setUp(() {
    player = QueuePlayer();
    documents = QueueDocuments();
    controller = PlaybackController(player, documents);
    addTearDown(controller.shutdown);
  });

  // A serialized no-op waits for already-delivered engine callbacks.
  Future<void> drain() => controller.setMode(controller.queue.mode);

  test(
    'a seek queued behind a track switch cannot target the new entry',
    () async {
      await controller.setMode(PlaybackMode.sequential);
      await controller.playSongs([song('A'), song('B')], 0);
      final previousEntry = controller.queue.current!.entryId;
      final change = controller.next();
      final seek = controller.seek(
        const Duration(seconds: 8),
        expectedEntryId: previousEntry,
      );
      await Future.wait([change, seek]);
      expect(controller.currentSongId, 'B');
      expect(player.seeks, isEmpty);
      expect(player.state.position, Duration.zero);
      player.state = player.state.copyWith(
        duration: const Duration(minutes: 1),
      );
      await controller.seek(
        const Duration(seconds: 8),
        expectedEntryId: controller.queue.current!.entryId,
      );
      expect(player.state.position, const Duration(seconds: 8));
    },
  );

  test(
    'startup/add are silent; UUID resolver supplies current SAF location',
    () async {
      expect(controller.current, isNull);
      expect(controller.queue.mode, PlaybackMode.shuffle);
      await controller.addToQueue([song('uuid-A'), song('uuid-A')]);
      expect(controller.playing, isFalse);
      expect(player.opens, isEmpty);
      expect(documents.descriptors, isEmpty);
      expect(
        controller.queue.entries.map((e) => e.entryId).toSet(),
        hasLength(2),
      );
      controller.resolveSong = (id) => ProbeTrack(
        location: 'content://relocated/$id',
        name: 'new-name.flac',
      );
      await controller.play();
      expect(controller.currentSongId, 'uuid-A');
      expect(controller.current?.name, 'new-name.flac');
      expect(documents.openedUris, ['content://relocated/uuid-A']);
      expect(documents.descriptors, hasLength(1));
      expect(TagAudioHandler(controller).mediaItem.value?.id, 'uuid-A');
    },
  );

  test(
    'FIFO additions and edits preserve sound/position; paused next plays',
    () async {
      await controller.setMode(PlaybackMode.sequential);
      await controller.playSongs([song('start'), song('original')], 0);
      await controller.seek(const Duration(seconds: 8));
      final stops = player.stops;
      await controller.addToQueue([song('A')]);
      await controller.addToQueue([song('B')]);
      await controller.reorderQueue(
        controller.queue.entries.map((e) => e.entryId).toList(),
      );
      await controller.setMode(PlaybackMode.shuffle);
      expect(player.stops, stops);
      expect(player.state.position.inSeconds, 8);
      await controller.pause();
      final handler = TagAudioHandler(controller);
      await handler.skipToNext();
      expect(controller.currentSongId, 'A');
      expect(controller.playing, isTrue);
      await handler.skipToNext();
      expect(controller.currentSongId, 'B');
      await handler.skipToNext();
      expect(controller.currentSongId, 'original');
      expect(documents.peakDescriptors, 1);
    },
  );

  test(
    'removing current preserves playing or paused, and final removal unloads',
    () async {
      await controller.playSongs([song('A'), song('B'), song('C')], 0);
      final displayed = controller.queue.entries
          .map((entry) => entry.song.songId)
          .toList();
      await controller.removeFromQueue(controller.queue.current!.entryId);
      expect(controller.currentSongId, displayed[1]);
      expect(controller.playing, isTrue);
      await controller.pause();
      await controller.removeFromQueue(controller.queue.current!.entryId);
      expect(controller.currentSongId, displayed[2]);
      expect(controller.playing, isFalse);
      expect(documents.descriptors, hasLength(1));
      await controller.removeFromQueue(controller.queue.current!.entryId);
      expect(controller.current, isNull);
      expect(controller.tracks, isEmpty);
      expect(player.state.playlist.medias, isEmpty);
      expect(documents.descriptors, isEmpty);
      expect(documents.peakDescriptors, 1);
    },
  );

  test(
    'missing UUID is skipped without opening cached stale location',
    () async {
      await controller.setMode(PlaybackMode.sequential);
      controller.resolveSong = (id) => id == 'lost' ? null : song(id).track;
      await controller.playSongs([song('lost'), song('good')], 0);
      expect(controller.currentSongId, 'good');
      expect(controller.error, isNull);
      expect(controller.playbackNotice, contains('lost.flac'));
      expect(documents.openedUris, ['test://good']);
    },
  );

  test(
    'audio focus refusal pauses current instead of misclassifying every song',
    () async {
      controller.session = DeniedSession();
      await controller.playSongs([song('A'), song('B'), song('C')], 0);
      expect(controller.currentSongId, 'A');
      expect(player.opens, hasLength(1));
      expect(controller.error, contains('音频焦点'));
      expect(controller.playing, isFalse);
      expect(documents.descriptors, isEmpty);
      controller.session = null;
      await controller.play();
      expect(controller.currentSongId, 'A');
      expect(controller.error, isNull);
      expect(controller.playing, isTrue);
    },
  );

  for (final engineEvent in [false, true]) {
    test(
      'all failures exhaust exactly once, engineEvent=$engineEvent',
      () async {
        player.rejectAll = true;
        player.emitErrorOnOpen = engineEvent;
        await controller.playSongs([song('A'), song('B'), song('C')], 0);
        await drain();
        expect(player.opens, hasLength(3));
        expect(documents.openedUris.toSet(), {
          'test://A',
          'test://B',
          'test://C',
        });
        expect(controller.playing, isFalse);
        expect(controller.error, contains('没有可继续播放'));
        expect(documents.descriptors, isEmpty);
        expect(documents.peakDescriptors, 1);
        expect(controller.queue.entries, hasLength(3));
        player.rejectAll = false;
        await controller.play();
        expect(player.opens, hasLength(4));
        expect(controller.error, isNull);
        expect(controller.playing, isTrue);
      },
    );
  }

  test(
    'asynchronous decoder failures advance then stop without cycling bad items',
    () async {
      final counts = <String>[];
      controller.recordCompletedPlay = (songId) async => counts.add(songId);
      await controller.setMode(PlaybackMode.repeatAll);
      await controller.playSongs([song('A'), song('B'), song('C')], 0);
      player.stream.failures.add('A failed');
      player.stream.endings.add(true);
      await drain();
      expect(controller.currentSongId, 'B');
      expect(controller.error, isNull);
      expect(controller.playbackNotice, contains('A failed'));
      player.stream.failures.add('B failed');
      await drain();
      expect(controller.currentSongId, 'C');
      player.stream.failures.add('C failed');
      await drain();
      expect(player.opens, hasLength(3));
      expect(controller.playing, isFalse);
      expect(controller.error, contains('C failed'));
      expect(documents.descriptors, isEmpty);
      expect(documents.peakDescriptors, 1);
      expect(counts, isEmpty);
    },
  );

  for (final mode in PlaybackMode.values) {
    test(
      '$mode completion dispatches once and respects single repeat priority',
      () async {
        final counts = <String>[];
        controller.recordCompletedPlay = (songId) async => counts.add(songId);
        await controller.setMode(mode);
        await controller.playSongs([song('A'), song('B')], 0);
        await controller.addToQueue([song('priority')]);
        await controller.seek(const Duration(seconds: 8));
        expect(counts, isEmpty);
        player.end();
        player.stream.endings.add(true);
        await drain();
        expect(counts, ['A']);
        expect(player.opens, hasLength(2));
        expect(
          controller.currentSongId,
          mode == PlaybackMode.repeatOne ? 'A' : 'priority',
        );
        if (mode == PlaybackMode.repeatOne) {
          expect(controller.queue.priorityIds, hasLength(1));
          player.end();
          await drain();
          expect(counts, ['A', 'A']);
          await controller.next();
          expect(controller.currentSongId, 'priority');
          expect(counts, ['A', 'A']);
        }
        expect(documents.peakDescriptors, 1);
      },
    );
  }

  test(
    'entry selection survives queued reorder and ignores removed identities',
    () async {
      await controller.addToQueue([song('A'), song('A'), song('C')]);
      final ids = controller.queue.entries.map((e) => e.entryId).toList();
      final reordered = controller.reorderQueue([ids[2], ids[0], ids[1]]);
      final selected = controller.selectEntry(ids[1]);
      await reordered;
      await selected;
      expect(controller.queue.current?.entryId, ids[1]);
      expect(controller.index, 2);
      final removed = controller.removeFromQueue(ids[1]);
      final stale = controller.selectEntry(ids[1]);
      await removed;
      final stops = player.stops;
      final current = controller.queue.current?.entryId;
      await stale;
      expect(controller.queue.current?.entryId, current);
      expect(player.stops, stops);
      expect(controller.error, isNull);
    },
  );

  test('sequential natural end releases media, stop/replay and clear remain usable', () async {
    await controller.setMode(PlaybackMode.sequential);
    await controller.playSongs([song('A')], 0);
    player.end();
    await drain();
    expect(controller.currentSongId, 'A');
    expect(controller.playing, isFalse);
    expect(documents.descriptors, isEmpty);
    await controller.play();
    await controller.seek(const Duration(seconds: 8));
    await controller.stop();
    expect(player.state.position, Duration.zero);
    await controller.play();
    expect(controller.playing, isTrue);
    await controller.clearQueue();
    expect(controller.current, isNull);
    expect(controller.tracks, isEmpty);
    expect(controller.playing, isFalse);
    expect(documents.descriptors, isEmpty);
  });
}
