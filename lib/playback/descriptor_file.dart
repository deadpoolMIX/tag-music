import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Borrowed read-only access. The Kotlin owner closes the descriptor after parsing.
abstract interface class DescriptorSource {
  int get length;
  Uint8List read(int offset, int count);
}

class AndroidDescriptorSource implements DescriptorSource {
  AndroidDescriptorSource(this.fd) {
    if (!Platform.isAndroid) {
      throw const FileSystemException(
        'Native descriptor metadata requires Android',
      );
    }
    final library = DynamicLibrary.open('libc.so');
    _seek = library
        .lookupFunction<
          Int64 Function(Int32, Int64, Int32),
          int Function(int, int, int)
        >('lseek64');
    _pread = library
        .lookupFunction<
          IntPtr Function(Int32, Pointer<Uint8>, UintPtr, Int64),
          int Function(int, Pointer<Uint8>, int, int)
        >('pread64');
    length = _seek(fd, 0, 2);
    if (length < 0) {
      throw const FileSystemException('Provider descriptor is not seekable');
    }
  }

  final int fd;
  late final int Function(int, int, int) _seek;
  late final int Function(int, Pointer<Uint8>, int, int) _pread;
  @override
  late final int length;

  @override
  Uint8List read(int offset, int count) {
    final buffer = calloc<Uint8>(count);
    try {
      final received = _pread(fd, buffer, count, offset);
      if (received < 0) {
        throw const FileSystemException('Cannot read provider descriptor');
      }
      return Uint8List.fromList(buffer.asTypedList(received));
    } finally {
      calloc.free(buffer);
    }
  }
}

/// File-shaped adapter required by audio_metadata_reader. It never opens a path.
class DescriptorFile implements File {
  DescriptorFile(this.source);
  final DescriptorSource source;

  @override
  String get path => 'borrowed-content-descriptor';
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    if (mode != FileMode.read) {
      throw UnsupportedError('Music descriptors are read-only');
    }
    return _DescriptorReader(source);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Read-only metadata adapter: ${invocation.memberName}',
  );
}

class _DescriptorReader implements RandomAccessFile {
  _DescriptorReader(this.source);
  final DescriptorSource source;
  int _position = 0;
  bool _closed = false;

  void _check() {
    if (_closed) throw const FileSystemException('Metadata reader is closed');
  }

  @override
  Uint8List readSync(int count) {
    _check();
    RangeError.checkNotNegative(count, 'count');
    final size = math.min(count, math.max(0, source.length - _position));
    if (size > 16 * 1024 * 1024) {
      throw const FileSystemException(
        'Metadata read exceeds the 16 MiB safety limit',
      );
    }
    if (size == 0) return Uint8List(0);
    final bytes = source.read(_position, size);
    _position += bytes.length;
    return bytes;
  }

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    final limit = RangeError.checkValidRange(start, end, buffer.length);
    final bytes = readSync(limit - start);
    buffer.setRange(start, start + bytes.length, bytes);
    return bytes.length;
  }

  @override
  int readByteSync() {
    final bytes = readSync(1);
    return bytes.isEmpty ? -1 : bytes.single;
  }

  @override
  void setPositionSync(int position) {
    _check();
    RangeError.checkNotNegative(position, 'position');
    _position = position;
  }

  @override
  int positionSync() {
    _check();
    return _position;
  }

  @override
  int lengthSync() {
    _check();
    return source.length;
  }

  @override
  void closeSync() {
    _closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Read-only metadata reader: ${invocation.memberName}',
  );
}
