import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'documents.dart';

final playbackProvider = Provider<PlaybackController?>((ref) => null);

class PlaybackController extends ChangeNotifier {
  PlaybackController(this.player, this.documents) {
    _subscriptions.addAll([
      player.stream.playing.listen((_) => _publish()),
      player.stream.position.listen((_) => _publish()),
      player.stream.duration.listen((_) => _publish()),
      player.stream.buffering.listen((_) => _publish()),
      player.stream.completed.listen((completed) {
        _publish();
        if (completed &&
            !_playbackFailed &&
            !changingTrack &&
            index + 1 < tracks.length) {
          unawaited(next());
        }
      }),
      player.stream.error.listen((message) {
        _playbackFailed = true;
        error = '播放失败：$message。可选择其他歌曲重试。';
        final failedSelection = _selection;
        debugPrint(
          'R1 ${jsonEncode({'event': 'playbackError', 'message': message})}',
        );
        _publish();
        // A decoder error may leave media_kit's playing flag true. Publish the
        // failure immediately, then release this selection in the serial lane.
        // A queued replacement must never be stopped by stale error cleanup.
        unawaited(
          _serial(() async {
            if (_selection != failedSelection || !_playbackFailed) return;
            await _unload();
            await session?.setActive(false);
          }),
        );
      }),
    ]);
  }

  final Player player;
  final DocumentAccess documents;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<ProbeTrack> tracks = [];
  List<String> roots = [];
  int index = -1;
  int? _playbackFd;
  TrackMetadata? metadata;
  AudioSession? session;
  String? error;
  String? metadataWarning;
  bool busy = false;
  bool changingTrack = false;
  bool notificationsEnabled = true;
  bool requestingNotifications = false;
  String? notificationMessage;
  bool _closed = false;
  bool _playbackFailed = false;
  int _selection = 0;
  bool get playing => !_playbackFailed && player.state.playing;
  Future<void> _pending = Future.value();
  ProbeTrack? get current =>
      index >= 0 && index < tracks.length ? tracks[index] : null;

  void _publish() {
    if (!_closed) notifyListeners();
  }

