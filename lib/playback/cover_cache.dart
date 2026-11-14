import 'dart:typed_data';
import 'dart:ui' as ui;

/// Compressed, resized images only. Pending work is shared, failures are cached.
class CoverCache {
  final _entries = <Object, Uint8List?>{};
  final _pending = <Object, Future<Uint8List?>>{};
  int bytes = 0;
  static const byteLimit = 12 * 1024 * 1024;
  static const entryLimit = 128;

  Future<Uint8List?> get(
    Object key,
    int size,
    Future<Uint8List?> Function() read,
  ) {
    if (_entries.containsKey(key)) {
      final value = _entries.remove(key);
      _entries[key] = value;
      return Future.value(value);
    }
    final future = _pending.putIfAbsent(key, () async {
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
                  targetWidth: (descriptor.width * ratio).round().clamp(
                    1,
                    size,
                  ),
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
                    result = data?.buffer.asUint8List();
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
        result = null;
      }
      _pending.remove(key);
      if (result != null && result.length > byteLimit) result = null;
      _entries[key] = result;
      bytes += result?.length ?? 0;
      while (_entries.length > entryLimit || bytes > byteLimit) {
        bytes -= _entries.remove(_entries.keys.first)?.length ?? 0;
      }
      return result;
    });
    return future.whenComplete(() => _pending.remove(key));
  }
}
