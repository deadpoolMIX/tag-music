import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'descriptor_file.dart';
import 'cover_cache.dart';
import 'lyrics.dart';

const audioExtensions = {'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus'};

// R1 locators, not permanent song IDs. R2 introduces the persistent library.
class ProbeTrack {
  const ProbeTrack({
    required this.location,
    required this.name,
    this.size,
    this.modified,
  });
  final String location;
  final String name;
  final int? size;
  final int? modified;
}

class TrackMetadata {
  const TrackMetadata({this.title, this.artist, this.album, this.duration});
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
}

class ScannedFile {
  const ScannedFile({
    required this.identity,
    required this.location,
    required this.name,
    required this.relativePath,
    this.size,
    this.modified,
  });
  final String identity;
  final String location;
  final String name;
  final String relativePath;
  final int? size;
  final int? modified;
  ProbeTrack get probe => ProbeTrack(
    location: location,
    name: name,
    size: size,
    modified: modified,
  );
}

Uint8List? readFileCover(File file) {
  final pictures = readMetadata(file, getImage: true).pictures;
  // Embedded originals are read only on demand, never stored in the library.
  for (final picture in pictures) {
    if (picture.bytes.isNotEmpty && picture.bytes.length <= 8 * 1024 * 1024) {
      return Uint8List.fromList(picture.bytes);
    }
  }
  return null;
}

TrackMetadata readTrackMetadata(String path) => readFileMetadata(File(path));

TrackMetadata readDescriptorMetadata(int fd) =>
    readFileMetadata(DescriptorFile(AndroidDescriptorSource(fd)));

// Keep isolate entry closures outside DocumentAccess: its pending Future is
// intentionally unsendable, and nested closures may capture the outer context.
Future<TrackMetadata> _pathMetadata(String path) =>
    Isolate.run(() => readTrackMetadata(path));
Future<TrackMetadata> _fdMetadata(int fd) =>
    Isolate.run(() => readDescriptorMetadata(fd));
Future<Uint8List?> _pathCover(String path) =>
    Isolate.run(() => readFileCover(File(path)));
Future<Uint8List?> _fdCover(int fd) => Isolate.run(
  () => readFileCover(DescriptorFile(AndroidDescriptorSource(fd))),
);

Future<String> _pathHash(String path, int? size, int? modified) =>
    Isolate.run(() async {
      final file = File(path);
      final before = await file.stat();
      if ((size != null && before.size != size) ||
          (modified != null &&
              before.modified.millisecondsSinceEpoch != modified)) {
        throw const FileSystemException('扫描后文件已变化');
      }
      final digest = await sha256.bind(file.openRead()).first;
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const FileSystemException('计算期间文件已变化');
      }
      return digest.toString();
    });