  // All transitions (including notification callbacks) share one serial lane.
  // At most one playback descriptor and one metadata descriptor are held.
  Future<void> _serial(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (_closed) return;
      try {
        await action();
      } catch (e) {
        error = '操作失败：$e';
      } finally {
        _publish();
      }
    });
    _pending = result;
    return result;
  }

  Future<void> initialize() async {
    if (Platform.isAndroid) {
      session = await AudioSession.instance;
      await session!.configure(const AudioSessionConfiguration.music());
      _subscriptions.add(
        session!.interruptionEventStream.listen((event) {
          if (event.begin) unawaited(pause());
        }),
      );
      _subscriptions.add(
        session!.becomingNoisyEventStream.listen((_) => unawaited(pause())),
      );
    }
    roots = await documents.roots();
    await refreshNotificationPermission();
    _publish();
  }

  Future<void> refreshNotificationPermission() async {
    if (!documents.android || _closed) return;
    try {
      notificationsEnabled = await documents.notificationsEnabled();
      if (notificationsEnabled) notificationMessage = null;
    } catch (_) {
      notificationMessage = '无法检查播放通知，请在系统通知设置中查看。';
    }
    _publish();
  }

  Future<void> requestNotificationPermission() async {
    if (requestingNotifications) return;
    requestingNotifications = true;
    _publish();
    try {
      notificationsEnabled = await documents.requestNotifications();
      notificationMessage = notificationsEnabled
          ? null
          : '通知尚未开启，可在通知设置中允许播放通知和锁屏显示。';
    } catch (_) {
      notificationMessage = '通知授权未完成，请重试或打开通知设置。';
    } finally {
      requestingNotifications = false;
      _publish();
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await documents.openNotificationSettings();
    } catch (_) {
      notificationMessage = '无法打开通知设置，请在手机系统设置中找到 Tag Music。';
      _publish();
    }
  }

  Future<void> chooseDirectory() async {
    if (busy) return;
    busy = true;
    error = null;
    _publish();
    try {
      final root = await documents.pickDirectory();
      roots = await documents.roots();
      if (root != null) await _loadDirectory(root);
    } catch (e) {
      error = '目录读取失败：$e。原测试列表仍保留，请重试或重新授权。';
    } finally {
      busy = false;
      _publish();
    }
  }

  Future<void> refresh(String root) async {
    if (busy) return;
    busy = true;
    error = null;
    _publish();
    try {
      await _loadDirectory(root);
    } catch (e) {
      error = '目录不可访问：$e。原测试列表仍保留，请重新授权。';
    } finally {
      busy = false;
      _publish();
    }
  }

  Future<void> _loadDirectory(String root) async {
    final loaded = await documents.list(root);
    await _serial(() async {
      _selection++;
      _playbackFailed = false;
      await _unload();
      tracks = loaded;
      index = -1;
      metadata = null;
      metadataWarning = null;
    });
  }

  Future<void> select(int target) => _serial(() => _select(target));

  // Search, sorting and rescanning never mutate this playback snapshot.
  Future<void> playSnapshot(List<ProbeTrack> snapshot, int target) =>
      _serial(() async {
        if (target < 0 || target >= snapshot.length) return;
        tracks = List.unmodifiable(snapshot);
        await _select(target);
      });

  Future<void> _select(int target) async {
    if (target < 0 || target >= tracks.length) return;
    _selection++;
    _playbackFailed = false;
    changingTrack = true;
    error = null;
    metadataWarning = null;
    _publish();
    try {
      await _unload();
      index = target;
      metadata = null;
      final track = tracks[target];
      try {
        metadata = await documents.metadata(track);
        debugPrint(
          'R1 ${jsonEncode({'event': 'metadata', 'name': track.name, 'title': metadata?.title, 'artist': metadata?.artist})}',
        );
      } catch (e) {
        metadataWarning = '元数据不可读，使用文件名：$e';
      }
      final location = documents.android
          ? 'fd://${_playbackFd = await documents.open(track.location)}'
          : track.location;
      await player.open(Media(location), play: false);
      if (!_playbackFailed) await _play();
      debugPrint(
        'R1 ${jsonEncode({'event': 'opened', 'name': track.name, 'diagnostics': await documents.diagnostics()})}',
      );
    } catch (_) {
      await _unload();
      rethrow;
    } finally {
      changingTrack = false;
      _publish();
    }
  }

  Future<void> _unload() async {
    await player.stop();
    final fd = _playbackFd;
    if (fd != null) {
      await documents.close(fd);
      _playbackFd = null;
      debugPrint(
        'R1 ${jsonEncode({'event': 'descriptorClosed', 'diagnostics': await documents.diagnostics()})}',
      );
    }
  }

  Future<void> _play() async {
    if (session != null && !await session!.setActive(true)) {
      throw StateError('系统未授予音频焦点，请稍后重试');
    }
    if (player.state.completed) await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> play() => _serial(() async {
    await _resume();
  });

  Future<void> _resume() async {
    if (current == null) return;
    if (_playbackFailed || player.state.playlist.medias.isEmpty) {
      await _select(index);
    } else {
      await _play();
    }
  }

  Future<void> _pause() async {
    await player.pause();
    await session?.setActive(false);
  }

  Future<void> pause() => _serial(_pause);

  // Decide at execution time, after any queued switch or earlier click.
  Future<void> togglePlayPause() => _serial(() async {
    if (playing) {
      await _pause();
    } else {
      await _resume();
    }
  });
  Future<void> stop() => _serial(() async {
    _selection++;
    _playbackFailed = false;
    error = null;
    await _unload();
    await session?.setActive(false);
  });
  Future<void> next() => _serial(() => _select(index + 1));
  Future<void> previous() => _serial(() => _select(index - 1));
  Future<void> seek(Duration position) => _serial(() async {
    final milliseconds = position.inMilliseconds.clamp(
      0,
      player.state.duration.inMilliseconds,
    );
    await player.seek(Duration(milliseconds: milliseconds));
  });

  Future<void> shutdown() async {
    await _pending;
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _unload();
    await session?.setActive(false);
    await player.dispose();
    super.dispose();
  }
}

class TagAudioHandler extends BaseAudioHandler {
  TagAudioHandler(this.controller) {
    controller.addListener(_broadcast);
    _broadcast();
  }
  final PlaybackController controller;
  MediaItem? _lastMediaItem;
  bool _sentState = false;

