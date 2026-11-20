import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/playback_page.dart';

class HandlerPlayer implements Player {
  @override
  PlayerState state = PlayerState(
    playlist: Playlist([Media('test://song')]),
    playing: true,
    duration: const Duration(seconds: 24),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused fake player method');
}

class HandlerController extends ChangeNotifier implements PlaybackController {
  @override
  final PlaybackQueue queue = PlaybackQueue();
  @override
  final HandlerPlayer player = HandlerPlayer();
  @override
  bool get playing => player.state.playing;
  @override
  bool get canNext => false;
  @override
  bool get canPrevious => false;
  @override
  String? get currentSongId => null;
  @override
  String? get currentLyric => null;
  @override
  ProbeTrack? current = const ProbeTrack(
    location: 'test://song',
    name: 'sample.flac',
  );
  @override
  TrackMetadata? metadata = const TrackMetadata(title: '测试曲目', artist: '测试艺术家');
  @override
  String? error;
  @override
  String? playbackNotice;
  @override
  bool busy = false;
  @override
  bool changingTrack = false;
  @override
  List<ProbeTrack> tracks = [];
  @override
  List<String> roots = [];
  @override
  bool notificationsEnabled = false;
  @override
  bool requestingNotifications = false;
  @override
  String? notificationMessage;
  int requests = 0;
  int settingsOpened = 0;
  bool grantPermission = true;

  @override
  Future<void> requestNotificationPermission() async {
    requests++;
    notificationsEnabled = grantPermission;
    notifyListeners();
  }

  @override
  Future<void> openNotificationSettings() async {
    settingsOpened++;
  }

  void emit(PlayerState state) {
    player.state = state;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused fake controller method');
}

class TransitionStreams implements PlayerStream {
  final changes = StreamController<bool>.broadcast(sync: true);
  final failures = StreamController<String>.broadcast(sync: true);
  @override
  Stream<bool> get playing => changes.stream;
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<String> get error => failures.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused fake stream');
}

class TransitionPlayer extends HandlerPlayer {
  @override
  final TransitionStreams stream = TransitionStreams();
  Completer<void>? playGate;
  final commands = <String>[];
  int stops = 0;

  @override
  Future<void> stop() async {
    stops++;
    state = PlayerState();
    stream.changes.add(false);
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    state = state.copyWith(
      playlist: Playlist([playable as Media]),
      duration: const Duration(seconds: 24),
    );
    stream.changes.add(false);
  }

  @override
  Future<void> play() async {
    commands.add('play');
    await playGate?.future;
    state = state.copyWith(playing: true);
    stream.changes.add(true);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    state = state.copyWith(playing: false);
    stream.changes.add(false);
  }

  @override
  Future<void> dispose() async {
    await stream.changes.close();
    await stream.failures.close();
  }
}

class TransitionDocuments extends DocumentAccess {
  TransitionDocuments({bool android = false}) : super(android: android);
  Completer<TrackMetadata>? metadataGate;
  final descriptors = <int>{};
  int nextDescriptor = 20;
  @override
  Future<int> open(String uri) async {
    final descriptor = nextDescriptor++;
    descriptors.add(descriptor);
    return descriptor;
  }

