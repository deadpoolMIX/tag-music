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
      debugPrint('R4_FILTER_BENCHMARK ${jsonEncode(report)}');
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
    });
  });
}
