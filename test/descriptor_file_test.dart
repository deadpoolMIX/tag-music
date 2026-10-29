import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/playback/descriptor_file.dart';
import 'package:tag_music/playback/documents.dart';

class MemoryDescriptor implements DescriptorSource {
  MemoryDescriptor(this.bytes);
  final Uint8List bytes;
  @override
  int get length => bytes.length;
  @override
  Uint8List read(int offset, int count) =>
      Uint8List.fromList(bytes.sublist(offset, offset + count));
}

void main() {
  test(
    'descriptor cursor supports seek, EOF and close without path access',
    () {
      final file = DescriptorFile(
        MemoryDescriptor(Uint8List.fromList([10, 20, 30])),
      );
      final reader = file.openSync();
      expect(reader.lengthSync(), 3);
      expect(reader.readByteSync(), 10);
      reader.setPositionSync(2);
      expect(reader.readSync(100), [30]);
      expect(reader.readByteSync(), -1);
      reader.setPositionSync(0);
      final buffer = List<int>.filled(4, 0);
      expect(reader.readIntoSync(buffer, 1, 3), 2);
      expect(buffer, [0, 10, 20, 0]);
      reader.closeSync();
      expect(() => reader.readByteSync(), throwsA(isA<FileSystemException>()));
      expect(() => file.openSync(mode: FileMode.write), throwsUnsupportedError);
      expect(() => file.writeAsBytesSync([0]), throwsUnsupportedError);
      expect(file.openSync().positionSync(), 0);
    },
  );

  test(
    'six metadata formats parse through the borrowed descriptor adapter',
    () {
      final directory = Platform.environment['TAG_MUSIC_FIXTURES']!;
      for (final extension in ['wav', 'mp3', 'flac', 'm4a', 'ogg', 'opus']) {
        final bytes = File('$directory/中文测试-$extension.$extension')
            .readAsBytesSync();
        final original = Uint8List.fromList(bytes);
        final metadata = readFileMetadata(
          DescriptorFile(MemoryDescriptor(bytes)),
        );
        expect(metadata.title, '中文测试音', reason: extension);
        expect(metadata.artist, 'Tag Music', reason: extension);
        expect(
          bytes,
          original,
          reason: 'Borrowed descriptor must remain read-only',
        );
      }
    },
    skip: Platform.environment['TAG_MUSIC_FIXTURES'] == null
        ? 'Run scripts/check.ps1'
        : false,
  );
}
