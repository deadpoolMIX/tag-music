import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/playback_queue.dart';

QueueSong song(String id) => QueueSong(
  songId: id,
  track: ProbeTrack(location: '/$id.flac', name: '$id.flac'),
);

PlaybackQueue queue(List<String> ids, {PlaybackMode? mode, int target = 0}) {
  final value = PlaybackQueue(random: Random(53));
  if (mode != null) value.setMode(mode);
  value.replace(ids.map(song).toList(), target);
  return value;
}

String? id(QueueEntry? entry) => entry?.song.songId;

void main() {
  test(
    'cold state is empty shuffle; snapshots are isolated and UUID-addressed',
    () {
      final value = PlaybackQueue();
      expect(value.mode, PlaybackMode.shuffle);
      expect(value.current, isNull);
      expect(value.canNext, isFalse);
      expect(value.canPrevious, isFalse);
      final songs = [song('A'), song('A')];
      value.replace(songs, 0);
      songs.clear();
      expect(value.entries.map((e) => e.song.songId), ['A', 'A']);
      expect(value.entries.map((e) => e.entryId).toSet(), hasLength(2));
      expect(() => value.entries.clear(), throwsUnsupportedError);
      expect(() => value.replace([song('B')], -1), throwsRangeError);
      expect(id(value.current), 'A');
    },
  );

  for (final mode in [PlaybackMode.sequential, PlaybackMode.repeatAll]) {
    test(
      '$mode priority FIFO resumes the source without replaying detours',
      () {
        final value = queue(['start', 'original', 'last'], mode: mode);
        value.add([song('A')]);
        value.add([song('B'), song('C')]);
        expect(value.entries.map((e) => e.song.songId), [
          'start',
          'A',
          'B',
          'C',
          'original',
          'last',
        ]);
        expect(
          [for (var i = 0; i < 5; i++) id(value.next())],
          ['A', 'B', 'C', 'original', 'last'],
        );
        expect(value.priorityIds, isEmpty);
        expect(value.entries, hasLength(6));
        expect(
          id(value.next()),
          mode == PlaybackMode.sequential ? null : 'start',
        );
      },
    );
  }

  test(
    'priority insertion during a priority song follows all waiting requests',
    () {
      final value = queue(['start', 'original'], mode: PlaybackMode.sequential);
      value.add([song('A'), song('B')]);
      expect(id(value.next()), 'A');
      value.add([song('C')]);
      expect(
        [id(value.next()), id(value.next()), id(value.next())],
        ['B', 'C', 'original'],
      );
      expect(value.next(), isNull);
    },
  );

  test(
    'empty add selects first; replace clears priority and history, keeps mode',
    () {
      final value = PlaybackQueue()..add([song('A'), song('B')]);
      expect(id(value.current), 'A');
      expect(value.priorityIds, [value.entries[1].entryId]);
      value.next();
      expect(value.canPrevious, isTrue);
      value.replace([song('new')], 0);
      expect(value.priorityIds, isEmpty);
      expect(value.canPrevious, isFalse);
      expect(value.mode, PlaybackMode.shuffle);
      expect(id(value.current), 'new');
    },
  );

  test('single repeat waits for manual next; manual navigation wraps', () {
    final value = queue(['start', 'original'], mode: PlaybackMode.repeatOne);
    value.add([song('A'), song('B')]);
    expect(id(value.next(natural: true)), 'start');
    expect(value.priorityIds, hasLength(2));
    expect(id(value.next()), 'A');
    expect(id(value.next(natural: true)), 'A');
    expect(id(value.next()), 'B');
    expect(id(value.next()), 'original');
    expect(id(value.next()), 'start');
    expect(id(value.previous()), 'original');
  });

  test('sequential previous then next replays the displayed successor', () {
    final value = queue(['A', 'B', 'C'], mode: PlaybackMode.sequential);
    expect(id(value.next()), 'B');
    expect(id(value.previous()), 'A');
    expect(id(value.next()), 'B');
    expect(id(value.next()), 'C');
    expect(value.canNext, isFalse);
    expect(value.next(), isNull);
  });

  test(
    'shuffle visits each entry once per round, including duplicate songs',
    () {
      final value = queue(['A', 'A', 'B', 'C']);
      final expected = value.entries.map((e) => e.entryId).toSet();
      final first = [
        value.current!.entryId,
        for (var i = 0; i < 3; i++) value.next()!.entryId,
      ];
      final second = [for (var i = 0; i < 4; i++) value.next()!.entryId];
      expect(first.toSet(), expected);
      expect(second.toSet(), expected);
      expect(first, hasLength(expected.length));
      expect(second, hasLength(expected.length));
    },
  );

  test(
    'shuffle priority precedes random, history wins on forward navigation',
    () {
      final value = queue(['start', 'X', 'Y', 'Z']);
      value.add([song('A')]);
      value.add([song('B')]);
      expect(id(value.next()), 'A');
      expect(id(value.next()), 'B');
      expect(id(value.previous()), 'A');
      value.add([song('C')]);
      expect(id(value.next()), 'B');
      expect(id(value.next()), 'C');
      final remainder = [for (var i = 0; i < 3; i++) id(value.next())];
      expect(remainder.toSet(), {'X', 'Y', 'Z'});
      final second = [for (var i = 0; i < 7; i++) value.next()!.entryId];
      expect(second.toSet(), value.entries.map((e) => e.entryId).toSet());
    },
  );

  test(
    'reorder keeps current identity and shuffle schedule; priority can reorder',
    () {
      final value = queue(['A', 'B', 'C', 'D']);
      final control = queue(['A', 'B', 'C', 'D']);
      final current = value.current!.entryId;
      value.reorder(
        value.entries.map((e) => e.entryId).toList().reversed.toList(),
      );
      expect(value.current!.entryId, current);
      expect(
        [for (var i = 0; i < 3; i++) id(value.next())],
        [for (var i = 0; i < 3; i++) id(control.next())],
      );
      value.add([song('X'), song('Y')]);
      final ordered = value.entries.map((e) => e.entryId).toList();
      final a = ordered.indexOf(value.priorityIds[0]);
      final b = ordered.indexOf(value.priorityIds[1]);
      final first = ordered[a];
      ordered[a] = ordered[b];
      ordered[b] = first;
      value.reorder(ordered);
      expect([id(value.next()), id(value.next())], ['Y', 'X']);
      expect(() => value.reorder([current]), throwsArgumentError);
    },
  );

  test('remove current selects successor then predecessor; duplicate is independent', () {
    final value = queue(['A', 'A', 'B'], mode: PlaybackMode.sequential);
    final first = value.current!.entryId;
    final second = value.entries[1].entryId;
    value.remove(first);
    expect(value.current!.entryId, second);
    expect(value.entries, hasLength(2));
    value.next();
    value.remove(value.current!.entryId);
    expect(value.current!.entryId, second);
    value.remove(second);
    expect(value.current, isNull);
    expect(value.entries, isEmpty);
    expect(value.canPrevious, isFalse);
    expect(value.canNext, isFalse);
  });

  test(
    'remove history and pending references leaves no dangling selections',
    () {
      final value = queue(['A', 'B', 'C']);
      value.add([song('X'), song('Y')]);
      final removed = value.priorityIds.first;
      value.next();
      value.next();
      value.remove(removed);
      expect(id(value.previous()), 'A');
      expect(id(value.next()), 'Y');
      expect(value.priorityIds, isEmpty);
    },
  );

  test(
    'mode change preserves current and priority, starts new shuffle traversal',
    () {
      final value = queue(['A', 'B', 'C'], mode: PlaybackMode.sequential);
      value.add([song('X')]);
      final current = value.current!.entryId;
      value.setMode(PlaybackMode.shuffle);
      expect(value.current!.entryId, current);
      expect(id(value.next()), 'X');
      expect({id(value.next()), id(value.next())}, {'B', 'C'});
      value.clear();
      expect(value.mode, PlaybackMode.shuffle);
      expect(PlaybackQueue().entries, isEmpty);
    },
  );

  for (final mode in PlaybackMode.values) {
    test('$mode exclusion bounds a failed traversal including singleton', () {
      final value = queue(['A', 'B', 'C'], mode: mode);
      final attempted = <String>{value.current!.entryId};
      while (true) {
        final candidate = value.next(excluded: attempted);
        if (candidate == null) break;
        expect(attempted.add(candidate.entryId), isTrue);
        expect(attempted.length, lessThanOrEqualTo(3));
      }
      expect(attempted, hasLength(3));
      final single = queue(['one'], mode: mode);
      expect(single.next(excluded: {single.current!.entryId}), isNull);
    });
  }

  test('10000 entries retain bounded membership through priority and shuffle round', () {
    final value = queue(List.generate(10000, (i) => '$i'));
    value.add([song('10000'), song('10001')]);
    expect([id(value.next()), id(value.next())], ['10000', '10001']);
    final visited = {
      value.entries.first.entryId,
      ...value.entries
          .where((e) => int.parse(e.song.songId) >= 10000)
          .map((e) => e.entryId),
    };
    for (var i = 0; i < 9999; i++) {
      expect(visited.add(value.next()!.entryId), isTrue);
    }
    expect(visited, hasLength(10002));
  });
}
