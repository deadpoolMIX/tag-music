import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_controller.dart';
import 'package:tag_music/playback/sleep_countdown.dart';

import 'audio_handler_test.dart' show TransitionDocuments;
import 'queue_playback_test.dart' show QueuePlayer, song;

class _Wake {
  _Wake(this.callback);
  final void Function() callback;
  bool cancelled = false;
}

class _Clock {
  Duration elapsed = Duration.zero;
  final wakes = <_Wake>[];
  Duration now() => elapsed;
  void advance(Duration value) {
    elapsed += value;
  }

  void Function() schedule(Duration delay, void Function() callback) {
    final wake = _Wake(callback);
    wakes.add(wake);
    return () => wake.cancelled = true;
  }

  void fire({bool stale = false}) {
    final current = List<_Wake>.of(wakes);
    wakes.clear();
    for (final wake in current) {
      if (stale || !wake.cancelled) wake.callback();
    }
  }
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _SleepPlayer extends QueuePlayer {
  void buffering(bool value) {
    state = state.copyWith(buffering: value);
    // The controller observes the same backend state snapshot on any stream tick.
    stream.changes.add(state.playing);
  }
}

class _Harness {
  _Harness() {
    controller = PlaybackController(
      player,
      documents,
      sleepClock: clock.now,
      sleepSchedule: clock.schedule,
    );
  }
  final clock = _Clock();
  final player = _SleepPlayer();
  final documents = TransitionDocuments();
  late final PlaybackController controller;
  Future<void> play({PlaybackMode mode = PlaybackMode.sequential}) async {
    await controller.setMode(mode);
    await controller.playSongs([song('same'), song('same'), song('last')], 0);
  }

