import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'descriptor_file.dart';

const audioExtensions = {'mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus'};

// R1 locators, not permanent song IDs. R2 introduces the persistent library.
class ProbeTrack {
  const ProbeTrack({required this.location, required this.name});
  final String location;
  final String name;
}

class TrackMetadata {
  const TrackMetadata({this.title, this.artist, this.album, this.duration});
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
}

TrackMetadata readTrackMetadata(String path) => readFileMetadata(File(path));

TrackMetadata readDescriptorMetadata(int fd) =>
    readFileMetadata(DescriptorFile(AndroidDescriptorSource(fd)));

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

  Future<List<String>> roots() async =>
      await _preferences.getStringList(_rootsKey) ?? [];

  Future<String?> pickDirectory() async {
    final root = android
        ? await channel.invokeMethod<String>('pickDirectory')
        : await getDirectoryPath(confirmButtonText: '选择音乐文件夹');
    if (root != null) {
      final saved = await roots();
      if (!saved.contains(root)) {
        await _preferences.setStringList(_rootsKey, [...saved, root]);
      }
    }
    return root;
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

  Future<int> open(String uri) async =>
      (await channel.invokeMethod<int>('open', {'uri': uri}))!;

  Future<void> close(int fd) => channel.invokeMethod<void>('close', {'fd': fd});

  Future<TrackMetadata> metadata(ProbeTrack track) async {
    if (!android) return Isolate.run(() => readTrackMetadata(track.location));
    final fd = await open(track.location);
    try {
      // Read the already-authorized descriptor directly. Reopening /proc/self/fd
      // can be denied by Android providers/SELinux even though the fd is readable.
      return await Isolate.run(() => readDescriptorMetadata(fd));
    } finally {
      await close(fd);
    }
  }

  Future<Map<Object?, Object?>> diagnostics() async => android
      ? await channel.invokeMapMethod<Object?, Object?>('diagnostics') ?? {}
      : {};
}
