import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/library/song_editor_page.dart';
import 'package:tag_music/library/song_file_editor.dart';

import 'library_test.dart' show FakeDocuments, entry;

class _Editor extends SongFileEditor {
  EditableSongFile? chosen;
  SongEdits? edits;

  @override
  Future<SongFileDraft> readSong(EditableSongFile file) async {
    chosen = file;
    return SongFileDraft(
      file,
      const SongFileMetadata(title: '旧歌名', artist: '旧歌手', album: '旧专辑'),
      'checksum',
    );
  }

  @override
  Future<SavedSongFile> save(
    SongFileDraft draft,
    SongEdits edits, {
    String? parent,
  }) async {
    this.edits = edits;
    final target = editedSongName(
      edits.title,
      edits.artist,
      draft.file.extension,
    );
    return SavedSongFile(
      SongFileDraft(
        EditableSongFile(target, target, target),
        SongFileMetadata(
          title: edits.title,
          artist: edits.artist,
          album: edits.album,
        ),
        'new-checksum',
      ),
    );
  }
}

void main() {
  testWidgets(
    'picks one library song, saves its metadata, and clears the editor',
    (tester) async {
      final editor = _Editor();
      final documents = FakeDocuments()..files['曲库'] = [entry('旧名字')];
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        documents,
      );
      addTearDown(library.shutdown);
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan();
      });
      final songId = library.tracks.single.song.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SongEditorPage(library: library, editor: editor),
          ),
        ),
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('选择歌曲'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('edit-song-$songId')));
      await tester.pumpAndSettle();
      expect(editor.chosen?.location, '/music/旧名字');
      expect(find.text('旧歌名'), findsOneWidget);
      expect(find.text('旧歌手'), findsOneWidget);
      expect(find.text('旧专辑'), findsOneWidget);

      final title = find.byType(TextFormField).first;
      await tester.enterText(title, '');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入歌名'), findsOneWidget);
      expect(editor.edits, isNull);

      await tester.enterText(title, '新歌名');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(editor.edits?.title, '新歌名');
      expect(library.tracks.single.song.id, songId);
      expect(library.tracks.single.song.title, '新歌名');
      expect(find.text('已保存 新歌名-旧歌手.mp3'), findsOneWidget);
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  test(
    'file name preserves the extension and replaces forbidden characters',
    () {
      expect(editedSongName('歌曲/1', '歌手:2', '.FLAC'), '歌曲_1-歌手_2.FLAC');
      expect(
        () => editedSongName(List.filled(100, '歌').join(), '歌手', '.mp3'),
        throwsA(isA<SongEditorException>()),
      );
    },
  );

  test('cover is encoded as a smaller JPEG without cropping', () async {
    final pixels = image.Image(width: 1200, height: 600);
    final jpeg = await compressSongCover(image.encodePng(pixels));
    final decoded = image.decodeJpg(jpeg)!;
    expect((decoded.width, decoded.height), (1000, 500));
    expect(
      () => compressSongCover(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<SongEditorException>()),
    );
  });

  final fixtures = Platform.environment['TAG_MUSIC_EDITOR_FIXTURES'];
  test(
    'native metadata round trips on all edit formats',
    () async {
      final root = Directory(fixtures!);
      final cover = await compressSongCover(
        image.encodePng(image.Image(width: 32, height: 20)),
      );
      for (final mode in ['plain', 'tagged']) {
        for (final extension in ['mp3', 'flac', 'm4a', 'wav', 'ogg', 'opus']) {
          final name = '$mode.$extension';
          final copy = await File('${root.path}/$name')
              .copy('${root.path}/edited-$name');
          final result = await writeSongFileTags(copy.path, (
            title: '新歌名',
            artist: '新歌手',
            album: '新专辑',
            cover: cover,
          ));
          expect(result.title, '新歌名', reason: name);
          expect(result.artist, '新歌手', reason: name);
          expect(result.album, '新专辑', reason: name);
          expect(result.pictureBytes, cover, reason: name);
          final updated = await writeSongFileTags(copy.path, (
            title: '再次修改',
            artist: '新歌手',
            album: '',
            cover: null,
          ));
          expect(updated.album, isNull, reason: name);
          expect(updated.pictureBytes, cover, reason: name);
        }
      }
    },
    skip: fixtures == null
        ? 'Requires native library and generated FFmpeg fixtures'
        : false,
  );

  test(
    'Windows replaces only the selected original and respects collisions',
    () async {
      final folder = await Directory.systemTemp.createTemp('歌曲-编辑-');
      addTearDown(() => folder.delete(recursive: true));
      final source = await File('$fixtures/tagged.mp3')
          .copy('${folder.path}/旧.mp3');
      final target = await File('${folder.path}/新歌-新歌手.mp3')
          .writeAsString('unrelated');
      final originalBytes = await source.readAsBytes();
      final draft = SongFileDraft(
        EditableSongFile(source.path, '旧.mp3', source.path.toLowerCase()),
        const SongFileMetadata(),
        sha256.convert(originalBytes).toString(),
      );
      const edits = (
        title: '新歌',
        artist: '新歌手',
        album: '',
        cover: null as Uint8List?,
      );
      const editor = SongFileEditor();
      await expectLater(
        editor.save(draft, edits),
        throwsA(isA<SongEditorException>()),
      );
      expect(await target.readAsString(), 'unrelated');
      expect(await source.readAsBytes(), originalBytes);
      await target.delete();

      final saved = await editor.save(draft, edits);
      expect(saved.draft.file.name, '新歌-新歌手.mp3');
      expect(await source.exists(), isFalse);
      expect(await File(saved.draft.file.location).exists(), isTrue);
      final updated = await editor.save(saved.draft, (
        title: edits.title,
        artist: edits.artist,
        album: '新专辑',
        cover: null,
      ));
      expect(updated.draft.metadata.album, '新专辑');
      expect(await folder.list().length, 1);
    },
    skip: fixtures == null || !Platform.isWindows
        ? 'Requires Windows and generated FFmpeg fixtures'
        : false,
  );
}
