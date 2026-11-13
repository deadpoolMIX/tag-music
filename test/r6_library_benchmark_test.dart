import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/r6_library_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('R6 actual query APIs: 10000-song sort/search cold and cache-hit raw host observations', () async {
    final report = await runR6LibraryBenchmark();
    final scenes = report['scenes'] as List;
    expect(scenes, hasLength(14));
    for (final scene in scenes) {
      expect(scene['samples'], hasLength(20));
      expect(scene['memorySamplesBytes'], hasLength(20));
      expect(scene['warmupCount'], 5);
      expect(
        (scene['observations'] as List).every(
          (row) => row['oracleVerified'] == true,
        ),
        isTrue,
      );
    }
    final output = Platform.environment['TAG_MUSIC_R6_LIBRARY_REPORT'];
    if (output != null) {
      final file = File(output);
      if (await file.exists()) {
        throw StateError(
          'Preserve earlier R6 evidence: $output already exists',
        );
      }
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
    }
  });
}
