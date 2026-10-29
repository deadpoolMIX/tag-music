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
        if (completed && index + 1 < tracks.length) unawaited(next());
      }),
      player.stream.error.listen((message) {
        error = '播放失败：$message。可选择其他歌曲重试。';
        debugPrint(
          'R1 ${jsonEncode({'event': 'playbackError', 'message': message})}',
        );
        _publish();
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
  bool _closed = false;
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
    _publish();
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
      await _unload();
      tracks = loaded;
      index = -1;
      metadata = null;
      metadataWarning = null;
    });
  }

  Future<void> select(int target) => _serial(() => _select(target));

  Future<void> _select(int target) async {
    if (target < 0 || target >= tracks.length) return;
    error = null;
    metadataWarning = null;
    await _unload();
    index = target;
    metadata = null;
    _publish();
    final track = tracks[target];
    try {
      metadata = await documents.metadata(track);
      debugPrint(
        'R1 ${jsonEncode({'event': 'metadata', 'name': track.name, 'title': metadata?.title, 'artist': metadata?.artist})}',
      );
    } catch (e) {
      metadataWarning = '元数据不可读，使用文件名：$e';
    }
    try {
      final location = documents.android
          ? 'fd://${_playbackFd = await documents.open(track.location)}'
          : track.location;
      await player.open(Media(location), play: false);
      await _play();
      debugPrint(
        'R1 ${jsonEncode({'event': 'opened', 'name': track.name, 'diagnostics': await documents.diagnostics()})}',
      );
    } catch (_) {
      await _unload();
      rethrow;
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
    if (current == null) return;
    if (player.state.playlist.medias.isEmpty) {
      await _select(index);
    } else {
      await _play();
    }
  });

  Future<void> pause() => _serial(() async {
    await player.pause();
    await session?.setActive(false);
  });
  Future<void> stop() => _serial(() async {
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

  void _broadcast() {
    final current = controller.current;
    final state = controller.player.state;
    if (current != null) {
      mediaItem.add(
        MediaItem(
          id: current.location,
          title: controller.metadata?.title ?? current.name,
          artist: controller.metadata?.artist,
          album: controller.metadata?.album,
          duration: state.duration > Duration.zero
              ? state.duration
              : controller.metadata?.duration,
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          state.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 3],
        processingState: controller.error != null
            ? AudioProcessingState.error
            : state.playlist.medias.isEmpty
            ? AudioProcessingState.idle
            : state.completed
            ? AudioProcessingState.completed
            : state.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: state.playing,
        updatePosition: state.position,
        bufferedPosition: state.buffer,
        speed: state.rate,
        errorCode: controller.error == null ? null : 1,
        errorMessage: controller.error,
      ),
    );
  }

  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> seek(Duration position) => controller.seek(position);
  @override
  Future<void> stop() => controller.stop();
  @override
  Future<void> skipToNext() => controller.next();
  @override
  Future<void> skipToPrevious() => controller.previous();
  @override
  Future<void> onTaskRemoved() => stop();
}
