import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/filter_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('10000-song three-box filter, search and sort benchmark', () async {
    final report = await runFilterBenchmark();
    final output = Platform.environment['TAG_MUSIC_FILTER_REPORT'];
    if (output != null) {
      await File(output)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    }
    for (final scenario in report['scenarios'] as List) {
      expect(
        scenario['warmFilterSearchSortP95Microseconds'],
        lessThanOrEqualTo(Platform.isAndroid ? 1000000 : 500000),
        reason: scenario['scenario'] as String,
      );
    }
  });
}
