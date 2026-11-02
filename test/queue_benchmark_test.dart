import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/queue_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '10000-entry queue operations and separate playlist persistence benchmark',
    () async {
      final report = await runQueueBenchmark();
      final output = Platform.environment['TAG_MUSIC_QUEUE_REPORT'];
      if (output != null) {
        await File(output)
            .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
      for (final scenario in report['queueScenarios'] as List) {
        expect(
          scenario['p95Microseconds'],
          lessThanOrEqualTo(Platform.isAndroid ? 1000000 : 500000),
          reason: scenario['scenario'] as String,
        );
      }
    },
  );
}
