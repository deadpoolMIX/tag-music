import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_taglib/flutter_taglib.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _editableExtensions = ['mp3', 'flac', 'm4a', 'wav', 'ogg', 'opus'];

class SongEditorException implements Exception {
  const SongEditorException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EditableSongFile {
  const EditableSongFile(this.location, this.name, this.identity);

  final String location;
  final String name;
  final String identity;
  String get extension => p.extension(name);

  factory EditableSongFile.fromPlatform(Map<String, Object?> values) =>
      EditableSongFile(
        values['location']! as String,
        values['name']! as String,
        values['identity']! as String,
      );
}

class SongFileDraft {
  const SongFileDraft(this.file, this.metadata, this.digest);
  final EditableSongFile file;
  final SongFileMetadata metadata;
  final String digest;
}

class SongFileMetadata {
  const SongFileMetadata({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.pictureBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? pictureBytes;
}

typedef SongEdits = ({
  String title,
  String artist,
  String album,
  Uint8List? cover,
});

class SavedSongFile {
  const SavedSongFile(
    this.draft, {
    this.documentId,
    this.size,
    this.modified,
    this.backup,
  });
  final SongFileDraft draft;
  final String? documentId;
  final int? size;
  final int? modified;
  final String? backup;
}

String editedSongName(String title, String artist, String extension) {
  final invalid = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]');
  final name = '$title-$artist'.replaceAll(invalid, '_');
  final result = '$name$extension';
  if (utf8.encode(result).length > 240) {
    throw const SongEditorException('歌名和歌手组成的文件名太长，请缩短后再保存');
  }
  return result;
}

class SongFileEditor {
  const SongFileEditor();

  static const _channel = MethodChannel('app.tagmusic.player/song_editor');
  static const _tempPrefix = 'tag-music-edit-';

  Future<SongFileDraft?> pickSong() async {
    final EditableSongFile selected;
    if (Platform.isAndroid) {
      final values = await _channel.invokeMapMethod<String, Object?>(
        'pickSong',
      );
      if (values == null) return null;
      selected = EditableSongFile.fromPlatform(values);
    } else {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: '歌曲', extensions: _editableExtensions),
        ],
      );
      if (picked == null) return null;
      final location = p.normalize(p.absolute(picked.path));
      selected = EditableSongFile(
        location,
        p.basename(location),
        Platform.isWindows ? location.toLowerCase() : location,
      );
    }
    if (!_editableExtensions.contains(
      selected.extension.toLowerCase().replaceFirst('.', ''),
    )) {
      throw const SongEditorException('请选择 MP3、FLAC、M4A、WAV、OGG 或 Opus 文件');
    }
    return _withCopy(selected, (copy, _) async {
      final metadata = await _readMetadata(copy.path);
      return SongFileDraft(selected, metadata, await _digest(copy));
    });
  }

  Future<Uint8List?> pickCover() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '图片',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
          mimeTypes: ['image/*'],
        ),
      ],
    );
    if (picked == null) return null;
    if (await picked.length() > 24 * 1024 * 1024) {
      throw const SongEditorException('图片文件超过 24 MB，请选一张较小的图片');
    }
    return compressSongCover(await picked.readAsBytes());
  }

  Future<String?> pickParent(EditableSongFile file) =>
      _channel.invokeMethod<String>('pickParent', {'uri': file.location});

  Future<SavedSongFile> save(
    SongFileDraft draft,
    SongEdits edits, {
    String? parent,
  }) async {
    final file = draft.file;
    final name = editedSongName(edits.title, edits.artist, file.extension);
    return _withCopy(file, (copy, directory) async {
      if (await _digest(copy) != draft.digest) {
        throw const SongEditorException('原文件已被其他程序修改，请重新选择歌曲');
      }
      final metadata = await writeSongFileTags(copy.path, edits);
      final digest = await _digest(copy);
      if (Platform.isAndroid) {
        final values = (await _channel.invokeMapMethod<String, Object?>(
          'replaceSong',
          {
            'uri': file.location,
            'parent': parent,
            'path': copy.path,
            'name': name,
            'originalName': file.name,
            'digest': draft.digest,
            'editedDigest': digest,
          },
        ))!;
        return SavedSongFile(
          SongFileDraft(
            EditableSongFile.fromPlatform(values),
            metadata,
            digest,
          ),
          documentId: values['documentId'] as String?,
          size: values['size'] as int?,
          modified: values['modified'] as int?,
          backup: values['backup'] as String?,
        );
      }

      final target = p.join(p.dirname(file.location), name);
      final identity = Platform.isWindows ? target.toLowerCase() : target;
      if (identity != file.identity &&
          await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw SongEditorException('文件夹里已有同名文件：$name');
      }
      final original = File(file.location);
      if (await _digest(original) != draft.digest) {
        throw const SongEditorException('原文件已被其他程序修改，请重新选择歌曲');
      }
      final stat = await copy.stat();
      final backup = p.join(directory.path, 'original${file.extension}');
      _moveWithoutReplacing(original.path, backup);
      try {
        _moveWithoutReplacing(copy.path, target);
      } catch (_) {
        try {
          _moveWithoutReplacing(backup, original.path);
        } catch (_) {
          throw _OriginalRetained(backup);
        }
        rethrow;
      }
      return SavedSongFile(
        SongFileDraft(
          EditableSongFile(target, name, identity),
          metadata,
          digest,
        ),
        size: stat.size,
        modified: stat.modified.millisecondsSinceEpoch,
      );
    }, sameVolume: true);
  }

  Future<T> _withCopy<T>(
    EditableSongFile file,
    Future<T> Function(File, Directory) action, {
    bool sameVolume = false,
  }) async {
    final android = Platform.isAndroid;
    final parent = !android && sameVolume
        ? Directory(p.dirname(file.location))
        : await getTemporaryDirectory();
    final directory = await parent.createTemp(_tempPrefix);
    var keepDirectory = false;
    try {
      final copy = File(p.join(directory.path, 'song${file.extension}'));
      if (android) {
        await _channel.invokeMethod<void>('copySong', {
          'uri': file.location,
          'path': copy.path,
        });
      } else {
        if (await FileSystemEntity.type(file.location, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const SongEditorException('歌曲文件不可访问，请重新选择');
        }
        await File(file.location).copy(copy.path);
      }
      return await action(copy, directory);
    } on _OriginalRetained {
      keepDirectory = true;
      rethrow;
    } finally {
      if (!keepDirectory) {
        try {
          // This directory was created for this one edit.
          await directory.delete(recursive: true);
        } on FileSystemException {
          // A transient cleanup failure cannot undo a completed save.
        }
      }
    }
  }
}

