import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = PreferencesSettingsStore();
  var mode = ThemeMode.system;
  String? warning;
  try {
    mode = decodeTheme(await store.readTheme());
  } catch (_) {
    warning = '无法读取主题设置，当前跟随系统。请检查存储空间后重新启动。';
  }
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        initialThemeProvider.overrideWithValue(mode),
        startupWarningProvider.overrideWithValue(warning),
      ],
      child: const TagMusicApp(),
    ),
  );
}
