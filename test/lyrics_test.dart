import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/playback/documents.dart';
import 'package:tag_music/playback/lyrics.dart';
import 'package:tag_music/playback/cover_cache.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LRC groups bilingual and extra lines, sorts multiple stamps and applies final offset', () {
    final lyrics = parseLyrics(
      bytes(
        '[ar:作者]\n[00:02.5][00:01]原文\n[00:01]译文\n[00:01]附加行\n[offset:-500]',
      ),
    );
    expect(lyrics.lines.map((l) => l.milliseconds), [500, 2000]);
    expect(lyrics.lines.first.texts, ['原文', '译文', '附加行']);
    expect(lyrics.indexAt(const Duration(milliseconds: 499)), -1);
    expect(lyrics.indexAt(const Duration(milliseconds: 500)), 0);
    expect(lyrics.indexAt(const Duration(seconds: 10)), 1);
    expect(
      parseLyrics(bytes('[offset:1000]\n[1:02.03]a')).lines.single.milliseconds,
      63030,
    );
  });

  test('UTF-8 BOM and both UTF-16 BOMs work; invalid encodings and surrogates fail', () {
    const source = '[00:01]你好🎵';
    expect(
      decodeLyrics(
        Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(source)]),
      ),
      source,
    );
    for (final little in [true, false]) {
      final encoded = <int>[
        if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff],
      ];
      for (final unit in source.codeUnits) {
        encoded.addAll(
          little ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
        );
      }
      expect(
        parseLyrics(Uint8List.fromList(encoded)).lines.single.original,
        '你好🎵',
      );
    }
    for (final invalid in [
      [0xff],
      [0xff, 0xfe, 0x00],
      [0xff, 0xfe, 0x00, 0xd8],
      [0xff, 0xfe, 0x00, 0xdc],
      [0x00, 0x61],
    ]) {
      expect(
        () => decodeLyrics(Uint8List.fromList(invalid)),
        throwsFormatException,
      );
    }
  });

  test(
    'LRC has bounded input and time points and degrades malformed timestamps',
    () {
      expect(
        () => parseLyrics(Uint8List(maxLyricsBytes + 1)),
        throwsFormatException,
      );
      expect(
        () => parseLyrics(
          bytes(List.generate(10001, (i) => '[$i:00]a').join('\n')),
        ),
        throwsFormatException,
      );
      expect(() => parseLyrics(bytes('[00:60]bad')), throwsFormatException);
      expect(parseLyrics(bytes('[ar:name]')).lines, isEmpty);
      expect(
        parseLyrics(
          bytes(
            List.generate(
              5001,
              (i) => '[$i:00]original\n[$i:00]translation',
            ).join('\n'),
          ),
        ).lines.length,
        5001,
      );
      expect(
        parseLyrics(bytes('[offset:-5000]\n[00:01]a\n[00:02]b'))
            .lines
            .single
            .texts,
        ['a', 'b'],
      );
    },
  );

  test('shared timeline rejects stale success and stale error, clear and dispose invalidate reads', () async {
    final timeline = LyricsTimeline();
    final slow = Completer<Uint8List?>();
    final first = timeline.load(() => slow.future);
    await timeline.load(() async => bytes('[00:01]new'));
    slow.complete(bytes('[00:01]old'));
    await first;
    expect(timeline.value.lines.single.original, 'new');
    final failure = Completer<Uint8List?>();
    final second = timeline.load(() => failure.future);
    await timeline.load(() async => bytes('[00:01]newer'));
    failure.completeError(StateError('old failure'));
    await second;
    expect(timeline.value.lines.single.original, 'newer');
    final cleared = Completer<Uint8List?>();
    final third = timeline.load(() => cleared.future);
    timeline.clear();
    cleared.complete(bytes('[00:01]stale'));
    await third;
    expect(timeline.value.lines, isEmpty);
    final disposed = Completer<Uint8List?>();
    final fourth = timeline.load(() => disposed.future);
    timeline.dispose();
    disposed.complete(bytes('[00:01]disposed'));
    await fourth;
  });

  test('Android companion uses queried provider URI verbatim and propagates bounded read errors', () async {
    const channel = MethodChannel('test.lyrics');
    const actual = 'content://provider/tree/root/document/opaque%3Alyric';
    final calls = <MethodCall>[];
    var failRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'findLyrics') return actual;
          if (call.method == 'readLyrics') {
            expect(call.arguments, {'uri': actual});
            if (failRead) {
              throw PlatformException(
                code: 'documents',
                message: '歌词超过 1MiB 上限',
              );
            }
            return bytes('[00:01]content');
          }
          throw StateError('Unexpected FD or path operation');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final documents = DocumentAccess(android: true, channel: channel);
    const track = ProbeTrack(
      location: 'content://provider/tree/root/document/opaque%3Aaudio',
      name: 'song.flac',
    );
    expect(
      parseLyrics((await documents.lyrics(track))!).lines.single.original,
      'content',
    );
    expect(calls.map((c) => c.method), ['findLyrics', 'readLyrics']);
    failRead = true;
    await expectLater(
      documents.lyrics(track),
      throwsA(isA<PlatformException>()),
    );
    failRead = false;
    expect(
      await documents.lyrics(track),
      isNotNull,
    ); // Serial read lane recovers after failure.
  });

  test(
    'pending Android companion query does not block metadata descriptor close',
    () async {
      const channel = MethodChannel('test.lyrics.independent');
      final query = Completer<String?>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'findLyrics') return query.future;
            if (call.method == 'open') return 2147483646;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final documents = DocumentAccess(android: true, channel: channel);
      const track = ProbeTrack(
        location: 'content://provider/tree/root/document/song',
        name: 'song.flac',
      );
      final lyrics = documents.lyrics(track);
      await expectLater(
        documents.metadata(track),
        throwsA(isA<FileSystemException>()),
      );
      expect(calls, ['findLyrics', 'open', 'close']);
      query.complete(null);
      expect(await lyrics, isNull);
    },
  );

  test(
    'desktop reads only same-stem sibling, closes after oversize and recovers',
    () async {
      final directory = await Directory.systemTemp.createTemp('tag-lyrics-');
      addTearDown(() => directory.delete(recursive: true));
      final documents = DocumentAccess(android: false);
      final track = ProbeTrack(
        location: '${directory.path}/same.flac',
        name: 'same.flac',
      );
      await File('${directory.path}/other.lrc').writeAsString('[00:01]wrong');
      expect(await documents.lyrics(track), isNull);
      final sibling = File('${directory.path}/same.lrc');
      await sibling.writeAsBytes(Uint8List(maxLyricsBytes + 1));
      await expectLater(documents.lyrics(track), throwsFormatException);
      await sibling.delete();
      await sibling.writeAsString('[00:01]right');
      expect(
        parseLyrics((await documents.lyrics(track))!).lines.single.original,
        'right',
      );
      await sibling.delete();
    },
  );

  test(
    'cover cache decodes bounded target dimensions and reuses resized bytes',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 64),
        ui.Paint()..color = const ui.Color(0xffaabbcc),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      var reads = 0;
      final cache = CoverCache();
      Future<Uint8List?> read() async {
        reads++;
        return png!.buffer.asUint8List();
      }

      final small = await cache.get(('same', 1, 1, 32), 32, read);
      expect(small, isNotNull);
      final codec = await ui.instantiateImageCodec(small!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 32);
      expect(frame.image.height, 32);
      frame.image.dispose();
      codec.dispose();
      expect(
        identical(await cache.get(('same', 1, 1, 32), 32, read), small),
        isTrue,
      );
      expect(reads, 1);
      expect(cache.bytes, small.length);
    },
  );

  test('cover cache merges pending reads, caches bad images, bounds entries and invalidates changed keys', () async {
    final cache = CoverCache();
    var reads = 0;
    final pending = Completer<Uint8List?>();
    Future<Uint8List?> read() {
      reads++;
      return pending.future;
    }

    final a = cache.get('path|1|1|96', 96, read);
    final b = cache.get('path|1|1|96', 96, read);
    expect(reads, 1);
    pending.complete(Uint8List.fromList([1, 2, 3]));
    expect(await a, isNull);
    expect(await b, isNull);
    expect(await cache.get('path|1|1|96', 96, read), isNull);
    expect(reads, 1);
    Future<Uint8List?> missing() async {
      reads++;
      return null;
    }

    await cache.get('path|2|2|96', 96, missing);
    expect(reads, 2);
    for (var i = 0; i < CoverCache.entryLimit; i++) {
      await cache.get('new$i', 96, missing);
    }
    await cache.get('path|1|1|96', 96, missing);
    expect(reads, CoverCache.entryLimit + 3);
    expect(cache.bytes, lessThanOrEqualTo(CoverCache.byteLimit));
  });
}
