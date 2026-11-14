import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'documents.dart';
import 'lyrics.dart';
import 'sleep_countdown.dart';
import 'playback_queue.dart';

export 'playback_queue.dart'
    show PlaybackMode, PlaybackQueue, QueueEntry, QueueSong;

final playbackProvider = Provider<PlaybackController?>((ref) => null);

class _AudioFocusDenied implements Exception {
  @override
  String toString() => '系统未授予音频焦点，请稍后重试';
}

class PlaybackController extends ChangeNotifier {
  PlaybackController(
    this.player,
    this.documents, {
    PlaybackQueue? playbackQueue,
    Duration Function()? sleepClock,
    SleepSchedule? sleepSchedule,
  }) : queue = playbackQueue ?? PlaybackQueue() {
    sleep = SleepCountdown(
      clock: sleepClock ?? (() => _sleepWatch.elapsed),
      schedule: sleepSchedule ?? scheduleSleepWakeup,
      onWake: (token) => _scheduleSleepDeadline(token),
    );
    lyrics.addListener(_publish);
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
            _playIntent &&
            _completionHandled != _selection) {
          final selection = _selection;
          _completionHandled = selection;
          unawaited(
            _serial(() async {
              if (_selection == selection && _playIntent) {
                await _advance(natural: true);
              }
            }),
          );
        }
      }),
      player.stream.error.listen((message) {
        _playbackFailed = true;
        error = '播放失败：$message。可选择其他歌曲重试。';
        final failedSelection = _selection;
        final failedEntry = queue.current?.entryId;
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
            if (await _sleepBlocksSwitch()) return;
            if (failedEntry != null) _failedEntries.add(failedEntry);
            playbackNotice = error;
            await _unload();
            await session?.setActive(false);
            final nextEntry = queue.next(excluded: _failedEntries);
            if (nextEntry != null) {
              await _openCurrent(play: _playIntent, resetFailures: false);
            } else {
              _playIntent = false;
            }
          }),
        );
      }),
    ]);
  }

  final _sleepWatch = Stopwatch()..start();
  late final SleepCountdown sleep;
  int? _sleepDeadlineQueued;
  bool get _countSleep =>
      _playIntent &&
      playing &&
      !player.state.buffering &&
      !player.state.completed &&
      !changingTrack &&
      player.state.playlist.medias.isNotEmpty;

  void _observeSleep() {
    sleep.update(counting: _countSleep, entryId: queue.current?.entryId);
    if (sleep.waitingForEnd && (!playing || _playbackFailed || !_playIntent)) {
      _scheduleSleepDeadline(sleep.generation);
    }
  }

  void _scheduleSleepDeadline(int token) {
    if (_closed || token != sleep.generation || _sleepDeadlineQueued == token) {
      return;
    }
    _sleepDeadlineQueued = token;
    unawaited(
      _serial(() async {
        if (_sleepDeadlineQueued == token) _sleepDeadlineQueued = null;
        if (token != sleep.generation) return;
        sleep.update(counting: _countSleep, entryId: queue.current?.entryId);
        if (sleep.waitingForEnd &&
            (!playing ||
                _playbackFailed ||
                !_playIntent ||
                queue.current?.entryId != sleep.lockedEntryId)) {
          await _finishSleep();
        }
      }),
    );
  }

  Future<void> setSleepTimer(Duration duration) => _serial(() async {
    sleep.start(duration);
    _sleepDeadlineQueued = null;
    _observeSleep();
  });
  Future<void> cancelSleepTimer() => _serial(() async {
    sleep.cancel();
    _sleepDeadlineQueued = null;
  });
  Future<void> _finishSleep() async {
    sleep.cancel();
    _sleepDeadlineQueued = null;
    await _stopPlayback();
    playbackNotice = '睡眠定时已结束';
  }

  Future<bool> _sleepBlocksSwitch() async {
    _observeSleep();
    if (!sleep.waitingForEnd) return false;
    await _finishSleep();
    return true;
  }

  final lyrics = LyricsTimeline();
  bool simpleLayout = false;
  void toggleLayout() {
    simpleLayout = !simpleLayout;
    _publish();
  }

  String? get currentLyric {
    final index = lyrics.value.indexAt(player.state.position);
    return index < 0 ? null : lyrics.value.lines[index].original;
  }

  final Player player;
  final DocumentAccess documents;
  final PlaybackQueue queue;
  FutureOr<ProbeTrack?> Function(String songId)? resolveSong;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  List<ProbeTrack> _tracks = const [];
  List<ProbeTrack> get tracks => _tracks;
  // Only the standalone directory probe/test path uses transient locator IDs.
  // Product entrypoints call playSongs with persistent library UUIDs.
  set tracks(List<ProbeTrack> value) {
    _diagnosticQueue = true;
    queue.replace(
      value
          .map((t) => QueueSong(songId: 'probe:${t.location}', track: t))
          .toList(),
      0,
    );
    _syncTracks();
  }

  List<String> roots = [];
  int get index => queue.index;
  int? _playbackFd;
  TrackMetadata? metadata;
  AudioSession? session;
  String? error;
  String? metadataWarning;
  String? playbackNotice;
  bool busy = false;
  bool changingTrack = false;
  bool notificationsEnabled = true;
  bool requestingNotifications = false;
  String? notificationMessage;
  bool _closed = false;
  bool _playbackFailed = false;
  int _selection = 0;
  int _completionHandled = -1;
  bool _playIntent = false;
  bool _diagnosticQueue = false;
  final Set<String> _failedEntries = {};
  ProbeTrack? _resolvedTrack;
  String? _resolvedEntryId;
  bool get playing => !_playbackFailed && player.state.playing;
  bool get playbackFailed => _playbackFailed;
  bool get canSeek =>
      current != null &&
      !changingTrack &&
      !_playbackFailed &&
      player.state.playlist.medias.isNotEmpty &&
      player.state.duration > Duration.zero;
  bool get sleepCounting => sleep.active && !sleep.waitingForEnd && _countSleep;
  bool get canNext => queue.canNext;
  bool get canPrevious => queue.canPrevious;
  String? get currentSongId =>
      _diagnosticQueue ? null : queue.current?.song.songId;
  Future<void> _pending = Future.value();
  ProbeTrack? get current => queue.current?.entryId == _resolvedEntryId
      ? _resolvedTrack
      : queue.current?.song.track;

  void _syncTracks() => _tracks = List.unmodifiable(
    queue.entries.map((entry) => entry.song.track),
  );

  void _publish() {
    if (!_closed) {
      _observeSleep();
      notifyListeners();
    }
  }

  // All transitions (including notification callbacks) share one serial lane.
  // At most one playback descriptor and one metadata descriptor are held.
  Future<void> _serial(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (_closed) return;
      try {
        _observeSleep();
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
      if (await _sleepBlocksSwitch()) return;
      _selection++;
      _playbackFailed = false;
      await _unload();
      tracks = loaded;
      metadata = null;
      metadataWarning = null;
    });
  }

  Future<void> select(int target) => _serial(() => _select(target));

  Future<void> selectEntry(String entryId) => _serial(() async {
    final target = queue.entries.indexWhere((e) => e.entryId == entryId);
    if (target >= 0) await _select(target);
  });

  // Search, sorting and rescanning never mutate this playback snapshot.
  Future<void> playSongs(List<QueueSong> snapshot, int target) =>
      _serial(() async {
        if (target < 0 || target >= snapshot.length) return;
        if (await _sleepBlocksSwitch()) return;
        _diagnosticQueue = false;
        queue.replace(snapshot, target);
        _syncTracks();
        await _openCurrent(play: true);
      });

  Future<void> addToQueue(List<QueueSong> songs) => _serial(() async {
    if (queue.entries.isEmpty) _diagnosticQueue = false;
    queue.add(songs);
    _syncTracks();
  });

  Future<void> setMode(PlaybackMode mode) => _serial(() async {
    queue.setMode(mode);
    _syncTracks();
  });

  Future<void> reorderQueue(List<String> orderedIds) => _serial(() async {
    queue.reorder(orderedIds);
    _syncTracks();
  });

  Future<void> removeFromQueue(String entryId) => _serial(() async {
    final wasCurrent = queue.current?.entryId == entryId;
    final wasPlaying = playing;
    if (wasCurrent && await _sleepBlocksSwitch()) return;
    queue.remove(entryId);
    _syncTracks();
    if (!wasCurrent) return;
    if (queue.current != null) {
      await _openCurrent(play: wasPlaying);
    } else {
      await _clearMedia();
    }
  });

  Future<void> clearQueue() => _serial(() async {
    await _clearMedia();
    queue.clear();
    _syncTracks();
  });

  Future<void> _clearMedia() async {
    lyrics.clear();
    _selection++;
    _playIntent = false;
    _playbackFailed = false;
    await _unload();
    await session?.setActive(false);
    _resolvedTrack = null;
    _resolvedEntryId = null;
    metadata = null;
    metadataWarning = null;
    error = null;
    playbackNotice = null;
  }

  Future<void> _select(int target) async {
    if (target < 0 || target >= tracks.length) return;
    if (await _sleepBlocksSwitch()) return;
    queue.select(queue.entries[target].entryId);
    await _openCurrent(play: true);
  }

  Future<void> _openCurrent({
    required bool play,
    bool resetFailures = true,
  }) async {
    _syncTracks();
    if (resetFailures) {
      _failedEntries.clear();
      playbackNotice = null;
    }
    _playIntent = play;
    changingTrack = true;
    _publish();
    try {
      while (queue.current != null) {
        final entry = queue.current!;
        lyrics.clear();
        _selection++;
        _playbackFailed = false;
        error = null;
        metadataWarning = null;
        try {
          await _unload();
          metadata = null;
          final track = !_diagnosticQueue && resolveSong != null
              ? await resolveSong!(entry.song.songId)
              : entry.song.track;
          if (track == null) throw StateError('文件失联或目录不可访问');
          _resolvedEntryId = entry.entryId;
          _resolvedTrack = track;
          unawaited(lyrics.load(() => documents.lyrics(track)));
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
          if (_playbackFailed) throw StateError(error ?? '播放失败');
          if (play) {
            await _play();
          } else {
            await session?.setActive(false);
          }
          if (_playbackFailed) throw StateError(error ?? '播放失败');
          debugPrint(
            'R1 ${jsonEncode({'event': 'opened', 'name': track.name, 'diagnostics': await documents.diagnostics()})}',
          );
          return;
        } catch (e) {
          if (e is _AudioFocusDenied) {
            _selection++;
            _playIntent = false;
            _playbackFailed = true;
            error = e.toString();
            await _unload();
            await session?.setActive(false);
            return;
          }
          _failedEntries.add(entry.entryId);
          error = '播放失败：$e';
          playbackNotice = '已跳过不可播放歌曲：${entry.song.track.name}。$e';
          await _unload();
          await session?.setActive(false);
          if (await _sleepBlocksSwitch()) return;
          if (queue.next(excluded: _failedEntries) == null) {
            _selection++; // Invalidate queued decoder cleanup for this attempt.
            _playbackFailed = true;
            _playIntent = false;
            error = '$error。没有可继续播放的歌曲，可修复后重试。';
            return;
          }
        }
      }
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
      _playIntent = false;
      throw _AudioFocusDenied();
    }
    error = null;
    if (player.state.completed) await player.seek(Duration.zero);
    _playIntent = true;
    _completionHandled = -1;
    await player.play();
  }

  Future<void> play() => _serial(() async {
    await _resume();
  });

  Future<void> _resume() async {
    if (current == null) return;
    _observeSleep();
    if (sleep.waitingForEnd) {
      if (!playing || _playbackFailed || player.state.playlist.medias.isEmpty) {
        await _finishSleep();
      }
      return;
    }
    if (_playbackFailed || player.state.playlist.medias.isEmpty) {
      await _openCurrent(play: true);
    } else {
      await _play();
    }
  }

  Future<void> _pause() async {
    _playIntent = false;
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
  Future<void> stop() => _serial(_stopPlayback);
  Future<void> _stopPlayback() async {
    _selection++;
    _playbackFailed = false;
    error = null;
    _playIntent = false;
    await _unload();
    await session?.setActive(false);
  }

  Future<void> _advance({bool natural = false}) async {
    if (await _sleepBlocksSwitch()) return;
    if (queue.next(natural: natural) != null) {
      await _openCurrent(play: true);
    } else if (natural) {
      _playIntent = false;
      await _unload();
      await session?.setActive(false);
    }
  }

  Future<void> next() => _serial(() => _advance());
  Future<void> previous() => _serial(() async {
    if (await _sleepBlocksSwitch()) return;
    if (queue.previous() != null) await _openCurrent(play: true);
  });
  Future<void> seek(Duration position, {String? expectedEntryId}) =>
      _serial(() async {
        if (expectedEntryId != null &&
            queue.current?.entryId != expectedEntryId) {
          return;
        }
        final milliseconds = position.inMilliseconds.clamp(
          0,
          player.state.duration.inMilliseconds,
        );
        await player.seek(Duration(milliseconds: milliseconds));
      });

  Future<void> shutdown() async {
    await _pending;
    _closed = true;
    sleep.dispose();
    _sleepWatch.stop();
    lyrics.removeListener(_publish);
    lyrics.dispose();
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
        id: controller.currentSongId ?? current.location,
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