  @override
  Future<void> close(int descriptor) async => descriptors.remove(descriptor);
  @override
  Future<Map<Object?, Object?>> diagnostics() async => {
    'managedDescriptors': descriptors.length,
  };
  @override
  Future<TrackMetadata> metadata(ProbeTrack track) async =>
      await metadataGate?.future ??
      const TrackMetadata(title: '完整标题', artist: '完整歌手');
}

void main() {
  testWidgets(
    'decoder failure stops stale playback and retry reopens the track',
    (tester) async {
      final player = TransitionPlayer();
      final documents = TransitionDocuments(android: true);
      final controller = PlaybackController(player, documents)
        ..tracks = [
          const ProbeTrack(location: 'test://first', name: 'first.flac'),
        ];
      final handler = TagAudioHandler(controller);
      await controller.select(0);
      expect(documents.descriptors, hasLength(1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackProvider.overrideWithValue(controller)],
          child: const MaterialApp(home: Scaffold(body: PlaybackPage())),
        ),
      );
      // The native decoder can report failure without resetting its playing flag.
      player.stream.failures.add('Failed to recognize file format.');
      expect(player.state.playing, isTrue);
      expect(controller.playing, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.error,
      );
      expect(
        handler.playbackState.value.controls[1].label,
        MediaControl.play.label,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('播放'), findsOneWidget);
      expect(player.state.playlist.medias, isEmpty);
      expect(documents.descriptors, isEmpty);
      expect(controller.error, contains('Failed to recognize'));
      await tester.tap(find.byTooltip('播放'));
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(controller.playing, isTrue);
      expect(documents.descriptors, hasLength(1));
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(controller.shutdown);
      expect(documents.descriptors, isEmpty);
    },
  );

  test(
    'queued track replacement survives cleanup from the failed selection',
    () async {
      final player = TransitionPlayer();
      final controller = PlaybackController(player, TransitionDocuments())
        ..tracks = [
          const ProbeTrack(location: 'test://first', name: 'first.flac'),
          const ProbeTrack(location: 'test://second', name: 'second.flac'),
        ];
      addTearDown(controller.shutdown);
      await controller.select(0);
      final replacement = controller.next();
      player.stream.failures.add('decoder failure');
      await replacement;
      // Enqueued after cleanup, so this also waits for its generation guard.
      await controller.play();
      expect(controller.current?.name, 'second.flac');
      expect(controller.error, isNull);
      expect(controller.playing, isTrue);
      expect(
        player.stops,
        2,
        reason: 'Only the two selections should stop playback',
      );
    },
  );

