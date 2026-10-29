import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveEvidence(WidgetTester tester, String name) async {
    final directory = Platform.environment['TAG_MUSIC_EVIDENCE'];
    if (!Platform.isWindows || directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(AppShell),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('native settings persist across application reinitialization', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    await saveEvidence(tester, 'windows-native-library');
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
    await saveEvidence(tester, 'windows-native-settings-dark');
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