  void _broadcast() {
    final current = controller.current;
    final state = controller.player.state;
    final previous = playbackState.value;
    var mediaChanged = false;
    // Keep the last complete title/artist during stop -> read -> open. Publishing
    // a filename-only item here makes the native card change its text layout.
    if (!controller.changingTrack && current != null) {
      final title = controller.metadata?.title ?? current.name;
      final item = MediaItem(
        id: current.location,
        title: title,
        artist: controller.metadata?.artist,
        album: controller.metadata?.album,
        displayTitle: title,
        displaySubtitle: controller.metadata?.artist,
        displayDescription: controller.metadata?.album,
        duration: state.duration > Duration.zero
            ? state.duration
            : controller.metadata?.duration,
      );
      if (_lastMediaItem?.id != item.id ||
          _lastMediaItem?.title != item.title ||
          _lastMediaItem?.artist != item.artist ||
          _lastMediaItem?.album != item.album ||
          _lastMediaItem?.duration != item.duration) {
        _lastMediaItem = item;
        mediaItem.add(item);
        mediaChanged = true;
      }
    } else if (!controller.changingTrack &&
        current == null &&
        _lastMediaItem != null) {
      _lastMediaItem = null;
      mediaItem.add(null);
      mediaChanged = true;
    }
    // audio_service tears down the native service on idle. A track transition
    // must remain loading until the replacement player and metadata are ready.
    final processing = controller.changingTrack
        ? AudioProcessingState.loading
        : controller.error != null
        ? AudioProcessingState.error
        : state.playlist.medias.isEmpty
        ? AudioProcessingState.idle
        : state.completed
        ? AudioProcessingState.completed
        : state.buffering
        ? AudioProcessingState.buffering
        : AudioProcessingState.ready;
    final playing = controller.changingTrack && controller.error == null
        ? previous.playing
        : controller.playing;
    if (_sentState &&
        !mediaChanged &&
        previous.playing == playing &&
        previous.processingState == processing &&
        previous.speed == state.rate &&
        previous.errorMessage == controller.error &&
        (previous.position - state.position).inMilliseconds.abs() < 500 &&
        (previous.bufferedPosition - state.buffer).inMilliseconds.abs() < 500) {
      return;
    }
    _sentState = true;
    debugPrint(
      'R1 ${jsonEncode({'event': 'mediaState', 'processing': processing.name, 'playing': playing, 'changingTrack': controller.changingTrack, 'name': current?.name, 'title': _lastMediaItem?.title, 'artist': _lastMediaItem?.artist, 'position': state.position.inMilliseconds})}',
    );
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          // audio_service maps separate play to KEYCODE_MUTE, which Android's
          // MediaController filters out. The standard toggle key is supported
          // and click() decides against the serialized, actual player state.
          (playing ? MediaControl.pause : MediaControl.play).copyWith(
            action: MediaAction.playPause,
          ),
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processing,
        playing: playing,
        updatePosition: state.position,
        bufferedPosition: state.buffer,
        speed: state.rate,
        errorCode: controller.error == null ? null : 1,
        errorMessage: controller.error,
      ),
    );
  }

  @override
  Future<void> play() => _command('play', controller.play);
  @override
  Future<void> pause() => _command('pause', controller.pause);
  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      switch (button) {
        MediaButton.media => _command('toggle', controller.togglePlayPause),
        MediaButton.next => skipToNext(),
        MediaButton.previous => skipToPrevious(),
      };
  @override
  Future<void> seek(Duration position) => controller.seek(position);
  @override
  Future<void> stop() => _command('stop', controller.stop);
  @override
  Future<void> skipToNext() => _command('next', controller.next);
  @override
  Future<void> skipToPrevious() => _command('previous', controller.previous);
  @override
  Future<void> onTaskRemoved() => stop();

  Future<void> _command(String name, Future<void> Function() action) async {
    final timer = Stopwatch()..start();
    debugPrint(
      'R1 ${jsonEncode({'event': 'mediaCommand', 'command': name, 'phase': 'received'})}',
    );
    await action();
    debugPrint(
      'R1 ${jsonEncode({'event': 'mediaCommand', 'command': name, 'phase': 'completed', 'elapsedMs': timer.elapsedMilliseconds, 'playing': controller.playing, 'backendPlaying': controller.player.state.playing, 'error': controller.error})}',
    );
  }
}
