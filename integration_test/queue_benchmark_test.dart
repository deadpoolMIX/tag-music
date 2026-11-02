import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/queue_benchmark.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('device isolated 10000-entry queue and playlist benchmark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final report = await runQueueBenchmark();
      binding.reportData = report;
      const output = String.fromEnvironment('QUEUE_BENCHMARK_OUTPUT');
      if (output.isNotEmpty) {
        final file = File(output);
        if (await file.exists()) {
          throw StateError('Benchmark report already exists: $output');
        }
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
      }
      final payload = base64Encode(utf8.encode(jsonEncode(report)));
      const size = 600;
      final count = (payload.length / size).ceil();
      debugPrintSynchronously('R5_REPORT_BEGIN $count ${payload.length}');
      for (var i = 0; i < count; i++) {
        debugPrintSynchronously(
          'R5_REPORT_PART ${i + 1}/$count ${payload.substring(i * size, ((i + 1) * size).clamp(0, payload.length))}',
        );
      }
      debugPrintSynchronously('R5_REPORT_END $count ${payload.length}');
      for (final scenario in report['queueScenarios'] as List) {
        expect(
          scenario['p95Microseconds'],
          lessThanOrEqualTo(Platform.isAndroid ? 1000000 : 500000),
          reason: scenario['scenario'] as String,
        );
      }
    });
  });
}