  test('switch never publishes idle or partial new metadata', () async {
    final player = TransitionPlayer();
    final documents = TransitionDocuments();
    final controller = PlaybackController(player, documents)
      ..tracks = [
        const ProbeTrack(location: 'test://first', name: 'first.flac'),
        const ProbeTrack(location: 'test://second', name: 'second.flac'),
      ];
    final handler = TagAudioHandler(controller);
    addTearDown(controller.shutdown);
    await controller.select(0);
    final states = <PlaybackState>[];
    final items = <MediaItem?>[];
    final stateSubscription = handler.playbackState.listen(states.add);
    final itemSubscription = handler.mediaItem.listen(items.add);
    addTearDown(stateSubscription.cancel);
    addTearDown(itemSubscription.cancel);
    await Future<void>.delayed(Duration.zero);
    documents.metadataGate = Completer<TrackMetadata>();
    final switching = handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(controller.changingTrack, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.loading,
    );
    expect(handler.mediaItem.value?.id, 'test://first');
    documents.metadataGate!.complete(
      const TrackMetadata(title: '第二首完整标题', artist: '第二首歌手'),
    );
    await switching;
    await Future<void>.delayed(Duration.zero);
    expect(
      states.every((s) => s.processingState != AudioProcessingState.idle),
      isTrue,
    );
    final secondItems = items.where((i) => i?.id == 'test://second').toList();
    expect(secondItems, hasLength(1));
    expect(secondItems.single?.title, '第二首完整标题');
    expect(secondItems.single?.displaySubtitle, '第二首歌手');
    expect(handler.playbackState.value.playing, isTrue);
    await handler.pause();
    expect(handler.playbackState.value.playing, isFalse);
    await handler.play();
    expect(handler.playbackState.value.playing, isTrue);
    await handler.stop();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test(
    'two hardware clicks during delayed play execute as play then pause',
    () async {
      final player = TransitionPlayer();
      final controller = PlaybackController(player, TransitionDocuments())
        ..tracks = [
          const ProbeTrack(location: 'test://first', name: 'first.flac'),
        ];
      player.state = player.state.copyWith(playing: false);
      final handler = TagAudioHandler(controller);
      addTearDown(controller.shutdown);
      player.playGate = Completer<void>();
      final first = handler.click();
      final second = handler.click();
      await Future<void>.delayed(Duration.zero);
      expect(player.commands, ['play']);
      player.playGate!.complete();
      await Future.wait([first, second]);
      expect(player.commands, ['play', 'pause']);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.controls[1].action,
        MediaAction.playPause,
      );
      expect(
        handler.playbackState.value.controls[1].androidIcon,
        MediaControl.play.androidIcon,
      );
    },
  );

  test(
    'notification uses standard toggle transport with truthful play/pause icon',
    () {
      final controller = HandlerController();
      final handler = TagAudioHandler(controller);
      addTearDown(controller.dispose);
      expect(
        handler.playbackState.value.controls[1].action,
        MediaAction.playPause,
      );
      expect(
        handler.playbackState.value.controls[1].androidIcon,
        MediaControl.pause.androidIcon,
      );
      expect(
        handler.playbackState.value.controls[1].label,
        MediaControl.pause.label,
      );
      controller.emit(controller.player.state.copyWith(playing: false));
      expect(
        handler.playbackState.value.controls[1].action,
        MediaAction.playPause,
      );
      expect(
        handler.playbackState.value.controls[1].androidIcon,
        MediaControl.play.androidIcon,
      );
      expect(
        handler.playbackState.value.controls[1].label,
        MediaControl.play.label,
      );
    },
  );

  testWidgets(
    'natural progress does not repost metadata; seek, pause and error still publish',
    (tester) async {
      final controller = HandlerController();
      final handler = TagAudioHandler(controller);
      final states = <dynamic>[];
      final items = <dynamic>[];
      final stateSubscription = handler.playbackState.listen(states.add);
      final itemSubscription = handler.mediaItem.listen(items.add);
      addTearDown(stateSubscription.cancel);
      addTearDown(itemSubscription.cancel);
      addTearDown(controller.dispose);
      await tester.pump();
      expect(states.length, 1);
      expect(items.length, 1);
      for (var i = 1; i <= 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        controller.emit(
          controller.player.state.copyWith(
            position: Duration(milliseconds: i * 100),
          ),
        );
        await tester.pump();
      }
      expect(
        items.length,
        1,
        reason: 'Progress must not repeatedly post unchanged metadata',
      );
      expect(
        states.length,
        1,
        reason:
            'System clients project normal progress using the playback clock',
      );
      controller.emit(
        controller.player.state.copyWith(position: const Duration(seconds: 12)),
      );
      await tester.pump();
      expect(states.length, 2);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );
      controller.emit(controller.player.state.copyWith(playing: false));
      await tester.pump();
      expect(states.length, 3);
      expect(handler.playbackState.value.playing, isFalse);
      controller.error = 'fixture error';
      controller.notifyListeners();
      await tester.pump();
      expect(states.length, 4);
      expect(handler.playbackState.value.errorMessage, 'fixture error');
    },
  );

  for (final allowed in [true, false]) {
    testWidgets(
      'notification permission is requested only by user action; grant=$allowed',
      (tester) async {
        final controller = HandlerController()
          ..current = null
          ..grantPermission = allowed;
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackProvider.overrideWithValue(controller)],
            child: const MaterialApp(home: Scaffold(body: PlaybackPage())),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.requests, 0);
        expect(find.text('开启播放通知'), findsOneWidget);
        await tester.tap(find.text('通知设置'));
        await tester.pumpAndSettle();
        expect(controller.settingsOpened, 1);
        expect(controller.requests, 0);
        await tester.tap(find.text('开启播放通知'));
        await tester.pumpAndSettle();
        expect(controller.requests, 1);
        expect(find.text('开启播放通知'), allowed ? findsNothing : findsOneWidget);
        expect(find.textContaining('让音乐有自己的归属'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
