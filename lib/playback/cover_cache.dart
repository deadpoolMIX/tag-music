import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

enum CoverPriority { stale, deferred, nearby, visible, artwork, current }

/// Only one file extraction is queued at a time. Recheck the callers just
/// before starting it, so fast scrolling does not leave a backlog of old rows.
class CoverCache {
  CoverCache({Future<Directory> Function()? cacheDirectory})
    : _disk = cacheDirectory == null ? null : _ThumbnailDisk(cacheDirectory);

  final _ThumbnailDisk? _disk;
  final _entries = <Object, Uint8List?>{};
  final _pending = <Object, _CoverRequest>{};
  bool _busy = false, _scheduled = false;
  int bytes = 0;
  static const byteLimit = 12 * 1024 * 1024;
  static const entryLimit = 384;
  static const thumbnailSize = 96;

  Future<Uint8List?> get(
    Object key,
    int size,
    Future<Uint8List?> Function() read, {
    String? diskKey,
    CoverPriority Function()? priority,
  }) {
    if (_entries.containsKey(key)) {
      final value = _entries.remove(key);
      _entries[key] = value;
      return Future.value(value);
    }
    final request = _pending.putIfAbsent(
      key,
      () => _CoverRequest(key, size, diskKey, read),
    );
    request.callers.add(priority ?? _visible);
    if (priority == null) {
      _startNext();
    } else {
      resume();
    }
    return request.result.future;
  }

  static CoverPriority _visible() => CoverPriority.visible;

  void resume() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _startNext();
    });
  }

  void _startNext() {
    if (_busy) return;
    _CoverRequest? next;
    var highest = CoverPriority.deferred;
    _pending.removeWhere((_, request) {
      final priority = request.priority;
      if (priority == CoverPriority.stale) {
        request.result.complete(null);
        return true;
      }
      if (priority.index > highest.index) {
        next = request;
        highest = priority;
      }
      return false;
    });
    if (next case final request?) {
      _busy = true;
      unawaited(_load(request));
    }
  }

  Future<void> _load(_CoverRequest request) async {
    Uint8List? result;
    try {
      final diskKey = request.diskKey;
      final disk = _disk;
      if (disk != null && diskKey != null) result = await disk.read(diskKey);
      if (result == null &&
          request.priority.index > CoverPriority.deferred.index) {
        result = await _resize(request.size, request.read);
        if (result != null && diskKey != null) disk?.write(diskKey, result);
      } else if (result == null && request.priority == CoverPriority.deferred) {
        return;
      }
      _pending.remove(request.key);
      if (result != null || request.priority != CoverPriority.stale) {
        _entries[request.key] = result;
        bytes += result?.length ?? 0;
        while (_entries.length > entryLimit || bytes > byteLimit) {
          bytes -= _entries.remove(_entries.keys.first)?.length ?? 0;
        }
      }
      request.result.complete(result);
    } finally {
      _busy = false;
      resume();
    }
  }

  static Future<Uint8List?> _resize(
    int size,
    Future<Uint8List?> Function() read,
  ) async {
    Uint8List? result;
    try {
      final raw = await read();
      if (raw != null && raw.length <= 8 * 1024 * 1024) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            if (descriptor.width <= 4096 &&
                descriptor.height <= 4096 &&
                descriptor.width * descriptor.height <= 16000000) {
              final largest = descriptor.width > descriptor.height
                  ? descriptor.width
                  : descriptor.height;
              final ratio = largest > size ? size / largest : 1.0;
              final codec = await descriptor.instantiateCodec(
                targetWidth: (descriptor.width * ratio).round().clamp(1, size),
                targetHeight: (descriptor.height * ratio).round().clamp(
                  1,
                  size,
                ),
              );
              try {
                final frame = await codec.getNextFrame();
                try {
                  final data = await frame.image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  result = data?.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  );
                } finally {
                  frame.image.dispose();
                }
              } finally {
                codec.dispose();
              }
            }
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
      }
    } catch (_) {
      return null;
    }
    return result != null && result.length <= byteLimit ? result : null;
  }
}

