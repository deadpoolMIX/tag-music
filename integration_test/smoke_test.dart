import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native settings persist across application reinitialization', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.textContaining('版本 0.1.0+'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('copy-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.text('诊断信息已复制'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.main();
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-system')));
    await tester.pumpAndSettle();
    expect(find.byType(TagMusicApp), findsOneWidget);
  });
}
