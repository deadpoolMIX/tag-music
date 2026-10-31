import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/filter_benchmark.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device synthetic 10000-song three-box filter benchmark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final report = await runFilterBenchmark();
      binding.reportData = report;
      for (final scenario in report['scenarios'] as List) {
        expect(
          scenario['warmFilterSearchSortP95Microseconds'],
          lessThanOrEqualTo(Platform.isAndroid ? 1000000 : 500000),
          reason: scenario['scenario'] as String,
        );
      }
      const output = String.fromEnvironment('FILTER_BENCHMARK_OUTPUT');
      if (output.isNotEmpty) {
        await File(output)
            .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
      // Keep every Android log message below the observed 1023-character cap.
      // Base64 gives fixed ASCII boundaries even when report text is Unicode.
      final payload = base64Encode(utf8.encode(jsonEncode(report)));
      const chunkSize = 600;
      final count = (payload.length / chunkSize).ceil();
      debugPrintSynchronously('R4_REPORT_BEGIN $count ${payload.length}');
      for (var index = 0; index < count; index++) {
        final start = index * chunkSize;
        final end = (start + chunkSize).clamp(0, payload.length);
        debugPrintSynchronously(
          'R4_REPORT_PART ${index + 1}/$count ${payload.substring(start, end)}',
        );
      }
      debugPrintSynchronously('R4_REPORT_END $count ${payload.length}');
    });
  });
}