class _CoverRequest {
  _CoverRequest(this.key, this.size, this.diskKey, this.read);

  final Object key;
  final int size;
  final String? diskKey;
  final Future<Uint8List?> Function() read;
  final result = Completer<Uint8List?>();
  final callers = <CoverPriority Function()>[];

  CoverPriority get priority {
    var highest = CoverPriority.stale;
    callers.removeWhere((caller) {
      final priority = caller();
      if (priority.index > highest.index) highest = priority;
      return priority == CoverPriority.stale;
    });
    return highest;
  }
}

class _ThumbnailDisk {
  _ThumbnailDisk(this._cacheDirectory);

  final Future<Directory> Function() _cacheDirectory;
  static const _limit = 64 * 1024 * 1024;
  static const _maxThumbnailBytes = 64 * 1024;
  static final _fileName = RegExp(r'^[0-9a-f]{64}\.png$');
  final _writes = <String, Uint8List>{};
  Map<String, int>? _files;
  int _bytes = 0;
  bool _writing = false;
  late final _directory = _open();

  Future<Directory?> _open() async {
    try {
      final root = await _cacheDirectory();
      return await Directory(p.join(root.path, 'thumbnails-v1'))
          .create(recursive: true);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> read(String key) async {
    final queued = _writes[key];
    if (queued != null) return queued;
    try {
      final directory = await _directory;
      if (directory == null) return null;
      final file = File(p.join(directory.path, key));
      final length = await file.length();
      if (length > _maxThumbnailBytes || length < 20) return null;
      final data = await file.readAsBytes();
      if (data.length != length ||
          data[0] != 0x89 ||
          data[1] != 0x50 ||
          data[length - 5] != 0x44) {
        return null;
      }
      final files = _files;
      final knownLength = files?.remove(key);
      if (knownLength != null) files![key] = knownLength;
      unawaited(file.setLastModified(DateTime.now()).catchError((Object _) {}));
      return data;
    } catch (_) {
      return null;
    }
  }

  void write(String key, Uint8List bytes) {
    if (bytes.length > _maxThumbnailBytes) return;
    _writes[key] = bytes;
    if (_writes.length > 32) _writes.remove(_writes.keys.first);
    if (_writing) return;
    _writing = true;
    unawaited(_writePending());
  }

  Future<void> _writePending() async {
    try {
      final directory = await _directory;
      if (directory == null) return;
      final files = _files ??= await _index(directory);
      while (_writes.isNotEmpty) {
        final key = _writes.keys.first;
        final data = _writes.remove(key)!;
        final target = File(p.join(directory.path, key));
        final temporary = File(p.join(directory.path, '.write-$pid'));
        try {
          final previous = files[key] ?? 0;
          while (_bytes - previous + data.length > _limit) {
            final oldest = files.keys.firstWhere((name) => name != key);
            final oldFile = File(p.join(directory.path, oldest));
            if (await oldFile.exists()) await oldFile.delete();
            _bytes -= files.remove(oldest)!;
          }
          await temporary.writeAsBytes(data);
          await temporary.rename(target.path);
          _bytes -= files.remove(key) ?? 0;
          files[key] = data.length;
          _bytes += data.length;
        } on FileSystemException {
          // The system can clear the cache directory at any time.
          await directory.create(recursive: true);
        }
      }
    } catch (_) {
      // The disk cache is optional. In-memory images remain available.
    } finally {
      _writes.clear();
      _writing = false;
    }
  }

  Future<Map<String, int>> _index(Directory directory) async {
    final entries = <(String, FileStat)>[];
    await for (final file in directory.list(followLinks: false)) {
      final name = p.basename(file.path);
      if (file is! File || !_fileName.hasMatch(name)) continue;
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.file) entries.add((name, stat));
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    _bytes = entries.fold(0, (total, entry) => total + entry.$2.size);
    return {for (final (name, stat) in entries) name: stat.size};
  }
}