  Future<void> expire() async {
    clock.advance(const Duration(seconds: 10));
    clock.fire();
    await flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('countdown uses previous observable playing state and monotonic time, validates duration', () {
    final clock = _Clock();
    final timer = SleepCountdown(
      clock: clock.now,
      schedule: clock.schedule,
      onWake: (_) {},
    );
    timer.start(const Duration(seconds: 10));
    timer.update(counting: true, entryId: 'entry-1');
    clock.advance(const Duration(seconds: 3));
    timer.update(counting: false, entryId: 'entry-1');
    clock.advance(const Duration(hours: 1));
    timer.update(counting: true, entryId: 'entry-1');
    expect(timer.remaining, const Duration(seconds: 7));
    clock.advance(const Duration(seconds: 7));
    timer.update(counting: false, entryId: 'entry-1');
    expect(timer.waitingForEnd, isTrue);
    expect(timer.lockedEntryId, 'entry-1');
    expect(timer.remaining, Duration.zero);
    expect(() => timer.start(Duration.zero), throwsArgumentError);
    expect(() => timer.start(const Duration(hours: 13)), throwsArgumentError);
    timer.start(const Duration(hours: 12, minutes: 59));
    expect(timer.active, isTrue);
    expect(timer.waitingForEnd, isFalse);
    timer.dispose();
  });

  test('controller excludes pause, buffering, loading and stop; seek never adds playback time', () async {
    final h = _Harness();
    addTearDown(h.controller.shutdown);
    await h.play();
    await h.controller.setSleepTimer(const Duration(minutes: 1));
    expect(h.controller.canSeek, isTrue);
    expect(h.controller.sleepCounting, isTrue);
    h.clock.advance(const Duration(seconds: 5));
    await h.controller.pause();
    expect(h.controller.canSeek, isTrue);
    expect(h.controller.sleepCounting, isFalse);
    h.clock.advance(const Duration(minutes: 2));
    await h.controller.seek(const Duration(seconds: 22));
    expect(h.controller.sleep.remaining, const Duration(seconds: 55));
    await h.controller.play();
    h.clock.advance(const Duration(seconds: 5));
    h.player.buffering(true);
    expect(h.controller.sleepCounting, isFalse);
    h.clock.advance(const Duration(minutes: 2));
    h.player.buffering(false);
    expect(h.controller.sleepCounting, isTrue);
    expect(h.controller.sleep.remaining, const Duration(seconds: 50));
    h.clock.advance(const Duration(seconds: 5));
    final loading = Completer<TrackMetadata>();
    h.documents.metadataGate = loading;
    final switching = h.controller.next();
    await flush();
    expect(h.controller.changingTrack, isTrue);
    expect(h.controller.canSeek, isFalse);
    expect(h.controller.sleepCounting, isFalse);
    h.clock.advance(const Duration(minutes: 3));
    loading.complete(const TrackMetadata());
    await switching;
    expect(h.controller.canSeek, isTrue);
    expect(h.controller.sleepCounting, isTrue);
    expect(h.controller.sleep.remaining, const Duration(seconds: 45));
    h.clock.advance(const Duration(seconds: 5));
    await h.controller.stop();
    expect(h.controller.canSeek, isFalse);
    expect(h.controller.sleepCounting, isFalse);
    h.clock.advance(const Duration(hours: 1));
    expect(h.controller.sleep.remaining, const Duration(seconds: 40));
    expect(h.controller.queue.entries, hasLength(3));
  });

  test('unrelated directory busy/error never stop counting an actually playing backend', () async {
    final h = _Harness();
    addTearDown(h.controller.shutdown);
    await h.play();
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    h.controller.busy = true;
    h.controller.error = '目录不可访问；旧音频仍在播放';
    h.player.stream.changes.add(true);
    h.clock.advance(const Duration(seconds: 5));
    await h.controller.seek(const Duration(seconds: 20));
    expect(h.controller.playing, isTrue);
    expect(h.controller.sleep.remaining, const Duration(seconds: 5));
    h.controller.busy = false;
    h.controller.error = null;
  });

  for (final mode in PlaybackMode.values) {
    test(
      'expired natural completion stops before $mode and priority FIFO, preserving entry identity',
      () async {
        final h = _Harness();
        addTearDown(h.controller.shutdown);
        await h.play(mode: mode);
        h.controller.queue.add([song('priority')]);
        final locked = h.controller.queue.current!.entryId;
        await h.controller.setSleepTimer(const Duration(seconds: 10));
        await h.expire();
        expect(h.controller.sleep.waitingForEnd, isTrue);
        expect(h.controller.sleep.lockedEntryId, locked);
        expect(h.controller.playing, isTrue);
        final opens = h.player.opens.length;
        h.player.end();
        await flush();
        expect(h.controller.playing, isFalse);
        expect(h.controller.sleep.active, isFalse);
        expect(h.controller.queue.current!.entryId, locked);
        expect(h.controller.queue.entries, hasLength(4));
        expect(h.player.opens.length, opens);
        expect(h.controller.queue.priorityIds, hasLength(1));
      },
    );
  }

  for (final action in [
    'next',
    'previous',
    'select',
    'select-entry',
    'replace',
    'remove-current',
    'handler-next',
    'handler-previous',
  ]) {
    test(
      'expired manual $action stops before any current entry mutation',
      () async {
        final h = _Harness();
        addTearDown(h.controller.shutdown);
        await h.play();
        await h.controller.next();
        final locked = h.controller.queue.current!.entryId;
        await h.controller.setSleepTimer(const Duration(seconds: 10));
        await h.expire();
        final entries = h.controller.queue.entries
            .map((entry) => entry.entryId)
            .toList();
        final opens = h.player.opens.length;
        switch (action) {
          case 'next':
            await h.controller.next();
          case 'previous':
            await h.controller.previous();
          case 'select':
            await h.controller.select(0);
          case 'select-entry':
            await h.controller.selectEntry(entries.first);
          case 'replace':
            await h.controller.playSongs([song('replacement')], 0);
          case 'remove-current':
            await h.controller.removeFromQueue(locked);
          case 'handler-next':
            await TagAudioHandler(h.controller).skipToNext();
          case 'handler-previous':
            await TagAudioHandler(h.controller).skipToPrevious();
        }
        expect(h.controller.playing, isFalse);
        expect(h.controller.sleep.active, isFalse);
        expect(h.controller.queue.current!.entryId, locked);
        expect(
          h.controller.queue.entries.map((entry) => entry.entryId),
          entries,
        );
        expect(h.player.opens.length, opens);
      },
    );
  }

  test('redundant play during expiry wait keeps current playing; pause then finishes stopped', () async {
    final h = _Harness();
    addTearDown(h.controller.shutdown);
    await h.play();
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    await h.expire();
    final locked = h.controller.queue.current!.entryId;
    final opens = h.player.opens.length;
    await h.controller.play();
    expect(h.controller.playing, isTrue);
    expect(h.controller.sleep.waitingForEnd, isTrue);
    expect(h.player.opens.length, opens);
    await h.controller.pause();
    await flush();
    expect(h.controller.playing, isFalse);
    expect(h.controller.sleep.active, isFalse);
    expect(h.controller.queue.current!.entryId, locked);
  });

  test('expiry observed on an already paused backend finishes stopped; delayed callback cannot advance', () async {
    final h = _Harness();
    addTearDown(h.controller.shutdown);
    await h.play();
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    final locked = h.controller.queue.current!.entryId;
    h.clock.advance(const Duration(seconds: 10));
    await h.controller.pause();
    h.clock.fire(stale: true);
    await flush();
    expect(h.controller.sleep.active, isFalse);
    expect(h.controller.playing, isFalse);
    expect(h.controller.queue.current!.entryId, locked);
  });

  test(
    'expiry on decoder failure blocks error-skip and closes the current media',
    () async {
      final h = _Harness();
      addTearDown(h.controller.shutdown);
      await h.play();
      await h.controller.setSleepTimer(const Duration(seconds: 10));
      final locked = h.controller.queue.current!.entryId;
      final opens = h.player.opens.length;
      h.clock.advance(const Duration(seconds: 10));
      h.player.stream.failures.add('expired decoder');
      await flush();
      expect(h.controller.sleep.active, isFalse);
      expect(h.controller.playing, isFalse);
      expect(h.controller.queue.current!.entryId, locked);
      expect(h.player.opens.length, opens);
    },
  );

  test('cancel and reset invalidate stale callbacks and restore normal manual and natural switching', () async {
    final h = _Harness();
    addTearDown(h.controller.shutdown);
    await h.play();
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    h.clock.advance(const Duration(seconds: 5));
    await h.controller.setSleepTimer(const Duration(minutes: 1));
    h.clock.fire(stale: true);
    await flush();
    expect(h.controller.sleep.remaining, const Duration(minutes: 1));
    h.clock.advance(const Duration(minutes: 1));
    h.clock.fire();
    await flush();
    expect(h.controller.sleep.waitingForEnd, isTrue);
    await h.controller.cancelSleepTimer();
    final before = h.controller.queue.current!.entryId;
    await h.controller.next();
    expect(h.controller.queue.current!.entryId, isNot(before));
    h.clock.fire(stale: true);
    await flush();
    expect(h.controller.playing, isTrue);
    expect(h.controller.sleep.active, isFalse);
    final current = h.controller.queue.current!.entryId;
    h.player.end();
    await flush();
    expect(h.controller.queue.current!.entryId, isNot(current));
  });

  test('deadline wins when next is queued before wake delivery, and shutdown invalidates old wake', () async {
    final h = _Harness();
    await h.play();
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    final locked = h.controller.queue.current!.entryId;
    h.clock.advance(const Duration(seconds: 10));
    final next = h.controller.next();
    h.clock.fire(stale: true);
    await next;
    await flush();
    expect(h.controller.playing, isFalse);
    expect(h.controller.queue.current!.entryId, locked);
    await h.controller.setSleepTimer(const Duration(seconds: 10));
    await h.controller.play();
    await h.controller.shutdown();
    h.clock.advance(const Duration(hours: 1));
    h.clock.fire(stale: true);
    await flush();
    expect(h.controller.sleep.active, isFalse);
  });
}
