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
  final HandlerPlayer player = HandlerPlayer();
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
  bool busy = false;
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

void main() {
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
