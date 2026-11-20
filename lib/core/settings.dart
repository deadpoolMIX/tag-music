import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SettingsStore {
  Future<String?> readTheme();
  Future<void> writeTheme(String value);
}

class PreferencesSettingsStore implements SettingsStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> readTheme() => _preferences.getString('settings.v1.theme');

  @override
  Future<void> writeTheme(String value) =>
      _preferences.setString('settings.v1.theme', value);

  Future<String?> readThemeColor() =>
      _preferences.getString('settings.v1.themeColor');

  Future<void> writeThemeColor(String value) =>
      _preferences.setString('settings.v1.themeColor', value);

  Future<double?> readDesktopVolume() =>
      _preferences.getDouble('settings.v1.desktopVolume');

  Future<void> writeDesktopVolume(double value) =>
      _preferences.setDouble('settings.v1.desktopVolume', value);

  Future<int?> readDesktopScale() =>
      _preferences.getInt('settings.v1.desktopScale');

  Future<void> writeDesktopScale(int value) =>
      _preferences.setInt('settings.v1.desktopScale', value);
}

enum ThemeColor {
  blue('海蓝', Color(0xFF006CCA)),
  purple('紫色', Color(0xFF6941CC)),
  rose('玫红', Color(0xFFB72960)),
  amber('琥珀', Color(0xFFA45B00));

  const ThemeColor(this.label, this.seed);
  final String label;
  final Color seed;

  static ThemeColor decode(String? value) =>
      values.firstWhere((color) => color.name == value, orElse: () => blue);
}

ThemeMode decodeTheme(String? value) => ThemeMode.values.firstWhere(
  (mode) => mode.name == value,
  orElse: () => ThemeMode.system,
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => PreferencesSettingsStore(),
);
final initialThemeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);
final themeColorStoreProvider = Provider((ref) => PreferencesSettingsStore());
final initialThemeColorProvider = Provider((ref) => ThemeColor.blue);
final startupWarningProvider = Provider<String?>((ref) => null);
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeProvider);

  Future<void> select(ThemeMode mode) async {
    await ref.read(settingsStoreProvider).writeTheme(mode.name);
    state = mode;
  }
}

final themeColorProvider = NotifierProvider<ThemeColorController, ThemeColor>(
  ThemeColorController.new,
);

class ThemeColorController extends Notifier<ThemeColor> {
  @override
  ThemeColor build() => ref.watch(initialThemeColorProvider);

  Future<void> select(ThemeColor color) async {
    await ref.read(themeColorStoreProvider).writeThemeColor(color.name);
    state = color;
  }
}

const desktopScaleOptions = [80, 90, 100, 110, 125, 150];
const defaultDesktopScale = 100;
final desktopScaleStoreProvider = Provider((ref) => PreferencesSettingsStore());
final initialDesktopScaleProvider = Provider((ref) => defaultDesktopScale);
final desktopScaleProvider = NotifierProvider<DesktopScaleController, int>(
  DesktopScaleController.new,
);

class DesktopScaleController extends Notifier<int> {
  @override
  int build() => ref.watch(initialDesktopScaleProvider);

  Future<void> select(int scale) async {
    await ref.read(desktopScaleStoreProvider).writeDesktopScale(scale);
    state = scale;
  }
}
