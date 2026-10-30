import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/playback/documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recursive directory discovery ignores symlinks and non-audio files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tag-music-discovery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await Directory('${directory.path}/子目录').create();
      await File('${directory.path}/子目录/中文.MP3').writeAsString('invalid audio');
      await File('${directory.path}/notes.txt').writeAsString('ignore');
      final tracks = await DocumentAccess(android: false).list(directory.path);
      expect(tracks.map((t) => t.name), ['中文.MP3']);
    },
  );

  test(
    'unavailable directory fails instead of returning a misleading empty list',
    () async {
      await expectLater(
        DocumentAccess(android: false).list('missing-r1-directory'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'metadata failure always closes the acquired Android descriptor',
    () async {
      const channel = MethodChannel('test.documents');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'open') return 2147483646;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        DocumentAccess(android: true, channel: channel).metadata(
          const ProbeTrack(
            location: 'content://test/document/song',
            name: 'song.mp3',
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(calls.map((call) => call.method), ['open', 'close']);
      expect(calls.last.arguments, {'fd': 2147483646});
    },
  );

  test('Android discovery preserves provider URIs verbatim', () async {
    const channel = MethodChannel('test.documents');
    const uri = 'content://provider/tree/root/document/opaque%3A42';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => [
            {'location': uri, 'name': '中文.mp3'},
          ],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final tracks = await DocumentAccess(
      android: true,
      channel: channel,
    ).list('content://provider/tree/root');
    expect(tracks.single.location, uri);
  });

  test(
    'paged SAF enumeration closes token on cancellation and page errors',
    () async {
      const channel = MethodChannel('test.pages');
      final calls = <String>[];
      var fail = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'beginScan') return 41;
            if (call.method == 'nextScan') {
              if (fail) throw PlatformException(code: 'lost-grant');
              return {
                'done': false,
                'files': [
                  {
                    'identity': 'provider:opaque:42',
                    'location':
                        'content://provider/tree/root/document/opaque%3A42',
                    'name': '中文.mp3',
                    'relativePath': '子目录/中文.mp3',
                    'size': 123,
                    'modified': 1000,
                  },
                ],
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final access = DocumentAccess(android: true, channel: channel);
      final first = await access
          .scan('content://provider/tree/root', cancelled: () => false)
          .first;
      expect(
        first.location,
        'content://provider/tree/root/document/opaque%3A42',
      );
      expect(first.relativePath, '子目录/中文.mp3');
      expect(calls, ['beginScan', 'nextScan', 'endScan']);
      calls.clear();
      fail = true;
      await expectLater(
        access
            .scan('content://provider/tree/root', cancelled: () => false)
            .toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['beginScan', 'nextScan', 'endScan']);
    },
  );

  test(
    'six original audio formats read metadata without changing file bytes',
    () async {
      final fixtures = Directory(Platform.environment['TAG_MUSIC_FIXTURES']!);
      expect(
        await fixtures.exists(),
        isTrue,
        reason: 'Run scripts/make-audio-fixtures.ps1 first',
      );
      for (final extension in ['wav', 'mp3', 'flac', 'm4a', 'ogg', 'opus']) {
        final file = File('${fixtures.path}/中文测试-$extension.$extension');
        final original = await file.readAsBytes();
        final metadata = await DocumentAccess(android: false).metadata(
          ProbeTrack(location: file.path, name: file.uri.pathSegments.last),
        );
        expect(metadata.title, '中文测试音', reason: extension);
        expect(metadata.artist, 'Tag Music', reason: extension);
        expect(
          await file.readAsBytes(),
          original,
          reason: 'Music files must remain read-only',
        );
      }
    },
    skip: Platform.environment['TAG_MUSIC_FIXTURES'] == null
        ? 'Use scripts/check.ps1 to generate and verify six audio formats'
        : false,
  );
}