class _OriginalRetained extends SongEditorException {
  _OriginalRetained(String path) : super('保存失败，原歌曲仍保留在 $path');
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

// A Windows File.rename replaces an existing file. MoveFileW fails safely if
// another process creates the target between the check and the move.
void _moveWithoutReplacing(String source, String target) {
  if (!Platform.isWindows) {
    if (FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const SongEditorException('文件夹里已有同名文件');
    }
    File(source).renameSync(target);
    return;
  }
  final kernel = DynamicLibrary.open('kernel32.dll');
  final move = kernel
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)
      >('MoveFileW');
  final getLastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  using((arena) {
    final from = p.normalize(source).toNativeUtf16(allocator: arena);
    final to = p.normalize(target).toNativeUtf16(allocator: arena);
    if (move(from, to) == 0) {
      final code = getLastError();
      throw SongEditorException(switch (code) {
        80 || 183 => '文件夹里已有同名文件',
        5 || 32 => '文件无法修改，可能正在播放、被占用或没有写入权限',
        _ => '移动文件失败（Windows 错误 $code）',
      });
    }
  });
}

Future<Uint8List> compressSongCover(Uint8List bytes) => Isolate.run(() {
  final decoder = image.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 40 * 1000 * 1000) {
    throw const SongEditorException('图片无法读取或像素过大');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const SongEditorException('图片无法读取');
  final oriented = image.bakeOrientation(decoded);
  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final resized = longest <= 1000
      ? oriented
      : image.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1000 : null,
          height: oriented.height > oriented.width ? 1000 : null,
          interpolation: image.Interpolation.average,
        );
  // Embed JPEG for compatibility and flatten any alpha against white.
  final canvas = image.Image(width: resized.width, height: resized.height);
  image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(canvas, resized);
  return image.encodeJpg(canvas, quality: 85);
});

Future<SongFileMetadata> _readMetadata(String path) =>
    Isolate.run(() => _readTags(path));

TagLibFile _openTags(String path) =>
    TagLibFile.open(path) ?? (throw const SongEditorException('无法识别歌曲文件或标签'));

Picture? _coverPicture(List<Picture> pictures) =>
    pictures
        .where((picture) => picture.pictureType == 'Front Cover')
        .firstOrNull ??
    pictures.firstOrNull;

SongFileMetadata _readTags(String path, {Uint8List? expectedCover}) {
  final file = _openTags(path);
  try {
    final cover = _coverPicture(file.pictures);
    if (expectedCover != null &&
        (cover?.mimeType != 'image/jpeg' ||
            !_sameBytes(cover?.bytes, expectedCover))) {
      throw const SongEditorException('重新读取时封面不一致，保存已取消');
    }
    String? value(String text) => text.isEmpty ? null : text;
    return SongFileMetadata(
      title: value(file.title),
      artist: value(file.artist),
      album: value(file.album),
      duration: file.duration,
      pictureBytes: cover?.bytes,
    );
  } finally {
    file.close();
  }
}

Future<SongFileMetadata> writeSongFileTags(String path, SongEdits edits) =>
    Isolate.run(() {
      final file = _openTags(path);
      try {
        if (file.title != edits.title) file.title = edits.title;
        if (file.artist != edits.artist) file.artist = edits.artist;
        if (file.album != edits.album) file.album = edits.album;
        if (edits.cover case final bytes?) {
          final pictures = file.pictures;
          final previous = _coverPicture(pictures);
          final applied = file.setPictures([
            Picture(bytes: bytes, mimeType: 'image/jpeg'),
            for (final picture in pictures)
              if (!identical(picture, previous)) picture,
          ]);
          if (!applied) throw const SongEditorException('该歌曲的封面写入失败');
        }
        if (!file.save()) throw const SongEditorException('文件标签写入失败');
      } finally {
        file.close();
      }

      final verified = _readTags(path, expectedCover: edits.cover);
      if (verified.title != edits.title ||
          verified.artist != edits.artist ||
          (verified.album ?? '') != edits.album) {
        throw const SongEditorException('重新读取时标签不一致，保存已取消');
      }
      return verified;
    });

bool _sameBytes(Uint8List? actual, Uint8List expected) {
  if (actual == null || actual.length != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) return false;
  }
  return true;
}
