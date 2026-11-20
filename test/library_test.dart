import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/playback/documents.dart';

class FakeDocuments extends DocumentAccess {
  FakeDocuments() : super(android: false);
  final Map<String, List<ScannedFile>> files = {};
  final Set<String> brokenRoots = {};
  final Set<String> brokenMetadata = {};
  int reads = 0;
  int yielded = 0;
  bool ended = false;
  void Function()? onFile;
  @override
  Future<List<String>> roots() async => files.keys.toList();
  @override
  Stream<ScannedFile> scan(
    String root, {
    required bool Function() cancelled,
  }) async* {
    ended = false;
    try {
      for (final file in files[root] ?? <ScannedFile>[]) {
        if (cancelled()) return;
        yielded++;
        onFile?.call();
        yield file;
      }
      if (brokenRoots.contains(root)) {
        throw FileSystemException('lost grant / unreadable child');
      }
    } finally {
      ended = true;
    }
  }

  @override
  Future<TrackMetadata> metadata(ProbeTrack track) async {
    reads++;
    if (brokenMetadata.contains(track.location)) {
      throw const FormatException('bad audio');
    }
    return TrackMetadata(title: '歌曲 ${track.name}', artist: '歌手', album: '专辑');
  }
}

ScannedFile entry(String name, {String? location, int? modified = 1}) =>
    ScannedFile(
      identity: name,
      location: location ?? '/music/$name',
      name: '$name.mp3',
      relativePath: '子目录/$name.mp3',
      size: 128,
      modified: modified,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDocuments access;
  late LibraryController library;
  setUp(() {
    access = FakeDocuments();
    library = LibraryController(
      LibraryDatabase(NativeDatabase.memory()),
      access,
    );
  });
  tearDown(() => library.shutdown());

  test('overlapping roots share UUID, repeat scan is incremental, bad file does not abort', () async {
    access.files['a'] = [entry('好'), entry('坏')];
    access.files['b'] = [
      entry('好', location: 'content://second/tree/document/same'),
    ];
    access.brokenMetadata.add('/music/坏');
    await library.initialize();
    await library.scan();
    expect(library.tracks.length, 2);
    expect((await library.db.select(library.db.songLocations).get()).length, 3);
    final ids = {
      for (final row in library.tracks) row.song.identity: row.song.id,
    };
    expect(
      library.tracks
          .singleWhere((t) => t.song.identity == '坏')
          .song
          .metadataError,
      isNotNull,
    );
    expect(library.tracks.every((t) => t.available), isTrue);
    access.reads = 0;
    await library.scan();
    expect(access.reads, 1, reason: 'only the bad file is retried');
    expect({
      for (final row in library.tracks) row.song.identity: row.song.id,
    }, ids);
    access.files['a'] = [entry('好', modified: 2), entry('坏')];
    await library.scan(['a']);
    expect(library.metadataReads, 2);
  });

  test(
    'cancel and failed child enumeration never commit partial snapshots',
    () async {
      access.files['a'] = [entry('旧'), entry('保留')];
      await library.initialize();
      await library.scan();
      final original = library.tracks.map((t) => t.song.id).toSet();
      access.files['a'] = [entry('新')];
      access.onFile = library.cancelScan;
      await library.scan();
      expect(library.message, contains('取消'));
      expect(access.ended, isTrue);
      expect(library.tracks.map((t) => t.song.id).toSet(), original);
      expect(library.tracks.every((t) => t.available), isTrue);
      access.onFile = null;
      access.brokenRoots.add('a');
      await library.scan();
      expect(library.tracks.map((t) => t.song.id).toSet(), original);
      expect(library.tracks.every((t) => !t.available), isTrue);
      expect(library.roots.single.status, contains('不可访问'));
      expect(
        (await library.db.select(library.db.songLocations).get()).every(
          (r) => r.available,
        ),
        isTrue,
        reason: 'failed root must keep its prior membership snapshot',
      );
    },
  );

  test('missing and reappearing files retain UUID; another valid root keeps song available', () async {
    access.files['a'] = [entry('共享'), entry('单曲')];
    access.files['b'] = [entry('共享', location: '/other/共享')];
    await library.initialize();
    await library.scan();
    final uuid = library.tracks
        .singleWhere((t) => t.song.identity == '单曲')
        .song
        .id;
    access.files['a'] = [];
    await library.scan(['a']);
    expect(
      library.tracks.singleWhere((t) => t.song.id == uuid).available,
      isFalse,
    );
    expect(
      library.tracks.singleWhere((t) => t.song.identity == '共享').location,
      '/other/共享',
    );
    access.files['a'] = [entry('单曲')];
    await library.scan(['a']);
    expect(
      library.tracks.singleWhere((t) => t.song.id == uuid).available,
      isTrue,
    );
    library.filter(text: '单曲');
    expect(library.visible.single.song.id, uuid);
    library.filter(text: '专辑', order: LibrarySort.name, reverse: true);
    expect(library.visible.length, 2);
    library.filter(text: '不存在');
    expect(library.visible, isEmpty);
  });

  test('unknown modification time re-reads metadata; SQL failure rolls back all writes', () async {
    access.files['a'] = [entry('旧', modified: null)];
    await library.initialize();
    await library.scan();
    await library.scan();
    expect(library.metadataReads, 1);
    await library.db.customStatement(
      "CREATE TRIGGER reject_song BEFORE INSERT ON songs WHEN NEW.identity = '新' BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
    );
    access.files['a'] = [entry('新')];
    await library.scan();
    expect(library.tracks.single.song.identity, '旧');
    expect(
      (await library.db.select(library.db.songLocations).get())
          .single
          .available,
      isTrue,
    );
  });

  test('database reopens with schema v5, stable UUIDs and saved roots without rescanning', () async {
    final dir = await Directory.systemTemp.createTemp('tag-music-db-');
    final file = File('${dir.path}/library.sqlite');
    final first = LibraryController(
      LibraryDatabase(NativeDatabase(file)),
      access,
    );
    access.files['a'] = [entry('中文')];
    await first.initialize();
    await first.scan();
    final uuid = first.tracks.single.song.id;
    await first.shutdown();
    access.files.clear();
    final second = LibraryController(
      LibraryDatabase(NativeDatabase(file)),
      access,
    );
    try {
      await second.initialize();
      expect(second.tracks.single.song.id, uuid);
      expect(second.roots.single.location, 'a');
      expect(
        (await second.db.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        5,
      );
      expect(
        (await second.db.customSelect('PRAGMA foreign_key_check').get()),
        isEmpty,
      );
    } finally {
      await second.shutdown();
      await dir.delete(recursive: true);
    }
  });

  test('10000-song database scan, search and sort benchmark (synthetic identities)', () async {
    access.files['a'] = [for (var i = 0; i < 10000; i++) entry('歌曲$i')];
    await library.initialize();
    final scan = Stopwatch()..start();
    await library.scan();
    scan.stop();
    expect(library.tracks.length, 10000);
    final samples = <int>[];
    for (var i = 0; i < 25; i++) {
      library.filter(
        text: i.isEven ? '专辑' : '歌曲9',
        order: LibrarySort.values[i % 4],
        reverse: i.isEven,
      );
      final watch = Stopwatch()..start();
      final count = library.visible.length;
      watch.stop();
      expect(count, greaterThan(0));
      if (i >= 5) samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    final p95 = samples[(samples.length * .95).ceil() - 1];
    expect(p95, lessThan(500000));
    final report = Platform.environment['TAG_MUSIC_LIBRARY_REPORT'];
    if (report != null) {
      await File(report).writeAsString(
        jsonEncode({
          'platform': Platform.operatingSystem,
          'syntheticDatabaseSongs': 10000,
          'realFilesScanned': 0,
          'initialScanMs': scan.elapsedMilliseconds,
          'warmSearchSortP95Microseconds': p95,
          'samples': samples,
        }),
      );
    }
  });

  test('schema v5 matches checked-in SQLite DDL baseline', () async {
    final rows = await library.db
        .customSelect(
          "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name",
        )
        .get();
    final schema = {
      'version': library.db.schemaVersion,
      'schema': rows.map((r) => r.data).toList(),
    };
    final output = Platform.environment['TAG_MUSIC_SCHEMA_REPORT'];
    if (output != null) {
      await File(output)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(schema));
    }
    final baseline = File('docs/database-schema/v5.json');
    if (await baseline.exists()) {
      expect(
        schema,
        jsonDecode(await baseline.readAsString()),
        reason: 'schema changes require a migration and a new baseline',
      );
    } else {
      expect(
        output,
        isNotNull,
        reason: 'first export must explicitly set TAG_MUSIC_SCHEMA_REPORT',
      );
    }
  });

  test(
    'real recursive files, embedded cover and normalized overlap keep read-only bytes',
    () async {
      final fixtures = Platform.environment['TAG_MUSIC_LIBRARY_FIXTURES'];
      if (fixtures == null) return;
      final real = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        DocumentAccess(android: false),
      );
      try {
        await real.scan([
          '$fixtures/primary',
          '$fixtures/secondary',
          '$fixtures/primary/子目录',
        ]);
        expect(real.tracks.length, 9);
        expect(real.tracks.every((t) => t.available), isTrue);
        expect(
          real.tracks.where((t) => t.song.metadataError != null).length,
          1,
        );
        final art = real.tracks.singleWhere((t) => t.song.name == '内嵌封面.flac');
        final bytes = await File(art.probe.location).readAsBytes();
        expect((await real.documents.cover(art.probe))?.length, greaterThan(0));
        expect(await File(art.probe.location).readAsBytes(), bytes);
        final ids = real.tracks.map((t) => t.song.id).toSet();
        await real.scan(['$fixtures/primary', '$fixtures/secondary']);
        expect(real.metadataReads, 1);
        expect(real.tracks.map((t) => t.song.id).toSet(), ids);
      } finally {
        await real.shutdown();
      }
    },
    skip: Platform.environment['TAG_MUSIC_LIBRARY_FIXTURES'] == null
        ? 'Run scripts/check.ps1 -Round R2'
        : false,
  );
}
