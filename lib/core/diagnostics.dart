import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

const gitRevision = String.fromEnvironment(
  'GIT_REVISION',
  defaultValue: 'uncommitted',
);

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

String diagnosticReport(PackageInfo info) =>
    '''Tag Music
版本：${info.version}+${info.buildNumber}
应用标识：${info.packageName}
轮次：R0
代码：$gitRevision
系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Dart：${Platform.version.split(' ').first}
''';
