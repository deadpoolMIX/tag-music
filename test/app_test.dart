import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/core/settings.dart';

import 'settings_test.dart' show MemorySettings;

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Tag Music',
      packageName: 'app.tagmusic.player',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(MemorySettings())],
        child: const TagMusicApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mobile navigation, theme and package version', (tester) async {
    await open(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('让音乐有自己的归属'), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('版本 0.1.0+1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop uses sidebar and navigates placeholders', (
    tester,
  ) async {
    await open(tester, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    expect(find.text('用标签连接每一种喜好'), findsOneWidget);
    await tester.tap(find.text('歌单'));
    await tester.pumpAndSettle();
    expect(find.text('留住每一次灵感'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen and large text can scroll settings', (
    tester,
  ) async {
    await open(tester, const Size(320, 568));
    final context = tester.element(find.byType(AppShell));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsStoreProvider.overrideWithValue(MemorySettings())],
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: const TagMusicApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('开源许可'), 200);
    expect(tester.takeException(), isNull);
  });
}