TrackMetadata readFileMetadata(File source) {
  final data = readMetadata(source);
  // RIFF INFO has no universal charset marker. The parser returns Latin-1;
  // accept well-formed UTF-8 bytes, retaining the parser value otherwise.
  final file = source.openSync();
  late final bool riff;
  try {
    final header = file.readSync(12);
    riff =
        header.length == 12 &&
        ascii.decode(header.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(header.sublist(8, 12), allowInvalid: true) == 'WAVE';
  } finally {
    file.closeSync();
  }
  String? text(String? value) {
    if (!riff || value == null) return value;
    try {
      return utf8.decode(latin1.encode(value));
    } on FormatException {
      return value;
    } on ArgumentError {
      return value;
    }
  }

  return TrackMetadata(
    title: text(data.title),
    artist: text(data.artist),
    album: text(data.album),
    duration: data.duration,
  );
}

class DocumentAccess {
  DocumentAccess({bool? android, MethodChannel? channel})
    : android = android ?? Platform.isAndroid,
      channel = channel ?? const MethodChannel('app.tagmusic.player/documents');

  final bool android;
  final MethodChannel channel;
  late final _preferences = SharedPreferencesAsync();
  static const _rootsKey = 'r1.directoryLocations';
  Future<void> _reading = Future.value();
  Future<T> _read<T>(Future<T> Function() action) {
    final result = _reading.then((_) => action());
    _reading = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<List<String>> roots() async =>
      await _preferences.getStringList(_rootsKey) ?? [];

  Future<void> clearDirectoryBookmarks() => _preferences.remove(_rootsKey);

  Future<String?> selectMusicDirectory({bool temporary = false}) => android
      ? channel.invokeMethod<String>('pickDirectory', {'temporary': temporary})
      : getDirectoryPath(confirmButtonText: '选择音乐文件夹');

  Future<void> persistMusicDirectory(String root) async {
    if (android) {
      await channel.invokeMethod<void>('persistMusicDirectory', {'uri': root});
    }
  }

  Future<String> musicHash(ProbeTrack track) async => android
      ? (await channel.invokeMethod<String>('hashMusic', {
          'uri': track.location,
          'size': track.size,
          'modified': track.modified,
        }))!
      : _pathHash(track.location, track.size, track.modified);

  Future<void> cancelMusicHash() async {
    if (android) await channel.invokeMethod<void>('cancelMusicHash');
  }

  Future<String?> pickDirectory() async {
    final root = await selectMusicDirectory();
    if (root != null) {
      final saved = await roots();
      if (!saved.contains(root)) {
        await _preferences.setStringList(_rootsKey, [...saved, root]);
      }
    }
    return root;
  }

  Future<void> forgetDirectory(String root) async {
    final saved = await roots();
    if (saved.contains(root)) {
      await _preferences.setStringList(
        _rootsKey,
        saved.where((location) => location != root).toList(),
      );
    }
  }

  Future<String> directoryName(String root) async {
    if (!android) {
      final name = p.basename(p.normalize(root));
      return name.isEmpty ? '磁盘根目录' : name;
    }
    final name = await channel.invokeMethod<String>('directoryName', {
      'uri': root,
    });
    return name?.trim().isNotEmpty == true ? name! : '无法读取名称';
  }

  Future<List<ProbeTrack>> list(String root) async {
    if (android) {
      final rows = await channel.invokeListMethod<Map<Object?, Object?>>(
        'list',
        {'uri': root},
      );
      return [
        for (final row in rows ?? <Map<Object?, Object?>>[])
          ProbeTrack(
            location: row['location']! as String,
            name: row['name']! as String,
          ),
      ];
    }
    final tracks = <ProbeTrack>[];
    await for (final item in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (item is File &&
          audioExtensions.contains(item.path.split('.').last.toLowerCase())) {
        if (tracks.length >= 10000) throw StateError('R1 验证最多读取一万首');
        tracks.add(
          ProbeTrack(location: item.path, name: item.uri.pathSegments.last),
        );
      }
    }
    tracks.sort((a, b) => a.name.compareTo(b.name));
    return tracks;
  }

  Stream<ScannedFile> scan(
    String root, {
    required bool Function() cancelled,
  }) async* {
    if (android) {
      final token = (await channel.invokeMethod<int>('beginScan', {
        'uri': root,
      }))!;
      try {
        var done = false;
        while (!done && !cancelled()) {
          final page = (await channel.invokeMapMethod<String, Object?>(
            'nextScan',
            {'token': token},
          ))!;
          done = page['done'] == true;
          for (final raw in page['files']! as List) {
            if (cancelled()) return;
            final row = raw as Map;
            yield ScannedFile(
              identity: row['identity'] as String,
              location: row['location'] as String,
              name: row['name'] as String,
              relativePath: row['relativePath'] as String,
              size: row['size'] as int?,
              modified: row['modified'] as int?,
            );
          }
        }
      } finally {
        await channel.invokeMethod<void>('endScan', {'token': token});
      }
    } else {
      final directory = Directory(p.normalize(p.absolute(root)));
      await for (final item in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (cancelled()) return;
        if (item is! File ||
            !audioExtensions.contains(
              item.path.split('.').last.toLowerCase(),
            )) {
          continue;
        }
        final stat = await item.stat();
        if (stat.type != FileSystemEntityType.file) {
          throw FileSystemException('扫描期间文件不可访问', item.path);
        }
        final location = p.normalize(p.absolute(item.path));
        yield ScannedFile(
          identity: Platform.isWindows ? location.toLowerCase() : location,
          location: location,
          name: item.uri.pathSegments.last,
          relativePath: location
              .substring(directory.path.length)
              .replaceFirst(RegExp(r'^[/\\]'), ''),
          size: stat.size,
          modified: stat.modified.millisecondsSinceEpoch,
        );
      }
    }
  }

  Future<Uint8List?> cover(ProbeTrack track) => _read(() async {
    if (!android) return _pathCover(track.location);
    final fd = await open(track.location);
    try {
      return await _fdCover(fd);
    } finally {
      await close(fd);
    }
  });

  Future<String> saveCover(Uint8List bytes, String title) async {
    final (extension, mimeType) = _coverFormat(bytes);
    final cleaned = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final shortTitle = String.fromCharCodes(cleaned.runes.take(60)).trim();
    final suffix = const Uuid().v4().substring(0, 8);
    final name = '${shortTitle.isEmpty ? '封面' : shortTitle}-$suffix.$extension';
    if (android) {
      return (await channel.invokeMethod<String>('saveCover', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      }))!;
    }

    final downloads = await getDownloadsDirectory();
    if (downloads == null) throw StateError('无法找到下载目录');
    final directory = await Directory(p.join(downloads.path, 'Tag Music'))
        .create(recursive: true);
    final path = p.join(directory.path, name);
    final pending = File('$path.part');
    try {
      await pending.writeAsBytes(bytes, flush: true);
      await pending.rename(path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
    return path;
  }

  (String, String) _coverFormat(Uint8List bytes) {
    bool matches(int start, List<int> pattern) {
      if (bytes.length < start + pattern.length) return false;
      for (var i = 0; i < pattern.length; i++) {
        if (bytes[start + i] != pattern[i]) return false;
      }
      return true;
    }

    if (matches(0, [0xff, 0xd8, 0xff])) return ('jpg', 'image/jpeg');
    if (matches(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return ('png', 'image/png');
    }
    if (matches(0, ascii.encode('GIF8'))) return ('gif', 'image/gif');
    if (matches(0, ascii.encode('RIFF')) && matches(8, ascii.encode('WEBP'))) {
      return ('webp', 'image/webp');
    }
    if (matches(0, ascii.encode('BM'))) return ('bmp', 'image/bmp');
    if (matches(4, ascii.encode('ftypavif')) ||
        matches(4, ascii.encode('ftypavis'))) {
      return ('avif', 'image/avif');
    }
    throw const FormatException('无法识别原图格式');
  }

  final coverCache = CoverCache(cacheDirectory: getApplicationCacheDirectory);
  Future<Uint8List?> cachedCover(
    ProbeTrack track, {
    int targetSize = CoverCache.thumbnailSize,
    CoverPriority Function()? priority,
  }) {
    final size = targetSize.clamp(32, 1024);
    final key = (track.location, track.size, track.modified, size);
    final stableThumbnail =
        size == CoverCache.thumbnailSize &&
        track.size != null &&
        track.modified != null &&
        track.modified! > 0;
    final diskKey = stableThumbnail
        ? '${sha256.convert(utf8.encode(jsonEncode([key.$1, key.$2, key.$3, key.$4])))}.png'
        : null;
    return coverCache.get(
      key,
      size,
      () => cover(track),
      diskKey: diskKey,
      priority: priority,
    );
  }

  Future<Uri?> publishSessionArtwork(Uint8List png) async {
    final uri = await channel.invokeMethod<String>('publishSessionArtwork', {
      'bytes': png,
    });
    return uri == null ? null : Uri.parse(uri);
  }

  Future<Uint8List?> lyrics(ProbeTrack track) async {
    if (android) {
      final uri = await channel.invokeMethod<String>('findLyrics', {
        'uri': track.location,
      });
      if (uri == null) return null;
      return channel.invokeMethod<Uint8List>('readLyrics', {'uri': uri});
    }
    final file = File(p.setExtension(track.location, '.lrc'));
    if (!await file.exists()) return null;
    final handle = await file.open();
    try {
      final data = await handle.read(maxLyricsBytes + 1);
      if (data.length > maxLyricsBytes) {
        throw const FormatException('歌词超过 1MiB 上限');
      }
      return data;
    } finally {
      await handle.close();
    }
  }

  Future<int> open(String uri) async =>
      (await channel.invokeMethod<int>('open', {'uri': uri}))!;

  Future<void> close(int fd) => channel.invokeMethod<void>('close', {'fd': fd});

  Future<TrackMetadata> metadata(ProbeTrack track) => _read(() async {
    if (!android) return _pathMetadata(track.location);
    final fd = await open(track.location);
    try {
      // Read the already-authorized descriptor directly. Reopening /proc/self/fd
      // can be denied by Android providers/SELinux even though the fd is readable.
      return await _fdMetadata(fd);
    } finally {
      await close(fd);
    }
  });

  Future<Map<Object?, Object?>> diagnostics() async => android
      ? await channel.invokeMapMethod<Object?, Object?>('diagnostics') ?? {}
      : {};

  Future<bool> notificationsEnabled() async =>
      !android ||
      await channel.invokeMethod<bool>('notificationsEnabled') == true;

  Future<bool> requestNotifications() async =>
      !android ||
      await channel.invokeMethod<bool>('requestNotifications') == true;

  Future<void> openNotificationSettings() async {
    if (android) await channel.invokeMethod<void>('openNotificationSettings');
  }
}
