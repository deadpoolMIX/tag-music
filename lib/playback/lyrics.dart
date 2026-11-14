import 'dart:convert';

import 'package:flutter/foundation.dart';

const maxLyricsBytes = 1024 * 1024;

enum LyricsStatus { ready, loading, missing, untimed, unreadable }

class LyricLine {
  const LyricLine(this.milliseconds, this.texts);
  final int milliseconds;
  final List<String> texts;
  String get original => texts.first;
}

class Lyrics {
  const Lyrics(this.lines, {this.message, this.status = LyricsStatus.ready});
  final List<LyricLine> lines;
  final String? message;
  final LyricsStatus status;
  static const empty = Lyrics(
    [],
    message: '未找到同目录同名 LRC 歌词',
    status: LyricsStatus.missing,
  );
  int indexAt(Duration position) {
    var low = 0, high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].milliseconds <= position.inMilliseconds) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }
}

String decodeLyrics(Uint8List bytes) {
  if (bytes.length > maxLyricsBytes) {
    throw const FormatException('歌词超过 1MiB 上限');
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 歌词损坏');
    final little = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      );
    }
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('UTF-16 歌词损坏');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('UTF-16 歌词损坏');
      }
    }
    return String.fromCharCodes(units);
  }
  try {
    final text = utf8.decode(bytes);
    if (text.contains('\u0000')) {
      throw const FormatException('需要 UTF-8 或带 BOM 的 UTF-16 歌词');
    }
    return text.startsWith('\ufeff') ? text.substring(1) : text;
  } on FormatException {
    throw const FormatException('歌词编码不支持或已损坏；请使用 UTF-8 或带 BOM 的 UTF-16');
  }
}

Lyrics parseLyrics(Uint8List bytes) {
  final source = decodeLyrics(bytes);
  final timestamp = RegExp(r'\[(\d+):(\d{1,2})(?:\.(\d{1,3}))?\]');
  final offsetPattern = RegExp(
    r'^\[offset:([+-]?\d+)\]$',
    caseSensitive: false,
  );
  var offset = 0;
  final groups = <int, List<String>>{};
  for (final raw in const LineSplitter().convert(source)) {
    final row = raw.trim();
    final offsetMatch = offsetPattern.firstMatch(row);
    if (offsetMatch != null) {
      offset = int.parse(offsetMatch[1]!);
      continue;
    }
    final stamps = timestamp.allMatches(row).toList();
    if (stamps.isEmpty) continue;
    final text = row.substring(stamps.last.end).trim();
    if (text.isEmpty) continue;
    for (final stamp in stamps) {
      final seconds = int.parse(stamp[2]!);
      if (seconds >= 60) throw const FormatException('歌词时间戳损坏');
      final time =
          int.parse(stamp[1]!) * 60000 +
          seconds * 1000 +
          int.parse((stamp[3] ?? '').padRight(3, '0'));
      (groups[time] ??= []).add(text);
      if (groups.length > 10000) {
        throw const FormatException('歌词超过 10000 个时间点上限');
      }
    }
  }
  final shifted = <int, List<String>>{};
  for (final entry in groups.entries) {
    (shifted[(entry.key + offset).clamp(0, 0x7fffffffffffffff)] ??= []).addAll(
      entry.value,
    );
  }
  final times = shifted.keys.toList()..sort();
  return Lyrics(
    [
      for (final time in times)
        LyricLine(time, List.unmodifiable(shifted[time]!)),
    ],
    message: times.isEmpty ? '歌词没有可用时间戳' : null,
    status: times.isEmpty ? LyricsStatus.untimed : LyricsStatus.ready,
  );
}

/// A shared timeline owns selection identity independently of delayed I/O.
class LyricsTimeline extends ChangeNotifier {
  int _generation = 0;
  bool _disposed = false;
  Lyrics value = Lyrics.empty;
  void clear() {
    _generation++;
    value = Lyrics.empty;
    if (!_disposed) notifyListeners();
  }

  Future<void> load(Future<Uint8List?> Function() read) async {
    final generation = ++_generation;
    value = const Lyrics([], message: '正在读取歌词', status: LyricsStatus.loading);
    if (!_disposed) notifyListeners();
    Lyrics next;
    try {
      final bytes = await read();
      next = bytes == null ? Lyrics.empty : parseLyrics(bytes);
    } catch (error) {
      next = Lyrics(
        [],
        message: '歌词不可读：$error',
        status: LyricsStatus.unreadable,
      );
    }
    if (_disposed || generation != _generation) return;
    value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
